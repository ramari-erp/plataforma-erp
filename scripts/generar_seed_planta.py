import openpyxl, sys, collections
src, out = sys.argv[1], sys.argv[2]
wb = openpyxl.load_workbook(src, data_only=True, read_only=True)
def rows(name, start):
    return [r for r in wb[name].iter_rows(min_row=start, values_only=True) if r[0]]
mp = [(r[0].strip(), r[3]) for r in rows('Precios_MP', 4) if isinstance(r[1], (int, float))]
med = [(r[0].strip(), r[1]) for r in rows('Precios_Med', 4) if isinstance(r[1], (int, float))]
_agg = collections.OrderedDict()
for r in rows('Formulas', 4):
    if r[1] and isinstance(r[2], (int, float)):
        k = (r[0].strip(), r[1].strip()); _agg[k] = _agg.get(k, 0) + r[2]   # un ingrediente repetido se suma (p. ej. sorgo en borregos)
form = [(f, i, k) for (f, i), k in _agg.items()]
# área que recibió cada fórmula
area = collections.defaultdict(collections.Counter)
for r in wb['Detalle_salidas'].iter_rows(min_row=4, values_only=True):
    if r[0] and r[8]: area[str(r[8]).strip()][str(r[6])] += 1
def cat(n):
    u = n.upper()
    if u in ('SORGO', 'MAIZ'): return 'grano'
    if 'PASTA' in u: return 'pasta'
    if u.startswith('NÚCLEO') or 'VITAMINA' in u: return 'nucleo'
    if u in ('METIONINA','LISINA','TREONINA','VALINA','ISOLEUCINA','TRIPTÓFANO'): return 'aminoacido'
    if u in ('SAL','CALCIO MOLIDO','CALCIO QUEBRADO / GRANULADO','ORTOFOSFATO','CARBONATO'): return 'mineral'
    if 'POWER FEED' in u: return 'alimento_comprado'
    return 'ingrediente'
def esp(f):
    a = area.get(f)
    top = a.most_common(1)[0][0] if a else ''
    for k, v in (('Cerdos','cerdos'),('Gallinas','aves'),('Ganado','ganado'),('Borregos','borregos')):
        if top.startswith(k): return v
    return 'otro'
q = lambda s: "'" + s.replace("'", "''") + "'"
names = {n for n, _ in mp}
L = ["-- Generado desde Costo_Alimento_por_Granja_Jul-Sep_2026.xlsx (hojas Precios_MP, Precios_Med, Formulas).",
     "-- Catálogo inicial: revisar y completar. No carga inventario (eso es el conteo de arranque).", "",
     "insert into materias_primas (nombre, categoria) values"]
vals = [f"  ({q(n)}, {q(cat(n))})" for n, _ in mp]
vals += [f"  ({q(n)}, 'medicamento')" for n, _ in med if n not in names]
L.append(",\n".join(vals) + "\non conflict (nombre) do nothing;\n")
fn = list(dict.fromkeys(f for f, _, _ in form))
L.append("insert into formulas (nombre, especie) values")
L.append(",\n".join(f"  ({q(f)}, {q(esp(f))})" for f in fn) + "\non conflict (nombre) do nothing;\n")
missing = sorted({i for _, i, _ in form} - names - {n for n, _ in med})
L.append("insert into formula_ingredientes (formula_id, materia_prima_id, kg_por_tonelada)")
L.append("select f.id, m.id, x.kg from (values")
L.append(",\n".join(f"  ({q(f)}, {q(i)}, {k})" for f, i, k in form))
L.append(") as x (formula, ingrediente, kg)\njoin formulas f on f.nombre = x.formula\njoin materias_primas m on m.nombre = x.ingrediente\non conflict do nothing;")
open(out, 'w').write("\n".join(L) + "\n")
print(len(mp), 'mp', len(med), 'med', len(fn), 'formulas', len(form), 'renglones; sin catálogo:', missing)
print({f: esp(f) for f in fn})
