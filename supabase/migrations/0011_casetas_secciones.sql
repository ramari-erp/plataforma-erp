-- =====================================================================
-- 0011_casetas_secciones.sql — Casetas con sección, unidad de capacidad y notas
--   Rodadero y San Pablo repiten "Caseta 1" en varias secciones: la caseta se identifica por
--   granja + área + sección + nombre. La capacidad puede ser en cerdos, camas, corrales, salas,
--   cacheteras, gallinas, borregos, vientres…
-- =====================================================================

alter table casetas add column seccion text;
alter table casetas add column unidad_capacidad text not null default 'animales';
alter table casetas add column notas text;
alter table casetas add column orden int not null default 0;

alter table casetas drop constraint casetas_granja_id_nombre_key;
create unique index casetas_unica on casetas (granja_id, area, coalesce(seccion, ''), nombre);

-- Casetas con sus tolvas, para las pantallas.
create or replace view v_casetas with (security_invoker = true) as
select c.id, c.granja_id, g.nombre as granja, g.activa as granja_activa, c.area, c.seccion, c.nombre, c.uso,
       c.capacidad_animales as capacidad, c.unidad_capacidad, c.notas, c.activa, c.orden,
       count(t.id) filter (where t.activa) as tolvas,
       coalesce(sum(t.capacidad_kg) filter (where t.activa), 0) as capacidad_tolvas_kg
from casetas c
join granjas g on g.id = c.granja_id
left join tolvas t on t.caseta_id = c.id
group by c.id, g.nombre, g.activa;
