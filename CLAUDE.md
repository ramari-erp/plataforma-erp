# Plataforma ERP — Pecuaria Real Victoria (Ramari)

Plataforma web para que capturistas registren la operación diaria y el director la consulte actualizada.
Empresa pecuaria: planta de alimentos, cerdos (S1 maternidad, S2 destete, S3 engorda, reemplazos, gestación),
aves (postura y crianza), ganado (registro y comercial), borregos, berries.
Todo en español: tablas, columnas, interfaz y mensajes.

## Stack
- Supabase (PostgreSQL + Auth + Storage). Migraciones en `supabase/migrations/` numeradas; se ejecutan en orden
  en el SQL Editor de Supabase. Nunca editar una migración ya aplicada: crear una nueva.
- Vercel para la página web (frontend aún no iniciado).
- Cuenta de la empresa: sistemas@ramarierp.com (GitHub `ramari-erp`).

## Reglas de diseño
- Los inventarios no se capturan, se calculan desde movimientos (llegadas, órdenes de producción, salidas,
  ajustes, mortalidad, ventas, vales).
- Materia prima: kárdex `movimientos_mp` lo escriben solo triggers; costo = promedio ponderado móvil,
  recalculado en orden cronológico por `recalcular_mp()` (fechas atrasadas quedan bien).
- La materia prima se descuenta al registrar la orden de producción (fórmula + medicación de la orden).
  La salida a granja descuenta producto terminado y se carga a granja, caseta y lote/banda
  (lote automático vía `caseta_lotes`).
- Seguridad: RLS en todas las tablas con `aplicar_seguridad(tabla, modulo)`: leer = usuario activo,
  capturar = permiso del módulo en `perfil_modulos`, borrar = administrador.
- Catálogos cerrados (fórmulas, casetas, materias primas); nada de nombres libres en movimientos.

## Probar SQL localmente
PostgreSQL 16 está disponible en el contenedor. `supabase/tests/supabase_stub.sql` simula `auth.users`,
`auth.uid()` y el rol `authenticated`. Cargar stub + migraciones + seed y correr `supabase/tests/*.sql`.

## Plan
Plan de acción del proyecto (fases 0–8, tareas, formatos): documento "Plan de acción — Plataforma ERP
Pecuaria Real Victoria" en el proyecto de claude.ai.
