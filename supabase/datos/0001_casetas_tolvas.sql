-- Generado por scripts/generar_casetas.py desde CAPACIDADES.xlsx (19-nov-2026). Se puede volver a correr:
-- actualiza las casetas existentes y reemplaza sus tolvas.

-- Bellavista: arándanos, 10 hectáreas.
insert into granjas (nombre, superficie_ha, notas) values ('Bellavista', 10, 'Arándanos')
on conflict (nombre) do update set superficie_ha = excluded.superficie_ha, notas = excluded.notas;

insert into granja_areas (granja_id, area, subarea)
select g.id, x.area::area_productiva, x.subarea from (values
  ('Rodadero', 'borregos', null), ('Palenque', 'cerdos', 'sitio2'), ('Palenque', 'cerdos', 'sitio3'),
  ('Bellavista', 'berries', 'arándano')
) as x (granja, area, subarea) join granjas g on g.nombre = x.granja
on conflict do nothing;

drop table if exists carga_casetas;
create temp table carga_casetas (granja text, area text, seccion text, nombre text, uso text, capacidad numeric,
  unidad text, tolvas int, ton_tolvas numeric, notas text, orden int);
insert into carga_casetas values
  ('Ramari', 'cerdos', null, 'Caseta 1', 'engorda', 900, 'cerdos', 1, 10, null, 0),
  ('Ramari', 'cerdos', null, 'Caseta 2', 'engorda', 850, 'cerdos', 1, 10, null, 1),
  ('Ramari', 'cerdos', null, 'Caseta 4', 'engorda', 500, 'cerdos', 1, 7, null, 2),
  ('Ramari', 'cerdos', null, 'Caseta 5', 'engorda', 500, 'cerdos', 1, 7, null, 3),
  ('Ramari', 'cerdos', null, 'Caseta 6', 'engorda', 950, 'cerdos', 1, 10, null, 4),
  ('Ramari', 'cerdos', null, 'Caseta 7', 'engorda', 1100, 'cerdos', 1, 15, null, 5),
  ('Ramari', 'borregos', null, 'Caseta 3', 'engorda', 200, 'borregos', 0, 0, 'A granel, se manda de planta', 6),
  ('Ramari', 'borregos', null, 'Caseta adicional', 'engorda', 150, 'borregos', 0, 0, 'Solo se usa cuando se llena la caseta 3', 7),
  ('Ramari', 'borregos', null, 'Pie de cría', 'pie de cría', 108, 'borregos', 0, 0, '100 vientres y 8 sementales', 8),
  ('Rodadero', 'cerdos', 'Sección 1', 'Caseta 1', 'engorda', 1100, 'cerdos', 1, 15, null, 9),
  ('Rodadero', 'cerdos', 'Sección 1', 'Caseta 2', 'engorda', 1100, 'cerdos', 1, 15, null, 10),
  ('Rodadero', 'cerdos', 'Sección 1', 'Caseta 3', 'engorda', 1100, 'cerdos', 1, 15, null, 11),
  ('Rodadero', 'cerdos', 'Sección 1', 'Caseta 4', 'engorda', 1100, 'cerdos', 1, 15, null, 12),
  ('Rodadero', 'cerdos', 'Sección 1', 'Caseta 5', 'engorda', 1100, 'cerdos', 1, 15, null, 13),
  ('Rodadero', 'cerdos', 'Sección 1', 'Caseta 6', 'engorda', 1100, 'cerdos', 1, 15, null, 14),
  ('Rodadero', 'cerdos', 'Sección 2', 'Caseta 1', 'engorda', 1100, 'cerdos', 1, 15, null, 15),
  ('Rodadero', 'cerdos', 'Sección 2', 'Caseta 2', 'engorda', 1100, 'cerdos', 1, 15, null, 16),
  ('Rodadero', 'cerdos', 'Sección 2', 'Caseta 3', 'engorda', 1100, 'cerdos', 1, 15, null, 17),
  ('Rodadero', 'cerdos', 'Sección 2', 'Caseta 4', 'engorda', 1100, 'cerdos', 1, 15, null, 18),
  ('Rodadero', 'cerdos', 'Sección 2', 'Caseta 5', 'engorda', 1100, 'cerdos', 1, 15, null, 19),
  ('Rodadero', 'cerdos', 'Sección 2', 'Caseta 6', 'engorda', 1100, 'cerdos', 1, 15, null, 20),
  ('Rodadero', 'borregos', null, 'Pie de cría', 'pie de cría', 110, 'borregos', 0, 0, '100 vientres y 10 sementales. Se envía en costales, usualmente viajes de 3 t', 21),
  ('La Red', 'cerdos', null, 'Gestación 1', 'gestación', 620, 'camas', 0, 0, null, 22),
  ('La Red', 'cerdos', null, 'Gestación 2', 'gestación', 612, 'camas', 0, 0, null, 23),
  ('La Red', 'cerdos', null, 'Gestación 3', 'gestación', 616, 'camas', 0, 0, null, 24),
  ('La Red', 'cerdos', null, 'Gestación 4', 'gestación', 744, 'camas', 0, 0, null, 25),
  ('La Red', 'cerdos', null, 'Gestación 5', 'gestación', 744, 'camas', 0, 0, null, 26),
  ('La Red', 'cerdos', null, 'Gestación Mesita 6', 'gestación', 744, 'camas', 0, 0, null, 27),
  ('La Red', 'cerdos', null, 'Reemplazos Chequeo Salas', 'reemplazos', 37, 'corrales', 0, 0, null, 28),
  ('La Red', 'cerdos', null, 'Reemplazos Destete', 'reemplazos', 10, 'salas', 0, 0, null, 29),
  ('La Red', 'cerdos', null, 'Reemplazos Cuarentena', 'reemplazos', 160, 'cacheteras', 0, 0, null, 30),
  ('La Red', 'cerdos', null, 'Destetes 3', 'destete', 1000, 'cerdos', 1, 10, null, 31),
  ('La Red', 'cerdos', null, 'Destetes 4', 'destete', 1000, 'cerdos', 1, 10, null, 32),
  ('La Red', 'cerdos', null, 'Destetes 5', 'destete', 1000, 'cerdos', 1, 10, null, 33),
  ('La Red', 'cerdos', 'Maternidad', 'Sección 2', 'maternidad', 110, 'camas', 0, 0, null, 34),
  ('La Red', 'cerdos', 'Maternidad', 'Sección 3', 'maternidad', 110, 'camas', 0, 0, null, 35),
  ('La Red', 'cerdos', 'Maternidad', 'Sección 4', 'maternidad', 280, 'camas', 0, 0, null, 36),
  ('La Red', 'cerdos', 'Casetas satélite', 'Engorda 1', 'maternidad', 159, 'camas', 0, 0, null, 37),
  ('La Red', 'cerdos', 'Casetas satélite', 'Engorda 2', 'maternidad', 114, 'camas', 0, 0, null, 38),
  ('La Red', 'cerdos', 'Casetas satélite', 'Engorda 6', 'maternidad', 159, 'camas', 0, 0, null, 39),
  ('La Red', 'cerdos', 'Casetas satélite', 'Caseta 7', 'maternidad', 79, 'camas', 0, 0, null, 40),
  ('La Red', 'cerdos', 'Casetas satélite', 'Caseta 8', 'maternidad', 79, 'camas', 0, 0, null, 41),
  ('La Red', 'cerdos', 'Casetas satélite', 'Caseta 9', 'maternidad', 87, 'camas', 0, 0, null, 42),
  ('La Red', 'cerdos', 'Casetas satélite', 'Sección 5 Capilla', 'maternidad', 160, 'camas', 0, 0, null, 43),
  ('La Red', 'aves', null, 'Caseta 1', 'crianza', 100000, 'aves', 2, 18.22, null, 44),
  ('La Red', 'aves', null, 'Caseta 2', 'crianza', 100000, 'aves', 2, 18.22, null, 45),
  ('La Red', 'borregos', null, 'Pie de cría', 'pie de cría', 370, 'borregos', 0, 0, '350 vientres y 20 sementales', 46),
  ('La Red', 'borregos', null, 'Pariciones', 'parición', 10, 'corrales', 0, 0, 'Los corrales se utilizan conforme se presentan los partos; no tiene una capacidad exacta', 47),
  ('La Red', 'borregos', null, 'Engorda', 'engorda', 246, 'borregos', 1, 5, null, 48),
  ('San Pablo', 'cerdos', 'Sección 1', 'Caseta 1', 'engorda', 1100, 'cerdos', 1, 15, null, 49),
  ('San Pablo', 'cerdos', 'Sección 1', 'Caseta 2', 'engorda', 1100, 'cerdos', 1, 15, null, 50),
  ('San Pablo', 'cerdos', 'Sección 1', 'Caseta 3', 'engorda', 1100, 'cerdos', 1, 15, null, 51),
  ('San Pablo', 'cerdos', 'Sección 1', 'Caseta 4', 'engorda', 1100, 'cerdos', 1, 15, null, 52),
  ('San Pablo', 'cerdos', 'Sección 1', 'Caseta 5', 'engorda', 1100, 'cerdos', 1, 15, null, 53),
  ('San Pablo', 'cerdos', 'Sección 1', 'Caseta 6', 'engorda', 1100, 'cerdos', 1, 15, null, 54),
  ('San Pablo', 'cerdos', 'Sección 2', 'Caseta Doble 1', 'engorda', 2200, 'cerdos', 2, 15, null, 55),
  ('San Pablo', 'cerdos', 'Sección 2', 'Caseta Doble 2', 'engorda', 2200, 'cerdos', 2, 15, null, 56),
  ('San Pablo', 'cerdos', 'Sección 2', 'Caseta Doble 3', 'engorda', 2200, 'cerdos', 2, 15, null, 57),
  ('San Pablo', 'cerdos', 'Sección 3', 'Caseta Doble 1', 'engorda', 2200, 'cerdos', 2, 15, null, 58),
  ('San Pablo', 'cerdos', 'Sección 3', 'Caseta Doble 2', 'engorda', 2200, 'cerdos', 2, 15, null, 59),
  ('San Pablo', 'cerdos', 'Sección 3', 'Caseta Doble 3', 'engorda', 2200, 'cerdos', 2, 15, null, 60),
  ('San Pablo', 'cerdos', 'Sección 3', 'Caseta Doble 4', 'engorda', 2200, 'cerdos', 2, 15, null, 61),
  ('San Pablo', 'cerdos', 'Sección 4', 'Caseta 1', 'engorda', 1100, 'cerdos', 1, 15, null, 62),
  ('San Pablo', 'cerdos', 'Sección 4', 'Caseta 2', 'engorda', 1100, 'cerdos', 1, 15, null, 63),
  ('San Pablo', 'cerdos', 'Sección 4', 'Caseta 3', 'engorda', 1100, 'cerdos', 1, 15, null, 64),
  ('San Pablo', 'cerdos', 'Sección 4', 'Caseta 4', 'engorda', 1100, 'cerdos', 1, 15, null, 65),
  ('San Pablo', 'cerdos', 'Sección 4', 'Caseta 5', 'engorda', 1100, 'cerdos', 1, 15, null, 66),
  ('San Pablo', 'cerdos', 'Sección 4', 'Caseta 6', 'engorda', 1100, 'cerdos', 1, 15, null, 67),
  ('Princesita', 'aves', null, 'Caseta 1', 'postura', 20000, 'gallinas', 1, 10, null, 68),
  ('Princesita', 'aves', null, 'Caseta 2', 'postura', 20000, 'gallinas', 1, 10, null, 69),
  ('Princesita', 'aves', null, 'Caseta 3', 'postura', 20000, 'gallinas', 1, 10, null, 70),
  ('Princesita', 'aves', null, 'Caseta 4', 'postura', 20000, 'gallinas', 1, 10, null, 71),
  ('Princesita', 'aves', null, 'Caseta 5', 'postura', 20000, 'gallinas', 1, 10, null, 72),
  ('Princesita', 'aves', null, 'Caseta 6', 'postura', 20000, 'gallinas', 1, 6, null, 73),
  ('Durazno', 'aves', null, 'Caseta 1', 'postura', 17760, 'gallinas', 1, 10, null, 74),
  ('Durazno', 'aves', null, 'Caseta 2', 'postura', 17760, 'gallinas', 1, 10, null, 75),
  ('Durazno', 'aves', null, 'Caseta 3', 'postura', 17760, 'gallinas', 1, 10, null, 76),
  ('Durazno', 'aves', null, 'Caseta 4', 'postura', 17760, 'gallinas', 1, 10, null, 77),
  ('Durazno', 'aves', null, 'Caseta 5', 'postura', 17760, 'gallinas', 1, 10, null, 78),
  ('Durazno', 'aves', null, 'Caseta 6', 'postura', 26640, 'gallinas', 1, 10, null, 79),
  ('Durazno', 'aves', null, 'Caseta 7', 'postura', 17760, 'gallinas', 1, 10, null, 80),
  ('Durazno', 'aves', null, 'Caseta 8', 'postura', 26640, 'gallinas', 1, 12, null, 81),
  ('Durazno', 'aves', null, 'Caseta 9', 'postura', 33300, 'gallinas', 1, 12, null, 82),
  ('Paraíso', 'aves', null, 'Caseta 1', 'postura', 15000, 'gallinas', 1, 12, null, 83),
  ('Paraíso', 'aves', null, 'Caseta 2', 'postura', 15000, 'gallinas', 1, 12, null, 84),
  ('Paraíso', 'aves', null, 'Caseta 3', 'postura', 15000, 'gallinas', 1, 12, null, 85),
  ('Josefino', 'aves', null, 'Caseta 1', 'postura', 100000, 'gallinas', 2, 18.22, null, 86),
  ('Josefino', 'aves', null, 'Caseta 2', 'postura', 100000, 'gallinas', 2, 18.22, null, 87),
  ('La Mesa', 'aves', null, 'Caseta 1', 'postura', 100000, 'gallinas', 2, 18.22, null, 88),
  ('La Mesa', 'aves', null, 'Caseta 2', 'postura', 100000, 'gallinas', 2, 18.22, null, 89),
  ('Palenque', 'cerdos', 'Lactancia', 'Tolva 1', 'maternidad', null, 'animales', 1, 1.5, 'Capacidad de animales pendiente', 90),
  ('Palenque', 'cerdos', 'Lactancia', 'Tolva 2', 'maternidad', null, 'animales', 1, 1.5, 'Capacidad de animales pendiente', 91),
  ('Palenque', 'cerdos', 'Lactancia', 'Tolva 3', 'maternidad', null, 'animales', 1, 1.5, 'Capacidad de animales pendiente', 92),
  ('Palenque', 'cerdos', 'Gestación', 'Tolva 1', 'gestación', null, 'animales', 1, 3, 'Capacidad de animales pendiente', 93),
  ('Palenque', 'cerdos', 'Gestación', 'Tolva 2', 'gestación', null, 'animales', 1, 9, 'Capacidad de animales pendiente', 94),
  ('Palenque', 'cerdos', 'Gestación', 'Tolva 3', 'gestación', null, 'animales', 1, 9, 'Capacidad de animales pendiente', 95),
  ('Palenque', 'cerdos', 'Reemplazo', 'Tolva 1', 'reemplazos', null, 'animales', 1, 6, 'Capacidad de animales pendiente', 96),
  ('Palenque', 'cerdos', 'Reemplazo', 'Tolva 2', 'reemplazos', null, 'animales', 1, 9, 'Capacidad de animales pendiente', 97),
  ('Palenque', 'cerdos', 'Sitio 2-3', 'Tolva 1', 'destete y engorda', null, 'animales', 1, 4, 'Capacidad de animales pendiente', 98),
  ('Palenque', 'cerdos', 'Lactancia-iniciador', 'Tolva 1', 'maternidad', null, 'animales', 1, 10, 'Capacidad de animales pendiente', 99);

insert into casetas (granja_id, area, seccion, nombre, uso, capacidad_animales, unidad_capacidad, notas, orden)
select g.id, c.area::area_productiva, c.seccion, c.nombre, c.uso, c.capacidad, c.unidad, c.notas, c.orden
from carga_casetas c join granjas g on g.nombre = c.granja
on conflict (granja_id, area, coalesce(seccion, ''), nombre) do update
  set uso = excluded.uso, capacidad_animales = excluded.capacidad_animales,
      unidad_capacidad = excluded.unidad_capacidad, notas = excluded.notas, orden = excluded.orden;

-- Tolvas: se reemplazan las de estas casetas. La capacidad de la hoja es la de cada tolva.
delete from tolvas t using casetas k, granjas g, carga_casetas c
where t.caseta_id = k.id and k.granja_id = g.id and g.nombre = c.granja and k.area::text = c.area
  and coalesce(k.seccion, '') = coalesce(c.seccion, '') and k.nombre = c.nombre;
insert into tolvas (caseta_id, nombre, capacidad_kg)
select k.id, 'Tolva ' || n, round(c.ton_tolvas * 1000, 2)
from carga_casetas c
join granjas g on g.nombre = c.granja
join casetas k on k.granja_id = g.id and k.area::text = c.area and coalesce(k.seccion, '') = coalesce(c.seccion, '') and k.nombre = c.nombre
cross join generate_series(1, c.tolvas) as n
where c.tolvas > 0 and c.ton_tolvas > 0;

select g.nombre as granja, k.area, count(distinct k.id) as casetas, count(t.id) as tolvas,
       round(sum(t.capacidad_kg) / 1000, 1) as toneladas_en_tolvas
from casetas k join granjas g on g.id = k.granja_id left join tolvas t on t.caseta_id = k.id
group by g.nombre, k.area order by g.nombre, k.area;

drop table carga_casetas;
