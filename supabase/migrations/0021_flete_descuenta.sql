-- =====================================================================
-- 0021_flete_descuenta.sql — Corrige 0020: el flete NO se suma, se descuenta
--
--   El precio base México (CDMX) ya incluye el flete. Total de la venta (factura y cobranza) = kg netos × precio − descuento.
--   El flete (cajas × flete $/caja, según destino) lo paga la empresa: neto recibido = total − flete;
--   precio neto $/kg = neto ÷ kg netos.
-- =====================================================================

drop view v_saldos_clientes;
drop view v_ventas;
drop view v_venta_renglones;

-- Importe = kg netos × precio (o cantidad × precio si es por unidad); el flete va aparte en flete_importe.
create view v_venta_renglones with (security_invoker = true) as
with b as (
  select r.*, v.merma_kg_caja, v.flete_kg, v.flete_caja,
         round(coalesce(r.merma_kg, r.cantidad * v.merma_kg_caja), 2) as merma_calc,
         round(r.cantidad * v.flete_caja, 2) as flete_importe
  from venta_renglones r join ventas v on v.id = r.venta_id
)
select b.id, b.venta_id, b.granja_id, g.nombre as granja, b.calidad, b.cantidad, coalesce(b.kg, 0) as kg_brutos,
       b.merma_calc as merma_kg,
       coalesce(b.kg, 0) - b.merma_calc as kg_netos,
       case when b.cantidad > 0 and b.kg > 0 then round(b.kg / b.cantidad, 2) end as peso_promedio,
       b.precio_kg, b.flete_kg,
       case when b.precio_por = 'unidad' then b.precio_kg else b.precio_kg + b.flete_kg end as precio_total_kg,
       case when b.precio_por = 'unidad' then round(b.cantidad * b.precio_kg, 2)
            else round((coalesce(b.kg, 0) - b.merma_calc) * (b.precio_kg + b.flete_kg), 2)
       end as importe,
       b.presentacion, b.producto_id, p.nombre as producto, p.unidad, b.precio_por,
       b.flete_caja, b.flete_importe,
       case when coalesce(b.kg, 0) - b.merma_calc > 0 and b.precio_por = 'kg'
            then round(b.precio_kg + b.flete_kg - b.flete_importe / (coalesce(b.kg, 0) - b.merma_calc), 4) end as precio_neto_kg
from b
left join granjas g on g.id = b.granja_id
left join productos_venta p on p.id = b.producto_id;

-- Ventas: total = factura (precio base ya incluye flete); neto = total − flete que paga la empresa.
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
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento - coalesce(t.flete, 0)) / t.kg_netos, 4) end as precio_neto_kg
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


