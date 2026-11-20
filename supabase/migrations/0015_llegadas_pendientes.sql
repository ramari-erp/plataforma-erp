-- =====================================================================
-- 0015_llegadas_pendientes.sql — Editar llegadas, información pendiente y excedente de contrato
--   * precio_provisional: el precio o el tipo de cambio aún no es el definitivo (no se ha pagado).
--   * Pendientes de una llegada: sin factura, precio provisional.
--   * Excedente de contrato: lo que una llegada rebasó de lo contratado; se registra al precio del contrato.
--   * Quién modificó la llegada.
-- =====================================================================

alter table llegadas_mp add column precio_provisional boolean not null default false;
alter table llegadas_mp add column modificado_por uuid references auth.users (id);

create or replace function trg_modifico_llegada() returns trigger language plpgsql as $$
begin
  new.modificado_por := auth.uid();
  return new;
end $$;
create trigger modifico before update on llegadas_mp for each row execute function trg_modifico_llegada();

-- Historial de llegadas (columnas nuevas al final).
create or replace view v_llegadas with (security_invoker = true) as
select l.id, l.fecha, l.kg_bruto, l.kg_tara, l.kg_neto, l.humedad_pct, l.precio_kg, l.total,
       l.factura, l.boleta, l.notas, l.capturado_en,
       l.materia_prima_id, mp.nombre as materia_prima,
       l.proveedor_id, pr.nombre as proveedor,
       l.bodega_id, b.nombre as bodega,
       pf.nombre as capturado_por,
       l.contrato_id, coalesce(c.folio, '#' || c.id) as contrato, l.tipo_cambio,
       l.precio_provisional, c.moneda as moneda_contrato, c.precio as precio_contrato,
       -- Parte de esta llegada que rebasó lo contratado (diferencial), en orden de fecha
       case when l.contrato_id is null then 0 else
         greatest(0, sum(l.kg_neto) over w - c.kg_contratados) - greatest(0, sum(l.kg_neto) over w - l.kg_neto - c.kg_contratados)
       end as kg_excedente_contrato,
       array_remove(array[
         case when nullif(trim(l.factura), '') is null then 'factura' end,
         case when l.precio_provisional then 'precio' end
       ], null) as pendientes,
       pm.nombre as modificado_por, l.modificado_en
from llegadas_mp l
join materias_primas mp on mp.id = l.materia_prima_id
left join proveedores pr on pr.id = l.proveedor_id
left join bodegas b on b.id = l.bodega_id
left join perfiles pf on pf.id = l.capturado_por
left join contratos_mp c on c.id = l.contrato_id
left join perfiles pm on pm.id = l.modificado_por
window w as (partition by l.contrato_id order by l.fecha, l.id);


-- Contratos con el excedente surtido (columna nueva al final).
create or replace view v_contratos with (security_invoker = true) as
select c.id, c.folio, c.fecha, c.proveedor_id, pr.nombre as proveedor, c.materia_prima_id, mp.nombre as materia_prima,
       c.kg_contratados, c.moneda, c.precio, c.fecha_inicio, c.fecha_fin, c.estado, c.notas,
       coalesce(s.kg, 0) as kg_surtidos,
       greatest(c.kg_contratados - coalesce(s.kg, 0), 0) as kg_pendientes,
       round(100 * coalesce(s.kg, 0) / c.kg_contratados, 1) as pct_surtido,
       coalesce(s.n, 0) as llegadas, s.ultima as ultima_llegada,
       case when c.estado <> 'abierto' then c.estado
            when coalesce(s.kg, 0) >= c.kg_contratados then 'surtido'
            when c.fecha_fin < current_date then 'vencido'
            else 'abierto' end as estado_actual,
       c.fecha_fin - current_date as dias_para_vencer,
       pf.nombre as capturado_por,
       greatest(coalesce(s.kg, 0) - c.kg_contratados, 0) as kg_excedente
from contratos_mp c
join proveedores pr on pr.id = c.proveedor_id
join materias_primas mp on mp.id = c.materia_prima_id
left join perfiles pf on pf.id = c.capturado_por
left join lateral (
  select sum(l.kg_neto) as kg, count(*) as n, max(l.fecha) as ultima
  from llegadas_mp l where l.contrato_id = c.id
) s on true;
;
