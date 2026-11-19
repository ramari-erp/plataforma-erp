# Plataforma ERP — Pecuaria Real Victoria (Ramari)

Plataforma web para que capturistas registren la operación diaria y el director la consulte actualizada.
Empresa pecuaria: planta de alimentos, cerdos (S1 maternidad, S2 destete, S3 engorda, reemplazos, gestación),
aves (postura y crianza), ganado (registro y comercial), borregos, berries.
Todo en español: tablas, columnas, interfaz y mensajes.

## Stack
- Supabase (PostgreSQL + Auth + Storage). Migraciones en `supabase/migrations/` numeradas; se ejecutan en orden
  en el SQL Editor de Supabase. Nunca editar una migración ya aplicada: crear una nueva.
- Vercel para la página web. Sin compilación ni paquetes npm (la cuenta no permite instalar paquetes):
  `index.html` + módulos ES en `app/`; supabase-js se carga desde jsDelivr con versión fija en `app/api.js`.
  `.vercelignore` deja fuera supabase/, docs/ y scripts/. Las pantallas solo hablan con la base vía `app/api.js`.
- Probar la página: Playwright (preinstalado) sirviendo el repo con `page.route` y reemplazando `app/api.js`
  por una versión falsa con datos de ejemplo.
- Cuenta de la empresa: sistemas@ramarierp.com (GitHub `ramari-erp`).

## Reglas de diseño
- Los inventarios no se capturan, se calculan desde movimientos (llegadas, órdenes de producción, salidas,
  ajustes, mortalidad, ventas, vales).
- Materia prima: kárdex `movimientos_mp` lo escriben solo triggers; costo = promedio ponderado móvil,
  recalculado en orden cronológico por `recalcular_mp()` (fechas atrasadas quedan bien).
- La materia prima se descuenta al registrar la orden de producción. Cada orden guarda su copia de ingredientes
  (`orden_ingredientes`, modificable) + extras (`orden_extras`, kg/t o kg totales); se guarda con `guardar_orden()`.
  `kg_solicitados` / `kg_reales` (pesada del total); `kg_producidos` = real si existe, si no solicitado (trigger).
  Ingredientes se descuentan proporcional a `kg_producidos`. `registrar_pesada()` captura solo la pesada.
  La salida a granja descuenta producto terminado y se carga a granja, caseta y lote/banda
  (lote automático vía `caseta_lotes`).
- Contratos de materia prima (`contratos_mp`): las llegadas se ligan con `contrato_id`; surtido/pendiente en
  `v_contratos`; alertas por `materias_primas.requiere_contrato` en `v_cobertura_mp` (consumo últimos 30 días).
- Materias primas nuevas: `crear_materia_prima()` (capturista de planta) las deja `revisada = false`; el
  administrador las revisa en Planta → Materias primas. Duplicados por `nombre_normalizado()` (sin acentos).
- Fórmulas nuevas: `crear_formula()` (copia de otra o vacía, `revisada = false`). Una fórmula sin ingredientes toma
  los de su primera orden (`base_formula_vacia()` dentro de `guardar_orden()`). Revisión en Planta → Fórmulas.
- Seguridad: RLS en todas las tablas con `aplicar_seguridad(tabla, modulo)`: leer = usuario activo,
  capturar = permiso del módulo en `perfil_modulos`, borrar = administrador.
- Catálogos cerrados (fórmulas, casetas, materias primas); nada de nombres libres en movimientos.

## Probar SQL localmente
PostgreSQL 16 está disponible en el contenedor. `supabase/tests/supabase_stub.sql` simula `auth.users`,
`auth.uid()` y el rol `authenticated`. `supabase/tests/cargar_todo.sh` carga todo en el orden de Supabase (0001, 0002, seed, 0003…); luego correr `supabase/tests/test_planta.sql`.
Al agregar una migración, agregarla también a `cargar_todo.sh` y a `docs/instalar-base-de-datos.md`.
Croquis y capacidades de la planta: `docs/planta/`.
Casetas y tolvas: `scripts/generar_casetas.py` genera `supabase/datos/0001_casetas_tolvas.sql` desde CAPACIDADES.xlsx
(una hoja por granja; la capacidad de tolvas de la hoja es la de CADA tolva). Los archivos de `supabase/datos/` son repetibles.
El SQL Editor de Supabase puede correr cada instrucción en otra conexión: no usar tablas temporales entre
instrucciones; usar una sola instrucción con CTE (`with datos as (values …)`) por cada paso.

## Plan
Plan de acción del proyecto (fases 0–8, tareas, formatos): documento "Plan de acción — Plataforma ERP
Pecuaria Real Victoria" en el proyecto de claude.ai.
