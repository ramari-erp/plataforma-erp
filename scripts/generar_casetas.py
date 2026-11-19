"""Genera supabase/datos/0001_casetas_tolvas.sql desde CAPACIDADES.xlsx (una hoja por granja).
Uso: python3 -I scripts/generar_casetas.py CAPACIDADES.xlsx supabase/datos/0001_casetas_tolvas.sql
La capacidad de tolvas de la hoja es la de CADA tolva (confirmado 19-nov-2026)."""
import sys, openpyxl

wb = openpyxl.load_workbook(sys.argv[1], data_only=True)
casetas = []   # (granja, area, seccion, nombre, uso, capacidad, unidad, n_tolvas, ton_tolvas, notas, orden)

def num(v):
    return v if isinstance(v, (int, float)) else None

def agregar(granja, area, seccion, nombre, uso, cap, unidad, nt, tt, notas=None):
    casetas.append((granja, area, seccion, nombre, uso, cap, unidad, nt or 0, tt or 0, notas, len(casetas)))

def bloque(ws, granja, area, col, uso_por_defecto, filas, seccion_inicial=None, usos=None):
    """col = índice (0) de la columna del nombre; siguen capacidad, unidad, tolvas, capacidad tolva."""
    seccion, uso = seccion_inicial, uso_por_defecto
    for r in ws.iter_rows(min_row=filas[0], max_row=filas[1], values_only=True):
        nombre = r[col]
        if not isinstance(nombre, str) or not nombre.strip():
            continue
        nombre = nombre.strip()
        if nombre.upper().replace('Í', 'I') == granja.upper().replace('Í', 'I'):   # fila de totales
            continue
        cap, unidad, nt, tt = num(r[col + 1]), r[col + 2], num(r[col + 3]), num(r[col + 4])
        if nombre.upper() in ('CERDOS', 'CERDO', 'AVES', 'PROXIMAMENTE', 'ENGORDA', 'PIE DE CRIA'):   # títulos de la hoja
            continue
        if cap is None and nt is None:            # encabezado de sección
            if usos and nombre.upper() in usos:
                uso = usos[nombre.upper()]; seccion = None
            else:
                seccion = nombre.title().replace('Seccion', 'Sección')
            continue
        agregar(granja, area, seccion, nombre.title(), uso, cap, (unidad or 'animales').lower(), nt, tt)

# RAMARI: cerdos (B..G) y borregos (I..N)
ws = wb['RAMARI']
bloque(ws, 'Ramari', 'cerdos', 1, 'engorda', (3, ws.max_row))
agregar('Ramari', 'borregos', None, 'Caseta 3', 'engorda', 200, 'borregos', 0, 0, 'A granel, se manda de planta')
agregar('Ramari', 'borregos', None, 'Caseta adicional', 'engorda', 150, 'borregos', 0, 0, 'Solo se usa cuando se llena la caseta 3')
agregar('Ramari', 'borregos', None, 'Pie de cría', 'pie de cría', 108, 'borregos', 0, 0, '100 vientres y 8 sementales')

# RODADERO: cerdos con secciones; borregos pie de cría
ws = wb['RODADERO']
bloque(ws, 'Rodadero', 'cerdos', 1, 'engorda', (3, ws.max_row), seccion_inicial='Sección 1')
agregar('Rodadero', 'borregos', None, 'Pie de cría', 'pie de cría', 110, 'borregos', 0, 0,
        '100 vientres y 10 sementales. Se envía en costales, usualmente viajes de 3 t')

# LA RED: cerdos por etapa, aves crianza, borregos
ws = wb['LA RED']
seccion, uso = None, None
for r in ws.iter_rows(min_row=3, max_row=ws.max_row, values_only=True):
    nombre = r[1]
    if not isinstance(nombre, str): continue
    n = nombre.strip().upper()
    if n == 'MATERNIDAD': uso, seccion = 'maternidad', 'Maternidad'; continue
    if n == 'CASETAS SATELITE': uso, seccion = 'maternidad', 'Casetas satélite'; continue
    if seccion is None:
        uso = 'gestación' if n.startswith('GESTACI') else 'reemplazos' if n.startswith('REEMPLAZO') else 'destete' if n.startswith('DESTETE') else uso
    titulo = 'Reemplazos Chequeo Salas' if n == 'REEMPLAZOS CHEQUEO SAL' else nombre.strip().title()
    agregar('La Red', 'cerdos', seccion if seccion != 'Maternidad' else 'Maternidad', titulo, uso,
            num(r[2]), (r[3] or 'animales').lower(), num(r[4]), num(r[5]))
for nombre in ('CASETA 1', 'CASETA 2'):
    r = next(x for x in ws.iter_rows(min_row=3, max_row=5, values_only=True) if x[8] == nombre)
    agregar('La Red', 'aves', None, nombre.title(), 'crianza', num(r[9]), 'aves', num(r[11]), num(r[12]))
agregar('La Red', 'borregos', None, 'Pie de cría', 'pie de cría', 370, 'borregos', 0, 0, '350 vientres y 20 sementales')
agregar('La Red', 'borregos', None, 'Pariciones', 'parición', 10, 'corrales', 0, 0,
        'Los corrales se utilizan conforme se presentan los partos; no tiene una capacidad exacta')
agregar('La Red', 'borregos', None, 'Engorda', 'engorda', 246, 'borregos', 1, 5)

# SAN PABLO: secciones 1-4
bloque(wb['SAN PABLO'], 'San Pablo', 'cerdos', 1, 'engorda', (3, wb['SAN PABLO'].max_row), seccion_inicial='Sección 1')

# AVES de postura
for hoja, granja, col in (('PRINCESITA', 'Princesita', 2), ('DURAZNO', 'Durazno', 1), ('PARAISO', 'Paraíso', 1),
                          ('JOSEFINO', 'Josefino', 2), ('LA MESA', 'La Mesa', 2)):
    bloque(wb[hoja], granja, 'aves', col, 'postura', (1, wb[hoja].max_row))

# PALENQUE: solo tolvas por sección (sin capacidad de animales todavía)
ws = wb['PALENQUE']
seccion, i = None, 0
nombres = {'LACTANCIA': ('Lactancia', 'maternidad'), 'GESTACION': ('Gestación', 'gestación'),
           'REEMPLAZO': ('Reemplazo', 'reemplazos'), 'SITIO 2-3': ('Sitio 2-3', 'destete y engorda'),
           'LACTANCIA-INICIADOR': ('Lactancia-iniciador', 'maternidad')}
for r in ws.iter_rows(min_row=3, max_row=ws.max_row, values_only=True):
    if isinstance(r[2], str):
        seccion, uso = nombres[r[2].strip().upper()]; i = 0; continue
    if num(r[5]) is not None:
        i += 1
        agregar('Palenque', 'cerdos', seccion, f'Tolva {i}', uso, None, 'animales', num(r[5]), num(r[6]),
                'Capacidad de animales pendiente')

def q(v):
    if v is None: return 'null'
    if isinstance(v, (int, float)): return repr(v)
    return "'" + str(v).replace("'", "''") + "'"

datos = ",\n".join("    (" + ", ".join(q(v) for v in c) + ")" for c in casetas)
L = ["-- CARGA DE CASETAS Y TOLVAS v3 (19-nov-2026) — generado por scripts/generar_casetas.py desde CAPACIDADES.xlsx.",
     "-- Se puede volver a correr: actualiza casetas y tolvas sin duplicar. No usa tablas auxiliares.",
     "",
     "-- 1) Bellavista: arándanos, 10 hectáreas.",
     "insert into granjas (nombre, superficie_ha, notas) values ('Bellavista', 10, 'Arándanos')",
     "on conflict (nombre) do update set superficie_ha = excluded.superficie_ha, notas = excluded.notas;",
     "",
     "-- 2) Áreas que faltaban.",
     "insert into granja_areas (granja_id, area, subarea)",
     "select g.id, x.area::area_productiva, x.subarea from (values",
     "  ('Rodadero', 'borregos', null), ('Palenque', 'cerdos', 'sitio2'), ('Palenque', 'cerdos', 'sitio3'),",
     "  ('Bellavista', 'berries', 'arándano')",
     ") as x (granja, area, subarea) join granjas g on g.nombre = x.granja",
     "on conflict do nothing;",
     "",
     "-- 3) Casetas y sus tolvas, en una sola instrucción. La capacidad de tolva es la de CADA tolva.",
     "with datos (granja, area, seccion, nombre, uso, capacidad, unidad, tolvas, ton_tolvas, notas, orden) as (values",
     datos,
     "),",
     "guardadas as (",
     "  insert into casetas (granja_id, area, seccion, nombre, uso, capacidad_animales, unidad_capacidad, notas, orden)",
     "  select g.id, d.area::area_productiva, d.seccion, d.nombre, d.uso, d.capacidad, d.unidad, d.notas, d.orden",
     "  from datos d join granjas g on g.nombre = d.granja",
     "  on conflict (granja_id, area, coalesce(seccion, ''), nombre) do update",
     "    set uso = excluded.uso, capacidad_animales = excluded.capacidad_animales,",
     "        unidad_capacidad = excluded.unidad_capacidad, notas = excluded.notas, orden = excluded.orden",
     "  returning id, orden",
     ")",
     "insert into tolvas (caseta_id, nombre, capacidad_kg, activa)",
     "select k.id, 'Tolva ' || n, round(d.ton_tolvas * 1000, 2), true",
     "from guardadas k",
     "join datos d on d.orden = k.orden",
     "cross join generate_series(1, d.tolvas) as n",
     "where d.tolvas > 0 and d.ton_tolvas > 0",
     "on conflict (caseta_id, nombre) do update set capacidad_kg = excluded.capacidad_kg, activa = true;",
     "",
     "-- 4) Resultado: casetas y tolvas por granja",
     "select g.nombre as granja, k.area, count(distinct k.id) as casetas, count(t.id) as tolvas,",
     "       round(sum(t.capacidad_kg) / 1000, 1) as toneladas_en_tolvas",
     "from casetas k join granjas g on g.id = k.granja_id left join tolvas t on t.caseta_id = k.id and t.activa",
     "group by g.nombre, k.area order by g.nombre, k.area;"]
open(sys.argv[2], 'w').write("\n".join(L) + "\n")
print(len(casetas), 'casetas')
