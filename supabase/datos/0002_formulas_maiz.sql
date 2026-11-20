-- FÓRMULAS CON MAÍZ v1 (20-nov-2026) — 8 SMC y 9 NX, transcritas de la hoja "FORMULA DE MATERIAS" (sección MAIZ).
-- Cada fórmula suma 1,000 kg/t. Se puede volver a correr: actualiza las fórmulas y sus ingredientes sin duplicar.
-- Las órdenes ya registradas no cambian (cada orden guarda su propia copia de ingredientes).

-- 1) Núcleo que no existía en el catálogo (SMC Reemplazos 2). Queda por revisar.
insert into materias_primas (nombre, categoria, revisada, creada_en)
values ('NÚCLEO REEMPLAZOS 2 SMC', 'nucleo', false, now())
on conflict (nombre) do nothing;

-- 2) Fórmulas
insert into formulas (nombre, especie, etapa, notas, vigente_desde)
select x.nombre, 'cerdos', x.etapa, x.notas, date '2026-11-20' from (values
  ('SMC PREINICIADOR MAÍZ', 'Preiniciador', 'Código SMC P-200 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC FASE 4 MAÍZ', 'Fase 4', 'Código SMC P-120 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC CRECIMIENTO MAÍZ', 'Crecimiento', 'Código SMC P-121 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC DESARROLLO MAÍZ', 'Desarrollo', 'Código SMC P-122 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC FINALIZADOR MAÍZ', 'Finalizador', 'Código SMC P-125 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC GESTACIÓN MAÍZ', 'Gestación', 'Código SMC P-130 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC LACTANCIA MAÍZ', 'Lactancia', 'Código SMC P-133 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC REEMPLAZOS 2 MAÍZ', 'Reemplazos 2', 'Código SMC P-223 A. Fórmula con maíz (20-nov-2026).'),
  ('NX INICIADOR MAÍZ', 'Iniciador', 'Fórmula con maíz (20-nov-2026).'),
  ('NX CRECIMIENTO MAÍZ', 'Crecimiento', 'Fórmula con maíz (20-nov-2026).'),
  ('NX DESARROLLO MAÍZ', 'Desarrollo', 'Fórmula con maíz (20-nov-2026).'),
  ('NX FINALIZADOR MAÍZ', 'Finalizador', 'Fórmula con maíz (20-nov-2026).'),
  ('NX GESTACIÓN MAÍZ', 'Gestación', 'Fórmula con maíz (20-nov-2026).'),
  ('NX LACTANCIA MAÍZ', 'Lactancia', 'Fórmula con maíz (20-nov-2026).'),
  ('NX REEMPLAZOS 1 MAÍZ', 'Reemplazos 1', 'Fórmula con maíz (20-nov-2026).'),
  ('NX REEMPLAZOS 2 MAÍZ', 'Reemplazos 2', 'Fórmula con maíz (20-nov-2026).'),
  ('NX REEMPLAZOS 3 MAÍZ', 'Reemplazos 3', 'Fórmula con maíz (20-nov-2026).')
) as x (nombre, etapa, notas)
on conflict (nombre) do update set especie = excluded.especie, etapa = excluded.etapa, notas = excluded.notas, activa = true;

-- 3) Ingredientes (kg por tonelada): se reemplazan los de estas fórmulas
delete from formula_ingredientes fi using formulas f
where fi.formula_id = f.id and f.nombre in ('SMC PREINICIADOR MAÍZ', 'SMC FASE 4 MAÍZ', 'SMC CRECIMIENTO MAÍZ', 'SMC DESARROLLO MAÍZ', 'SMC FINALIZADOR MAÍZ', 'SMC GESTACIÓN MAÍZ', 'SMC LACTANCIA MAÍZ', 'SMC REEMPLAZOS 2 MAÍZ', 'NX INICIADOR MAÍZ', 'NX CRECIMIENTO MAÍZ', 'NX DESARROLLO MAÍZ', 'NX FINALIZADOR MAÍZ', 'NX GESTACIÓN MAÍZ', 'NX LACTANCIA MAÍZ', 'NX REEMPLAZOS 1 MAÍZ', 'NX REEMPLAZOS 2 MAÍZ', 'NX REEMPLAZOS 3 MAÍZ');

insert into formula_ingredientes (formula_id, materia_prima_id, kg_por_tonelada)
select f.id, m.id, x.kg from (values
  ('SMC PREINICIADOR MAÍZ', 'NÚCLEO PREINICIADOR 2-3', 175),
  ('SMC PREINICIADOR MAÍZ', 'MAIZ', 559),
  ('SMC PREINICIADOR MAÍZ', 'PASTA DE SOYA', 260),
  ('SMC PREINICIADOR MAÍZ', 'LIPOFEED', 6),
  ('SMC FASE 4 MAÍZ', 'NÚCLEO INICIADOR SMC', 40),
  ('SMC FASE 4 MAÍZ', 'MAIZ', 696),
  ('SMC FASE 4 MAÍZ', 'PASTA DE SOYA', 260),
  ('SMC FASE 4 MAÍZ', 'LIPOFEED', 4),
  ('SMC CRECIMIENTO MAÍZ', 'NÚCLEO CRECIMIENTO SMC', 25),
  ('SMC CRECIMIENTO MAÍZ', 'MAIZ', 764),
  ('SMC CRECIMIENTO MAÍZ', 'PASTA DE SOYA', 210),
  ('SMC CRECIMIENTO MAÍZ', 'LIPOFEED', 1),
  ('SMC DESARROLLO MAÍZ', 'NÚCLEO DESARROLLO SMC', 25),
  ('SMC DESARROLLO MAÍZ', 'MAIZ', 795),
  ('SMC DESARROLLO MAÍZ', 'PASTA DE SOYA', 180),
  ('SMC FINALIZADOR MAÍZ', 'NÚCLEO FINALIZADOR SMC', 25),
  ('SMC FINALIZADOR MAÍZ', 'MAIZ', 739),
  ('SMC FINALIZADOR MAÍZ', 'PASTA DE SOYA', 235),
  ('SMC FINALIZADOR MAÍZ', 'LIPOFEED', 1),
  ('SMC GESTACIÓN MAÍZ', 'NÚCLEO SMC GESTACIÓN', 35),
  ('SMC GESTACIÓN MAÍZ', 'MAIZ', 649),
  ('SMC GESTACIÓN MAÍZ', 'PASTA DE SOYA', 105),
  ('SMC GESTACIÓN MAÍZ', 'LIPOFEED', 1),
  ('SMC GESTACIÓN MAÍZ', 'SALVADO', 210),
  ('SMC LACTANCIA MAÍZ', 'NÚCLEO SMC LACTANCIA', 50),
  ('SMC LACTANCIA MAÍZ', 'MAIZ', 633),
  ('SMC LACTANCIA MAÍZ', 'PASTA DE SOYA', 230),
  ('SMC LACTANCIA MAÍZ', 'LIPOFEED', 7),
  ('SMC LACTANCIA MAÍZ', 'SALVADO', 80),
  ('SMC REEMPLAZOS 2 MAÍZ', 'NÚCLEO REEMPLAZOS 2 SMC', 30),
  ('SMC REEMPLAZOS 2 MAÍZ', 'MAIZ', 643),
  ('SMC REEMPLAZOS 2 MAÍZ', 'PASTA DE SOYA', 175),
  ('SMC REEMPLAZOS 2 MAÍZ', 'LIPOFEED', 2),
  ('SMC REEMPLAZOS 2 MAÍZ', 'SALVADO', 150),
  ('NX INICIADOR MAÍZ', 'NÚCLEO INICIADOR REFORZADO NX', 24),
  ('NX INICIADOR MAÍZ', 'MAIZ', 673),
  ('NX INICIADOR MAÍZ', 'PASTA DE SOYA', 285),
  ('NX INICIADOR MAÍZ', 'LIPOFEED', 4),
  ('NX INICIADOR MAÍZ', 'ORTOFOSFATO', 5),
  ('NX INICIADOR MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 9),
  ('NX CRECIMIENTO MAÍZ', 'NÚCLEO CRECIMIENTO NX', 18),
  ('NX CRECIMIENTO MAÍZ', 'MAIZ', 731),
  ('NX CRECIMIENTO MAÍZ', 'PASTA DE SOYA', 235),
  ('NX CRECIMIENTO MAÍZ', 'LIPOFEED', 2),
  ('NX CRECIMIENTO MAÍZ', 'ORTOFOSFATO', 4),
  ('NX CRECIMIENTO MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 10),
  ('NX DESARROLLO MAÍZ', 'NÚCLEO DESARROLLO NX', 19),
  ('NX DESARROLLO MAÍZ', 'MAIZ', 773),
  ('NX DESARROLLO MAÍZ', 'PASTA DE SOYA', 195),
  ('NX DESARROLLO MAÍZ', 'LIPOFEED', 1),
  ('NX DESARROLLO MAÍZ', 'ORTOFOSFATO', 2),
  ('NX DESARROLLO MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 10),
  ('NX FINALIZADOR MAÍZ', 'NÚCLEO FINALIZADOR NX', 19),
  ('NX FINALIZADOR MAÍZ', 'MAIZ', 728),
  ('NX FINALIZADOR MAÍZ', 'PASTA DE SOYA', 240),
  ('NX FINALIZADOR MAÍZ', 'LIPOFEED', 2),
  ('NX FINALIZADOR MAÍZ', 'ORTOFOSFATO', 2),
  ('NX FINALIZADOR MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 9),
  ('NX GESTACIÓN MAÍZ', 'NÚCLEO GESTACIÓN NX', 10),
  ('NX GESTACIÓN MAÍZ', 'MAIZ', 623),
  ('NX GESTACIÓN MAÍZ', 'PASTA DE SOYA', 150),
  ('NX GESTACIÓN MAÍZ', 'SALVADO', 200),
  ('NX GESTACIÓN MAÍZ', 'ORTOFOSFATO', 6),
  ('NX GESTACIÓN MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 11),
  ('NX LACTANCIA MAÍZ', 'NÚCLEO LACTANCIA NX', 22),
  ('NX LACTANCIA MAÍZ', 'MAIZ', 700),
  ('NX LACTANCIA MAÍZ', 'PASTA DE SOYA', 255),
  ('NX LACTANCIA MAÍZ', 'LIPOFEED', 4),
  ('NX LACTANCIA MAÍZ', 'ORTOFOSFATO', 8),
  ('NX LACTANCIA MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 11),
  ('NX REEMPLAZOS 1 MAÍZ', 'NÚCLEO REEMPLAZOS 1 NX', 15),
  ('NX REEMPLAZOS 1 MAÍZ', 'MAIZ', 733),
  ('NX REEMPLAZOS 1 MAÍZ', 'PASTA DE SOYA', 235),
  ('NX REEMPLAZOS 1 MAÍZ', 'LIPOFEED', 2),
  ('NX REEMPLAZOS 1 MAÍZ', 'ORTOFOSFATO', 5),
  ('NX REEMPLAZOS 1 MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 10),
  ('NX REEMPLAZOS 2 MAÍZ', 'NÚCLEO REEMPLAZOS 2 NX', 15),
  ('NX REEMPLAZOS 2 MAÍZ', 'MAIZ', 806),
  ('NX REEMPLAZOS 2 MAÍZ', 'PASTA DE SOYA', 165),
  ('NX REEMPLAZOS 2 MAÍZ', 'ORTOFOSFATO', 3),
  ('NX REEMPLAZOS 2 MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 11),
  ('NX REEMPLAZOS 3 MAÍZ', 'NÚCLEO REEMPLAZOS 3 NX', 15),
  ('NX REEMPLAZOS 3 MAÍZ', 'MAIZ', 786),
  ('NX REEMPLAZOS 3 MAÍZ', 'PASTA DE SOYA', 125),
  ('NX REEMPLAZOS 3 MAÍZ', 'SALVADO', 60),
  ('NX REEMPLAZOS 3 MAÍZ', 'ORTOFOSFATO', 3),
  ('NX REEMPLAZOS 3 MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 11)
) as x (formula, materia, kg)
join formulas f on f.nombre = x.formula
join materias_primas m on m.nombre = x.materia;

-- 4) Códigos SMC como nombres alternos (para buscar la fórmula por su código)
insert into formula_alias (alias, formula_id)
select x.alias, f.id from (values
  ('P-200 A', 'SMC PREINICIADOR MAÍZ'),
  ('P-120 A', 'SMC FASE 4 MAÍZ'),
  ('P-121 A', 'SMC CRECIMIENTO MAÍZ'),
  ('P-122 A', 'SMC DESARROLLO MAÍZ'),
  ('P-125 A', 'SMC FINALIZADOR MAÍZ'),
  ('P-130 A', 'SMC GESTACIÓN MAÍZ'),
  ('P-133 A', 'SMC LACTANCIA MAÍZ'),
  ('P-223 A', 'SMC REEMPLAZOS 2 MAÍZ')
) as x (alias, formula) join formulas f on f.nombre = x.formula
on conflict (alias) do update set formula_id = excluded.formula_id;

-- 5) Revisión: cada fórmula con su número de ingredientes y su total (debe dar 1,000)
select f.nombre, f.etapa, count(fi.materia_prima_id) as ingredientes, sum(fi.kg_por_tonelada) as total_kg_t
from formulas f left join formula_ingredientes fi on fi.formula_id = f.id
where f.nombre in ('SMC PREINICIADOR MAÍZ', 'SMC FASE 4 MAÍZ', 'SMC CRECIMIENTO MAÍZ', 'SMC DESARROLLO MAÍZ', 'SMC FINALIZADOR MAÍZ', 'SMC GESTACIÓN MAÍZ', 'SMC LACTANCIA MAÍZ', 'SMC REEMPLAZOS 2 MAÍZ', 'NX INICIADOR MAÍZ', 'NX CRECIMIENTO MAÍZ', 'NX DESARROLLO MAÍZ', 'NX FINALIZADOR MAÍZ', 'NX GESTACIÓN MAÍZ', 'NX LACTANCIA MAÍZ', 'NX REEMPLAZOS 1 MAÍZ', 'NX REEMPLAZOS 2 MAÍZ', 'NX REEMPLAZOS 3 MAÍZ')
group by f.nombre, f.etapa order by f.nombre;
