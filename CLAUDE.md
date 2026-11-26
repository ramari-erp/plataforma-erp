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
- Probar la página: `tests/navegador/correr.sh` (Playwright preinstalado; sirve el repo con `page.route` y reemplaza
  `app/api.js` por `tests/navegador/api_falsa.js`). Cada prueba revisa errores y scroll horizontal a 1280 y 390 px.
  Al cambiar una pantalla, actualizar su prueba y la api falsa; todas deben quedar en "bien".
- Ventas está dividido: `ventas.js` (pantalla y pestañas), `ventas_tipos.js` (config. por tipo y utilidades),
  `ventas_formulario.js`, `ventas_historial.js`; cobranza en `cobranza.js`, cuentas en `cuentas.js`.
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
- Llegadas: editables por planta (`modificado_por`); `precio_provisional` + sin factura = `pendientes` en `v_llegadas`;
  `kg_excedente_contrato` (ventana por contrato) y `v_contratos.kg_excedente`.
- Pesada conjunta (`pesadas_conjuntas`, `registrar_pesada_conjunta()`): el total se reparte entre órdenes en proporción
  a `kg_solicitados`. Nota de entrada (`notas_entrada`, `crear_nota_entrada()`): una llegada por producto con `nota_id`;
  pesos de la nota, o ajustados a báscula si `p_ajustar`. `factura_nota()` aplica la factura a toda la nota.
- Ventas (`ventas` + `venta_renglones`, `guardar_venta()`, módulo 'ventas'): renglón = granja, calidad, cantidad, kg, precio.
  Huevo: merma = cajas × `merma_kg_caja` (2). Total (factura y cobranza) = Σ kg netos × precio − descuento.
  Sin flete (0022: `flete_kg` y `flete_caja` quedan en 0; columnas neto/flete de las vistas solo por compatibilidad).
  Destino: `destino_colonia`, `destino_ciudad`, `destino_estado` (+ `destino` armado); `aumento_centavos_kg` = dato de
  referencia, no cambia precio ni total.
  Pesada única (0024): `ventas.kg_bascula` se reparte entre renglones por cajas (último renglón = redondeo), en
  `guardar_venta()`. Facturas: `venta_facturas` (número, razón social, monto); `ventas.factura` = números juntos.
  Calidades en `calidades_venta` (borrego pendiente: texto libre).
  Berries: `presentacion` (sugerencias en `presentaciones_venta` con kg por caja), `merma_kg` por renglón, moneda MXN/USD,
  folio y folio_externo. Generales: `producto_id` → `productos_venta` (catálogo que crece desde la captura).
  `precio_por` = 'kg' (kg netos × (precio + flete)) o 'unidad' (cantidad × precio; kg opcional).
- Cobranza (`pagos_cliente` + `pago_aplicaciones`, `registrar_pago()`): un pago se aplica a una o varias ventas a crédito
  del mismo cliente y moneda; lo no aplicado queda a favor. Saldo de venta = total − anticipo − pagado (`v_ventas`);
  por cliente y moneda en `v_saldos_clientes`. Pantalla Ventas → Cobranza y saldos (cobranza.js).
  Pagos: editar y eliminar desde Pagos recibidos o el estado de cuenta; eliminar lo puede quien captura ventas (0023).
- Cuentas (0025): `cuentas_bancarias` (banco o caja, alta en línea desde Ventas/Cobranza, app/cuentas.js); `cuenta_id` en
  `ventas` (contado/anticipo) y `pagos_cliente`. `v_depositos` = cobros por cuenta: base de la futura sección Bancos.
- Almacenes de planta (`grupos_almacen`): Sorgo (zona roja 4,800 t + 10 t tolvas) y Maíz (zona amarilla 1,350 t + 10 t) separados (0023).
- Materias primas nuevas: `crear_materia_prima()` (capturista de planta) las deja `revisada = false`; el
  administrador las revisa en Planta → Materias primas. Duplicados por `nombre_normalizado()` (sin acentos).
- Fórmulas nuevas: `crear_formula()` (copia de otra o vacía, `revisada = false`). Una fórmula sin ingredientes toma
  los de su primera orden (`base_formula_vacia()` dentro de `guardar_orden()`). Revisión en Planta → Fórmulas.
- Seguridad: RLS en todas las tablas con `aplicar_seguridad(tabla, modulo)`: capturar = permiso del módulo en
  `perfil_modulos`, borrar = administrador. Desde 0026 `perfil_modulos.nivel` = 'ver' | 'capturar'; `puede_ver(m)`
  (admin y director ven todo) y `puede_capturar(m)`. Permisos: avisos, granjas, planta, ventas_<especie>, cobranza
  ('ventas' quedó inactivo). Planta y sus catálogos se leen con `puede_ver('planta')`; ventas por especie (cobranza
  ve todas); pagos con 'cobranza'. Catálogos generales (granjas, clientes, cuentas) los lee todo usuario activo.
  En la página: `sesion.puedeVer/puedeCapturar`; menú, Inicio y pestañas de Ventas se filtran por permiso.
  Al crear una tabla nueva de un módulo, su regla de lectura debe usar `puede_ver(modulo)`.
- Catálogos cerrados (fórmulas, casetas, materias primas); nada de nombres libres en movimientos.

## Probar SQL localmente
PostgreSQL 16 está disponible en el contenedor. `supabase/tests/supabase_stub.sql` simula `auth.users`,
`auth.uid()` y el rol `authenticated`. `supabase/tests/cargar_todo.sh` carga todo en el orden de Supabase (0001, 0002, seed, 0003…).
`supabase/tests/correr_sql.sh` corre todas las pruebas SQL (cada una en base nueva) y compara los errores esperados.
Al agregar una migración: agregarla a `cargar_todo.sh` y a `docs/instalar-base-de-datos.md`, y correr
`scripts/juntar_base.sh` (regenera `supabase/base_completa.sql`, la instalación en un solo archivo para proyectos nuevos).
Croquis y capacidades de la planta: `docs/planta/`.
Casetas y tolvas: `scripts/generar_casetas.py` genera `supabase/datos/0001_casetas_tolvas.sql` desde CAPACIDADES.xlsx
(una hoja por granja; la capacidad de tolvas de la hoja es la de CADA tolva). Los archivos de `supabase/datos/` son repetibles.
El SQL Editor de Supabase puede correr cada instrucción en otra conexión: no usar tablas temporales entre
instrucciones; usar una sola instrucción con CTE (`with datos as (values …)`) por cada paso.

## Plan
Plan de acción del proyecto (fases 0–8, tareas, formatos): documento "Plan de acción — Plataforma ERP
Pecuaria Real Victoria" en el proyecto de claude.ai.
