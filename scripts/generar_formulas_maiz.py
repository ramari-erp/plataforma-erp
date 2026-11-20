"""Genera supabase/datos/0002_formulas_maiz.sql: fórmulas de cerdo con maíz (SMC y NX).
Transcritas de la foto de la hoja "FORMULA DE MATERIAS", sección MAIZ (20-nov-2026). Cada una suma 1,000 kg/t.
Uso: python3 -I scripts/generar_formulas_maiz.py supabase/datos/0002_formulas_maiz.sql"""
import sys

# Columnas: micro (núcleo), maíz, soya, lipofeed, salvado, ortofosfato, calcio — kg por tonelada
SMC = [  # (nombre, etapa, código SMC, núcleo, valores)
    ('SMC PREINICIADOR MAÍZ', 'Preiniciador', 'P-200 A', 'NÚCLEO PREINICIADOR 2-3', (175, 559, 260, 6, 0, 0, 0)),
    ('SMC FASE 4 MAÍZ',       'Fase 4',       'P-120 A', 'NÚCLEO INICIADOR SMC',    (40, 696, 260, 4, 0, 0, 0)),
    ('SMC CRECIMIENTO MAÍZ',  'Crecimiento',  'P-121 A', 'NÚCLEO CRECIMIENTO SMC',  (25, 764, 210, 1, 0, 0, 0)),
    ('SMC DESARROLLO MAÍZ',   'Desarrollo',   'P-122 A', 'NÚCLEO DESARROLLO SMC',   (25, 795, 180, 0, 0, 0, 0)),
    ('SMC FINALIZADOR MAÍZ',  'Finalizador',  'P-125 A', 'NÚCLEO FINALIZADOR SMC',  (25, 739, 235, 1, 0, 0, 0)),
    ('SMC GESTACIÓN MAÍZ',    'Gestación',    'P-130 A', 'NÚCLEO SMC GESTACIÓN',    (35, 649, 105, 1, 210, 0, 0)),
    ('SMC LACTANCIA MAÍZ',    'Lactancia',    'P-133 A', 'NÚCLEO SMC LACTANCIA',    (50, 633, 230, 7, 80, 0, 0)),
    ('SMC REEMPLAZOS 2 MAÍZ', 'Reemplazos 2', 'P-223 A', 'NÚCLEO REEMPLAZOS 2 SMC', (30, 643, 175, 2, 150, 0, 0)),
]
NX = [
    ('NX INICIADOR MAÍZ',    'Iniciador',    None, 'NÚCLEO INICIADOR REFORZADO NX', (24, 673, 285, 4, 0, 5, 9)),
    ('NX CRECIMIENTO MAÍZ',  'Crecimiento',  None, 'NÚCLEO CRECIMIENTO NX',  (18, 731, 235, 2, 0, 4, 10)),
    ('NX DESARROLLO MAÍZ',   'Desarrollo',   None, 'NÚCLEO DESARROLLO NX',   (19, 773, 195, 1, 0, 2, 10)),
    ('NX FINALIZADOR MAÍZ',  'Finalizador',  None, 'NÚCLEO FINALIZADOR NX',  (19, 728, 240, 2, 0, 2, 9)),
    ('NX GESTACIÓN MAÍZ',    'Gestación',    None, 'NÚCLEO GESTACIÓN NX',    (10, 623, 150, 0, 200, 6, 11)),
    ('NX LACTANCIA MAÍZ',    'Lactancia',    None, 'NÚCLEO LACTANCIA NX',    (22, 700, 255, 4, 0, 8, 11)),
    ('NX REEMPLAZOS 1 MAÍZ', 'Reemplazos 1', None, 'NÚCLEO REEMPLAZOS 1 NX', (15, 733, 235, 2, 0, 5, 10)),
    ('NX REEMPLAZOS 2 MAÍZ', 'Reemplazos 2', None, 'NÚCLEO REEMPLAZOS 2 NX', (15, 806, 165, 0, 0, 3, 11)),
    ('NX REEMPLAZOS 3 MAÍZ', 'Reemplazos 3', None, 'NÚCLEO REEMPLAZOS 3 NX', (15, 786, 125, 0, 60, 3, 11)),
]
OTRAS = ['MAIZ', 'PASTA DE SOYA', 'LIPOFEED', 'SALVADO', 'ORTOFOSFATO', 'CALCIO QUEBRADO / GRANULADO']

def q(v):
    return 'null' if v is None else "'" + str(v).replace("'", "''") + "'"

todas = SMC + NX
for n, *_, v in todas:
    assert sum(v) == 1000, n
nota = lambda c: (f'Código SMC {c}. ' if c else '') + 'Fórmula con maíz (20-nov-2026).'
formulas_vals = ",\n".join(f"  ({q(n)}, {q(e)}, {q(nota(c))})" for n, e, c, _, _ in todas)
ing = []
for n, e, c, nucleo, v in todas:
    ing.append((n, nucleo, v[0]))
    ing += [(n, mp, kg) for mp, kg in zip(OTRAS, v[1:]) if kg]
ing_vals = ",\n".join(f"  ({q(f)}, {q(m)}, {k})" for f, m, k in ing)
alias_vals = ",\n".join(f"  ({q(c)}, {q(n)})" for n, e, c, *_ in SMC)
nombres = ", ".join(q(n) for n, *_ in todas)

sql = f"""-- FÓRMULAS CON MAÍZ v1 (20-nov-2026) — 8 SMC y 9 NX, transcritas de la hoja "FORMULA DE MATERIAS" (sección MAIZ).
-- Cada fórmula suma 1,000 kg/t. Se puede volver a correr: actualiza las fórmulas y sus ingredientes sin duplicar.
-- Las órdenes ya registradas no cambian (cada orden guarda su propia copia de ingredientes).

-- 1) Núcleo que no existía en el catálogo (SMC Reemplazos 2). Queda por revisar.
insert into materias_primas (nombre, categoria, revisada, creada_en)
values ('NÚCLEO REEMPLAZOS 2 SMC', 'nucleo', false, now())
on conflict (nombre) do nothing;

-- 2) Fórmulas
insert into formulas (nombre, especie, etapa, notas, vigente_desde)
select x.nombre, 'cerdos', x.etapa, x.notas, date '2026-11-20' from (values
{formulas_vals}
) as x (nombre, etapa, notas)
on conflict (nombre) do update set especie = excluded.especie, etapa = excluded.etapa, notas = excluded.notas, activa = true;

-- 3) Ingredientes (kg por tonelada): se reemplazan los de estas fórmulas
delete from formula_ingredientes fi using formulas f
where fi.formula_id = f.id and f.nombre in ({nombres});

insert into formula_ingredientes (formula_id, materia_prima_id, kg_por_tonelada)
select f.id, m.id, x.kg from (values
{ing_vals}
) as x (formula, materia, kg)
join formulas f on f.nombre = x.formula
join materias_primas m on m.nombre = x.materia;

-- 4) Códigos SMC como nombres alternos (para buscar la fórmula por su código)
insert into formula_alias (alias, formula_id)
select x.alias, f.id from (values
{alias_vals}
) as x (alias, formula) join formulas f on f.nombre = x.formula
on conflict (alias) do update set formula_id = excluded.formula_id;

-- 5) Revisión: cada fórmula con su número de ingredientes y su total (debe dar 1,000)
select f.nombre, f.etapa, count(fi.materia_prima_id) as ingredientes, sum(fi.kg_por_tonelada) as total_kg_t
from formulas f left join formula_ingredientes fi on fi.formula_id = f.id
where f.nombre in ({nombres})
group by f.nombre, f.etapa order by f.nombre;
"""
open(sys.argv[1], 'w').write(sql)
print(len(todas), 'fórmulas,', len(ing), 'renglones de ingredientes')
