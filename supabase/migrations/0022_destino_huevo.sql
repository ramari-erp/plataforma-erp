-- =====================================================================
-- 0022_destino_huevo.sql — Huevo: sin flete; destino (colonia, ciudad, estado) y aumento al destino
--
--   El flete ya no se captura ni se descuenta (la empresa ya lo considera en su precio): flete_caja queda en 0.
--   aumento_centavos_kg = cuántos centavos por kg aumenta el precio en ese destino. Es solo un dato de referencia:
--   no cambia el precio, el total ni el saldo.
-- =====================================================================

alter table ventas add column destino_colonia text;
alter table ventas add column destino_ciudad text;
alter table ventas add column destino_estado text;
alter table ventas add column aumento_centavos_kg numeric(10,2) check (aumento_centavos_kg >= 0);

update ventas set flete_caja = 0 where flete_caja <> 0;

drop view v_saldos_clientes;
drop view v_ventas;

-- Ventas (igual que 0021 + destino desglosado y aumento al destino al final).
create view v_ventas with (security_invoker = true) as
select v.id, v.especie, v.fecha, v.cliente_id, c.nombre as cliente, c.rfc, v.destino,
       v.tipo_pago, v.empresa_factura_id, e.nombre as empresa_factura, v.factura, v.forma_pago, v.anticipo,
       v.flete_kg, v.merma_kg_caja, v.muertos, v.descuento, v.motivo_descuento, v.notas,
       coalesce(t.cantidad, 0) as cantidad, coalesce(t.kg_brutos, 0) as kg_brutos, coalesce(t.merma_kg, 0) as merma_kg,
       coalesce(t.kg_netos, 0) as kg_netos,
       case when t.cantidad > 0 and t.kg_brutos > 0 then round(t.kg_brutos / t.cantidad, 2) end as peso_promedio,
       coalesce(t.importe, 0) as subtotal,
       coalesce(t.importe, 0) - v.descuento as total,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento) / t.kg_netos, 4) end as precio_promedio_kg,
       case when v.forma_pago = 'contado' then 0
            else greatest(coalesce(t.importe, 0) - v.descuento - v.anticipo - coalesce(pg.pagado, 0), 0) end as saldo,
       t.calidades, t.granjas,
       pf.nombre as capturado_por, v.capturado_en, pm.nombre as modificado_por, v.modificado_en,
       v.folio, v.folio_externo, v.moneda, v.tipo_cambio,
       coalesce(pg.pagado, 0) as pagado, t.productos, t.presentaciones,
       v.flete_caja, coalesce(t.flete, 0) as flete_total,
       coalesce(t.importe, 0) - v.descuento - coalesce(t.flete, 0) as neto,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento - coalesce(t.flete, 0)) / t.kg_netos, 4) end as precio_neto_kg,
       v.destino_colonia, v.destino_ciudad, v.destino_estado, v.aumento_centavos_kg
from ventas v
join clientes c on c.id = v.cliente_id
left join empresas_factura e on e.id = v.empresa_factura_id
left join perfiles pf on pf.id = v.capturado_por
left join perfiles pm on pm.id = v.modificado_por
left join lateral (
  select sum(r.cantidad) as cantidad, sum(r.kg_brutos) as kg_brutos, sum(r.merma_kg) as merma_kg, sum(r.kg_netos) as kg_netos,
         sum(r.importe) as importe, sum(r.flete_importe) as flete,
         string_agg(distinct r.calidad, ', ') as calidades, string_agg(distinct r.granja, ', ') as granjas,
         string_agg(distinct r.producto, ', ') as productos, string_agg(distinct r.presentacion, ', ') as presentaciones
  from v_venta_renglones r where r.venta_id = v.id
) t on true
left join lateral (select sum(a.monto) as pagado from pago_aplicaciones a where a.venta_id = v.id) pg on true;



-- Saldo por cliente y moneda: lo que deben las ventas a crédito menos pagos sin aplicar.
create view v_saldos_clientes with (security_invoker = true) as
with ventas_c as (
  select cliente_id, moneda, count(*) filter (where saldo > 0) as ventas_con_saldo, sum(saldo) as saldo_ventas,
         sum(total) as vendido, min(fecha) filter (where saldo > 0) as venta_mas_antigua
  from v_ventas group by cliente_id, moneda
), pagos_c as (
  select cliente_id, moneda, sum(sin_aplicar) as a_favor, sum(monto) as pagado, max(fecha) as ultimo_pago
  from v_pagos group by cliente_id, moneda
)
select c.id as cliente_id, c.nombre as cliente, c.rfc, coalesce(v.moneda, p.moneda) as moneda,
       coalesce(v.vendido, 0) as vendido, coalesce(p.pagado, 0) as pagado,
       coalesce(v.ventas_con_saldo, 0) as ventas_con_saldo, coalesce(v.saldo_ventas, 0) as saldo_ventas,
       coalesce(p.a_favor, 0) as a_favor, coalesce(v.saldo_ventas, 0) - coalesce(p.a_favor, 0) as saldo,
       v.venta_mas_antigua, p.ultimo_pago
from ventas_c v
full join pagos_c p on p.cliente_id = v.cliente_id and p.moneda = v.moneda
join clientes c on c.id = coalesce(v.cliente_id, p.cliente_id);



-- Guarda encabezado + renglones. Reemplaza la de 0020 (agrega destino desglosado y aumento al destino).
create or replace function guardar_venta(p_venta jsonb, p_renglones jsonb, p_id bigint default null) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_cliente bigint := (p_venta->>'cliente_id')::bigint;
begin
  if v_cliente is null then raise exception 'Elige el cliente'; end if;
  if jsonb_array_length(coalesce(p_renglones, '[]')) = 0 then raise exception 'La venta necesita al menos un renglón'; end if;
  if p_venta->>'tipo_pago' = 'factura' and nullif(p_venta->>'empresa_factura_id', '') is null then
    raise exception 'Elige la razón social con la que se factura';
  end if;
  if exists (select 1 from jsonb_array_elements(p_renglones) x
             where coalesce(x->>'precio_por', 'kg') = 'kg' and coalesce((x->>'kg')::numeric, 0) <= 0) then
    raise exception 'Captura los kg de cada renglón que se cobra por kg';
  end if;

  if p_id is null then
    insert into ventas (especie, fecha, cliente_id, destino, tipo_pago, empresa_factura_id, factura, forma_pago, anticipo,
                        flete_kg, merma_kg_caja, muertos, descuento, motivo_descuento, notas, folio, folio_externo, moneda, tipo_cambio, flete_caja,
                        destino_colonia, destino_ciudad, destino_estado, aumento_centavos_kg)
    values (p_venta->>'especie', (p_venta->>'fecha')::date, v_cliente, nullif(trim(p_venta->>'destino'), ''),
            coalesce(p_venta->>'tipo_pago', 'factura'), nullif(p_venta->>'empresa_factura_id', '')::bigint,
            nullif(trim(p_venta->>'factura'), ''), coalesce(p_venta->>'forma_pago', 'contado'),
            coalesce((p_venta->>'anticipo')::numeric, 0), coalesce((p_venta->>'flete_kg')::numeric, 0),
            coalesce((p_venta->>'merma_kg_caja')::numeric, 0), coalesce((p_venta->>'muertos')::int, 0),
            coalesce((p_venta->>'descuento')::numeric, 0), nullif(trim(p_venta->>'motivo_descuento'), ''),
            nullif(trim(p_venta->>'notas'), ''), nullif(trim(p_venta->>'folio'), ''), nullif(trim(p_venta->>'folio_externo'), ''),
            coalesce(nullif(p_venta->>'moneda', ''), 'MXN'), nullif(p_venta->>'tipo_cambio', '')::numeric,
            coalesce(nullif(p_venta->>'flete_caja', '')::numeric, 0),
            nullif(trim(p_venta->>'destino_colonia'), ''), nullif(trim(p_venta->>'destino_ciudad'), ''),
            nullif(trim(p_venta->>'destino_estado'), ''), nullif(p_venta->>'aumento_centavos_kg', '')::numeric)
    returning id into v_id;
  else
    update ventas set fecha = (p_venta->>'fecha')::date, cliente_id = v_cliente,
        destino = nullif(trim(p_venta->>'destino'), ''), tipo_pago = coalesce(p_venta->>'tipo_pago', 'factura'),
        empresa_factura_id = nullif(p_venta->>'empresa_factura_id', '')::bigint, factura = nullif(trim(p_venta->>'factura'), ''),
        forma_pago = coalesce(p_venta->>'forma_pago', 'contado'), anticipo = coalesce((p_venta->>'anticipo')::numeric, 0),
        flete_kg = coalesce((p_venta->>'flete_kg')::numeric, 0), merma_kg_caja = coalesce((p_venta->>'merma_kg_caja')::numeric, 0),
        muertos = coalesce((p_venta->>'muertos')::int, 0), descuento = coalesce((p_venta->>'descuento')::numeric, 0),
        motivo_descuento = nullif(trim(p_venta->>'motivo_descuento'), ''), notas = nullif(trim(p_venta->>'notas'), ''),
        folio = nullif(trim(p_venta->>'folio'), ''), folio_externo = nullif(trim(p_venta->>'folio_externo'), ''),
        moneda = coalesce(nullif(p_venta->>'moneda', ''), 'MXN'), tipo_cambio = nullif(p_venta->>'tipo_cambio', '')::numeric,
        flete_caja = coalesce(nullif(p_venta->>'flete_caja', '')::numeric, 0),
        destino_colonia = nullif(trim(p_venta->>'destino_colonia'), ''), destino_ciudad = nullif(trim(p_venta->>'destino_ciudad'), ''),
        destino_estado = nullif(trim(p_venta->>'destino_estado'), ''), aumento_centavos_kg = nullif(p_venta->>'aumento_centavos_kg', '')::numeric
      where id = p_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró la venta % o no tienes permiso para cambiarla', p_id; end if;
    delete from venta_renglones where venta_id = v_id;
  end if;

  insert into venta_renglones (venta_id, granja_id, calidad, cantidad, kg, precio_kg, presentacion, producto_id, precio_por, merma_kg)
  select v_id, nullif(x->>'granja_id', '')::bigint, nullif(trim(x->>'calidad'), ''),
         coalesce((x->>'cantidad')::numeric, 0), nullif(x->>'kg', '')::numeric, (x->>'precio_kg')::numeric,
         nullif(trim(x->>'presentacion'), ''), nullif(x->>'producto_id', '')::bigint,
         coalesce(nullif(x->>'precio_por', ''), 'kg'), nullif(x->>'merma_kg', '')::numeric
  from jsonb_array_elements(p_renglones) x;
  return v_id;
end $$;

