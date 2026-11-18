-- =====================================================================
-- 0007_contratos_granos.sql — Contratos de materia prima y su corte con las llegadas
--
--   * Contrato: proveedor, materia prima, kg contratados, precio (MXN o USD), vigencia.
--   * Cada llegada puede ligarse a un contrato; lo surtido = suma de sus llegadas.
--   * Materias que requieren contrato (sorgo, maíz, pasta de soya): alerta si no hay contrato abierto
--     y cobertura en días según el consumo de los últimos 30 días.
-- =====================================================================

create table contratos_mp (
  id                bigint generated always as identity primary key,
  folio             text,
  proveedor_id      bigint not null references proveedores (id),
  materia_prima_id  bigint not null references materias_primas (id),
  fecha             date not null default current_date,           -- fecha en que se cerró el contrato
  kg_contratados    numeric(14,2) not null check (kg_contratados > 0),
  moneda            text not null default 'MXN' check (moneda in ('MXN', 'USD')),
  precio            numeric(12,4) not null check (precio >= 0),    -- por kg, en la moneda del contrato, con flete si aplica
  fecha_inicio      date,                                          -- desde cuándo se puede surtir
  fecha_fin         date,                                          -- fecha límite de entrega
  estado            text not null default 'abierto' check (estado in ('abierto', 'cerrado', 'cancelado')),
  notas             text,
  capturado_por     uuid references auth.users (id),
  capturado_en      timestamptz,
  modificado_en     timestamptz,
  check (fecha_fin is null or fecha_inicio is null or fecha_fin >= fecha_inicio)
);
create trigger captura before insert or update on contratos_mp for each row execute function marcar_captura();
select aplicar_seguridad('contratos_mp', 'planta');
-- Finanzas también puede capturar y editar contratos.
create policy capturar_finanzas on contratos_mp for insert to authenticated with check (puede_capturar('finanzas'));
create policy editar_finanzas on contratos_mp for update to authenticated
  using (puede_capturar('finanzas')) with check (puede_capturar('finanzas'));

alter table llegadas_mp add column contrato_id bigint references contratos_mp (id);
alter table llegadas_mp add column tipo_cambio numeric(10,4) check (tipo_cambio > 0);   -- si el contrato es en USD
create index on llegadas_mp (contrato_id);

-- La llegada debe ser de la misma materia prima que su contrato, y el contrato no puede estar cancelado.
create or replace function trg_validar_contrato_llegada() returns trigger language plpgsql as $$
declare c record;
begin
  if new.contrato_id is null then return new; end if;
  select materia_prima_id, estado into c from contratos_mp where id = new.contrato_id;
  if c.materia_prima_id is distinct from new.materia_prima_id then
    raise exception 'El contrato es de otra materia prima';
  end if;
  if c.estado = 'cancelado' then
    raise exception 'El contrato está cancelado';
  end if;
  return new;
end $$;
create trigger validar_contrato before insert or update on llegadas_mp
  for each row execute function trg_validar_contrato_llegada();

-- Materias primas que deben tener contrato vigente.
alter table materias_primas add column requiere_contrato boolean not null default false;
update materias_primas set requiere_contrato = true where nombre in ('SORGO', 'MAIZ', 'PASTA DE SOYA');

-- ---------- Corte de contratos ----------
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
       pf.nombre as capturado_por
from contratos_mp c
join proveedores pr on pr.id = c.proveedor_id
join materias_primas mp on mp.id = c.materia_prima_id
left join perfiles pf on pf.id = c.capturado_por
left join lateral (
  select sum(l.kg_neto) as kg, count(*) as n, max(l.fecha) as ultima
  from llegadas_mp l where l.contrato_id = c.id
) s on true;

-- ---------- Cobertura de las materias que requieren contrato ----------
create or replace view v_cobertura_mp with (security_invoker = true) as
with consumo as (
  select materia_prima_id, sum(-kg) / 30.0 as kg_dia
  from movimientos_mp
  where tipo = 'consumo' and fecha > current_date - 30
  group by materia_prima_id
), pendiente as (
  select materia_prima_id, sum(kg_pendientes) as kg, count(*) as contratos
  from v_contratos where estado_actual = 'abierto'
  group by materia_prima_id
)
select mp.id, mp.nombre,
       coalesce(s.existencia_kg, 0) as existencia_kg,
       coalesce(p.kg, 0) as kg_contratados_pendientes,
       coalesce(p.contratos, 0) as contratos_abiertos,
       round(coalesce(c.kg_dia, 0), 2) as consumo_kg_dia,
       case when c.kg_dia > 0 then greatest(0, floor(coalesce(s.existencia_kg, 0) / c.kg_dia)) end as dias_existencia,
       case when c.kg_dia > 0 then greatest(0, floor((greatest(coalesce(s.existencia_kg, 0), 0) + coalesce(p.kg, 0)) / c.kg_dia)) end as dias_cobertura
from materias_primas mp
left join saldos_mp s on s.materia_prima_id = mp.id
left join consumo c on c.materia_prima_id = mp.id
left join pendiente p on p.materia_prima_id = mp.id
where mp.requiere_contrato and mp.activa;

-- Historial de llegadas con su contrato (columnas nuevas al final).
create or replace view v_llegadas with (security_invoker = true) as
select l.id, l.fecha, l.kg_bruto, l.kg_tara, l.kg_neto, l.humedad_pct, l.precio_kg, l.total,
       l.factura, l.boleta, l.notas, l.capturado_en,
       l.materia_prima_id, mp.nombre as materia_prima,
       l.proveedor_id, pr.nombre as proveedor,
       l.bodega_id, b.nombre as bodega,
       pf.nombre as capturado_por,
       l.contrato_id, coalesce(c.folio, '#' || c.id) as contrato, l.tipo_cambio
from llegadas_mp l
join materias_primas mp on mp.id = l.materia_prima_id
left join proveedores pr on pr.id = l.proveedor_id
left join bodegas b on b.id = l.bodega_id
left join perfiles pf on pf.id = l.capturado_por
left join contratos_mp c on c.id = l.contrato_id;

alter publication supabase_realtime add table contratos_mp;
