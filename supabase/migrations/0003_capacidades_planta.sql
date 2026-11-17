-- =====================================================================
-- 0003_capacidades_planta.sql — Capacidad de almacenamiento de la planta
--
-- En la planta los espacios se comparten (la zona roja del croquis es "sorgo y/o maíz"),
-- así que la capacidad se controla por GRUPO de materias primas, no por bodega:
--   existencia del grupo = suma de las existencias de sus materias primas
--   capacidad del grupo  = capacidad en piso/bodega + capacidad en tolvas de la planta
-- Fuente: tabla de capacidades y croquis de planta (17-nov-2026).
-- =====================================================================

create table grupos_almacen (
  id                    bigint generated always as identity primary key,
  nombre                text not null unique,
  capacidad_planta_kg   numeric(14,2) not null default 0 check (capacidad_planta_kg >= 0),
  capacidad_tolvas_kg   numeric(14,2) not null default 0 check (capacidad_tolvas_kg >= 0),
  orden                 int not null default 0,
  notas                 text
);

-- Cada materia prima pertenece a lo más a un grupo.
alter table materias_primas add column grupo_almacen_id bigint references grupos_almacen (id);

select aplicar_seguridad('grupos_almacen', 'catalogos');

-- Ocupación por grupo, para el resumen de la planta.
create or replace view v_capacidad_planta with (security_invoker = true) as
select g.id, g.nombre, g.orden,
       g.capacidad_planta_kg, g.capacidad_tolvas_kg,
       g.capacidad_planta_kg + g.capacidad_tolvas_kg as capacidad_total_kg,
       coalesce(sum(s.existencia_kg), 0) as existencia_kg,
       case when g.capacidad_planta_kg + g.capacidad_tolvas_kg > 0
            then round(100 * coalesce(sum(s.existencia_kg), 0) / (g.capacidad_planta_kg + g.capacidad_tolvas_kg), 1)
       end as ocupacion_pct,
       g.capacidad_planta_kg + g.capacidad_tolvas_kg - coalesce(sum(s.existencia_kg), 0) as espacio_libre_kg,
       string_agg(mp.nombre, ', ' order by mp.nombre) as materias,
       g.notas
from grupos_almacen g
left join materias_primas mp on mp.grupo_almacen_id = g.id and mp.activa
left join saldos_mp s on s.materia_prima_id = mp.id
group by g.id;

-- ---------- Datos de la tabla de capacidades ----------

insert into materias_primas (nombre, categoria) values ('CÁSCARA DE SOYA', 'ingrediente')
on conflict (nombre) do nothing;

insert into grupos_almacen (nombre, capacidad_planta_kg, capacidad_tolvas_kg, orden, notas) values
  ('Sorgo y maíz',       6150000, 20000, 1, 'Zona roja 4,800 t (sorgo o maíz) + zona amarilla 1,350 t (solo maíz). El sorgo solo cabe en la zona roja.'),
  ('Soya',               1000000, 60000, 2, null),
  ('Calcio molido',        20000, 25000, 3, null),
  ('Calcio entero',        20000, 25000, 4, 'Calcio quebrado / granulado.'),
  ('Salvado o cáscara',    35000, 28000, 5, 'Salvado y/o cáscara de soya.'),
  ('Ortofosfato',          40000,     0, 6, null);

update materias_primas mp set grupo_almacen_id = g.id
from (values
  ('SORGO', 'Sorgo y maíz'), ('MAIZ', 'Sorgo y maíz'),
  ('PASTA DE SOYA', 'Soya'),
  ('CALCIO MOLIDO', 'Calcio molido'),
  ('CALCIO QUEBRADO / GRANULADO', 'Calcio entero'),
  ('SALVADO', 'Salvado o cáscara'), ('CÁSCARA DE SOYA', 'Salvado o cáscara'),
  ('ORTOFOSFATO', 'Ortofosfato')
) as x (materia, grupo)
join grupos_almacen g on g.nombre = x.grupo
where mp.nombre = x.materia;
