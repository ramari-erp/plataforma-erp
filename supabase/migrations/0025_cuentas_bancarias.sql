-- =====================================================================
-- 0025_cuentas_bancarias.sql — A qué cuenta se depositó o transfirió cada cobro
--
--   cuentas_bancarias: catálogo de cuentas de la empresa (banco, terminación, razón social, moneda) más la caja de
--   efectivo. Se registra la cuenta en la venta (cobro de contado o anticipo) y en cada pago de cliente.
--   v_depositos junta todos los cobros por cuenta: base para la futura sección de Bancos.
-- =====================================================================

create table cuentas_bancarias (
  id                  bigint generated always as identity primary key,
  nombre              text not null unique,           -- cómo se le conoce: "BBVA Pecuaria 1234", "Caja efectivo"
  tipo                text not null default 'banco' check (tipo in ('banco', 'caja')),
  banco               text,
  numero              text,                            -- terminación o CLABE
  empresa_factura_id  bigint references empresas_factura (id),
  moneda              text not null default 'MXN' check (moneda in ('MXN', 'USD')),
  activa              boolean not null default true,
  creado_por          uuid references auth.users (id),
  creado_en           timestamptz default now()
);
select aplicar_seguridad('cuentas_bancarias', 'catalogos');
create policy capturar_ventas on cuentas_bancarias for insert to authenticated with check (puede_capturar('ventas'));
insert into cuentas_bancarias (nombre, tipo) values ('CAJA (EFECTIVO)', 'caja') on conflict (nombre) do nothing;

alter table ventas add column cuenta_id bigint references cuentas_bancarias (id);
alter table pagos_cliente add column cuenta_id bigint references cuentas_bancarias (id);

drop view v_saldos_clientes;
drop view v_pagos;
drop view v_ventas;

-- Ventas (igual que 0024 + cuenta de depósito al final).
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
       v.destino_colonia, v.destino_ciudad, v.destino_estado, v.aumento_centavos_kg,
       v.kg_bascula, coalesce(fc.n, 0) as num_facturas, fc.facturas, fc.facturado,
       v.cuenta_id, cb.nombre as cuenta
from ventas v
join clientes c on c.id = v.cliente_id
left join empresas_factura e on e.id = v.empresa_factura_id
left join cuentas_bancarias cb on cb.id = v.cuenta_id
left join perfiles pf on pf.id = v.capturado_por
left join perfiles pm on pm.id = v.modificado_por
left join lateral (
  select sum(r.cantidad) as cantidad, sum(r.kg_brutos) as kg_brutos, sum(r.merma_kg) as merma_kg, sum(r.kg_netos) as kg_netos,
         sum(r.importe) as importe, sum(r.flete_importe) as flete,
         string_agg(distinct r.calidad, ', ') as calidades, string_agg(distinct r.granja, ', ') as granjas,
         string_agg(distinct r.producto, ', ') as productos, string_agg(distinct r.presentacion, ', ') as presentaciones
  from v_venta_renglones r where r.venta_id = v.id
) t on true
left join lateral (select sum(a.monto) as pagado from pago_aplicaciones a where a.venta_id = v.id) pg on true
left join lateral (
  select count(*) as n, sum(f.monto) as facturado,
         string_agg(f.numero || coalesce(' · ' || ef.nombre, ''), ', ' order by f.id) as facturas
  from venta_facturas f left join empresas_factura ef on ef.id = f.empresa_factura_id where f.venta_id = v.id
) fc on true;





create view v_pagos with (security_invoker = true) as
select p.id, p.cliente_id, c.nombre as cliente, p.fecha, p.monto, p.moneda, p.tipo_cambio, p.forma, p.banco, p.referencia,
       p.factura, p.notas, coalesce(a.aplicado, 0) as aplicado, p.monto - coalesce(a.aplicado, 0) as sin_aplicar,
       a.ventas, pf.nombre as capturado_por, p.capturado_en,
       p.cuenta_id, cb.nombre as cuenta
from pagos_cliente p
join clientes c on c.id = p.cliente_id
left join cuentas_bancarias cb on cb.id = p.cuenta_id
left join perfiles pf on pf.id = p.capturado_por
left join lateral (
  select sum(pa.monto) as aplicado,
         string_agg(coalesce(v.folio, to_char(v.fecha, 'DD/MM')) || ' (' || to_char(pa.monto, 'FM999,999,990.00') || ')', ', ' order by v.fecha) as ventas
  from pago_aplicaciones pa join ventas v on v.id = pa.venta_id where pa.pago_id = p.id
) a on true;


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





-- Cobros por cuenta: ventas de contado (total), anticipos de ventas a crédito y pagos de clientes.
create view v_depositos with (security_invoker = true) as
select 'venta' as origen, v.id as origen_id, v.fecha, v.cliente_id, v.cliente, v.especie, v.folio,
       v.total as monto, v.moneda, v.cuenta_id, v.cuenta, 'Venta de contado' as concepto
from v_ventas v where v.forma_pago = 'contado' and v.total > 0
union all
select 'anticipo', v.id, v.fecha, v.cliente_id, v.cliente, v.especie, v.folio,
       v.anticipo, v.moneda, v.cuenta_id, v.cuenta, 'Anticipo de venta a crédito'
from v_ventas v where v.forma_pago = 'credito' and v.anticipo > 0
union all
select 'pago', p.id, p.fecha, p.cliente_id, p.cliente, null, p.referencia,
       p.monto, p.moneda, p.cuenta_id, p.cuenta, 'Pago de cliente'
from v_pagos p;

-- Guarda encabezado + renglones + facturas. Reemplaza la de 0024 (agrega cuenta de depósito).
create or replace function guardar_venta(p_venta jsonb, p_renglones jsonb, p_id bigint default null) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_cliente bigint := (p_venta->>'cliente_id')::bigint;
  v_bascula numeric := nullif(p_venta->>'kg_bascula', '')::numeric;
  v_cajas numeric;
begin
  -- Pesada única (huevo): los kg de báscula se reparten entre los renglones en proporción a las cajas;
  -- el último renglón se lleva el redondeo para que la suma sea exacta.
  if v_bascula > 0 then
    select sum(coalesce((x->>'cantidad')::numeric, 0)) into v_cajas from jsonb_array_elements(p_renglones) x;
    if coalesce(v_cajas, 0) <= 0 then raise exception 'Captura las cajas de cada renglón para repartir la pesada'; end if;
    select jsonb_agg(case when n = total_n then x || jsonb_build_object('kg', v_bascula - acumulado)
                          else x || jsonb_build_object('kg', kg) end order by n)
      into p_renglones
    from (select x, n, count(*) over () as total_n, kg,
                 coalesce(sum(kg) over (order by n rows between unbounded preceding and 1 preceding), 0) as acumulado
          from (select x, n, round(v_bascula * coalesce((x->>'cantidad')::numeric, 0) / v_cajas, 2) as kg
                from jsonb_array_elements(p_renglones) with ordinality as e (x, n)) a) b;
  end if;
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
                        destino_colonia, destino_ciudad, destino_estado, aumento_centavos_kg, kg_bascula, cuenta_id)
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
            nullif(trim(p_venta->>'destino_estado'), ''), nullif(p_venta->>'aumento_centavos_kg', '')::numeric,
            v_bascula, nullif(p_venta->>'cuenta_id', '')::bigint)
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
        destino_estado = nullif(trim(p_venta->>'destino_estado'), ''), aumento_centavos_kg = nullif(p_venta->>'aumento_centavos_kg', '')::numeric,
        kg_bascula = v_bascula, cuenta_id = nullif(p_venta->>'cuenta_id', '')::bigint
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

  -- Facturas: si se manda la lista, reemplaza las de la venta; ventas.factura guarda los números juntos.
  if p_venta ? 'facturas' then
    delete from venta_facturas where venta_id = v_id;
    insert into venta_facturas (venta_id, numero, empresa_factura_id, monto, fecha)
    select v_id, trim(f->>'numero'),
           coalesce(nullif(f->>'empresa_factura_id', '')::bigint, nullif(p_venta->>'empresa_factura_id', '')::bigint),
           nullif(f->>'monto', '')::numeric, nullif(f->>'fecha', '')::date
    from jsonb_array_elements(p_venta->'facturas') f
    where nullif(trim(f->>'numero'), '') is not null;
    update ventas set factura = (select string_agg(numero, ', ' order by id) from venta_facturas where venta_id = v_id) where id = v_id;
  end if;
  return v_id;
end $$;


-- Registra (o corrige) un pago. Reemplaza la de 0019 (agrega cuenta de depósito).
create or replace function registrar_pago(p_pago jsonb, p_aplicaciones jsonb default '[]', p_id bigint default null) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_cliente bigint := (p_pago->>'cliente_id')::bigint;
  v_moneda text := coalesce(nullif(p_pago->>'moneda', ''), 'MXN');
  v_monto numeric := (p_pago->>'monto')::numeric;
  x jsonb;
  v record;
begin
  if v_cliente is null then raise exception 'Elige el cliente'; end if;
  if coalesce(v_monto, 0) <= 0 then raise exception 'El monto del pago debe ser mayor a cero'; end if;
  if (select coalesce(sum((a->>'monto')::numeric), 0) from jsonb_array_elements(coalesce(p_aplicaciones, '[]')) a) > v_monto + 0.005 then
    raise exception 'Lo aplicado a las ventas es mayor que el pago';
  end if;

  if p_id is null then
    insert into pagos_cliente (cliente_id, fecha, monto, moneda, tipo_cambio, forma, banco, referencia, factura, notas, cuenta_id)
    values (v_cliente, (p_pago->>'fecha')::date, v_monto, v_moneda, nullif(p_pago->>'tipo_cambio', '')::numeric,
            coalesce(nullif(p_pago->>'forma', ''), 'transferencia'), nullif(trim(p_pago->>'banco'), ''),
            nullif(trim(p_pago->>'referencia'), ''), nullif(trim(p_pago->>'factura'), ''), nullif(trim(p_pago->>'notas'), ''),
            nullif(p_pago->>'cuenta_id', '')::bigint)
    returning id into v_id;
  else
    update pagos_cliente set cliente_id = v_cliente, fecha = (p_pago->>'fecha')::date, monto = v_monto, moneda = v_moneda,
        tipo_cambio = nullif(p_pago->>'tipo_cambio', '')::numeric, forma = coalesce(nullif(p_pago->>'forma', ''), 'transferencia'),
        banco = nullif(trim(p_pago->>'banco'), ''), referencia = nullif(trim(p_pago->>'referencia'), ''),
        factura = nullif(trim(p_pago->>'factura'), ''), notas = nullif(trim(p_pago->>'notas'), ''),
        cuenta_id = nullif(p_pago->>'cuenta_id', '')::bigint
      where id = p_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró el pago % o no tienes permiso para cambiarlo', p_id; end if;
    delete from pago_aplicaciones where pago_id = v_id;
  end if;

  for x in select * from jsonb_array_elements(coalesce(p_aplicaciones, '[]')) loop
    select vv.id, vv.cliente_id, vv.moneda, vv.saldo, vv.folio, vv.fecha into v from v_ventas vv where vv.id = (x->>'venta_id')::bigint;
    if v.id is null then raise exception 'No se encontró la venta %', x->>'venta_id'; end if;
    if v.cliente_id <> v_cliente then raise exception 'La venta del % es de otro cliente', to_char(v.fecha, 'DD/MM/YYYY'); end if;
    if v.moneda <> v_moneda then raise exception 'La venta del % es en %, el pago en %', to_char(v.fecha, 'DD/MM/YYYY'), v.moneda, v_moneda; end if;
    if (x->>'monto')::numeric > v.saldo + 0.005 then
      raise exception 'A la venta del % solo le quedan % de saldo', to_char(v.fecha, 'DD/MM/YYYY'), v.saldo;
    end if;
    insert into pago_aplicaciones (pago_id, venta_id, monto) values (v_id, v.id, (x->>'monto')::numeric);
  end loop;
  return v_id;
end $$;
