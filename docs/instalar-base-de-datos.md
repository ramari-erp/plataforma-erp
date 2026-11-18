# Cómo instalar la base de datos en Supabase

1. Entra a supabase.com con la cuenta de la empresa y abre el proyecto **ramari-erp**.
2. En el menú de la izquierda abre **SQL Editor** → **New query**.
3. Copia todo el contenido de `supabase/migrations/0001_base.sql`, pégalo y presiona **Run**.
   Debe decir "Success. No rows returned".
4. Repite con `supabase/migrations/0002_planta.sql`.
5. Repite con `supabase/seed/0001_catalogo_planta.sql` (carga 67 materias primas y medicamentos,
   y 29 fórmulas con sus ingredientes, tomadas del archivo de costo de alimento jul–sep 2026).
6. Repite con `supabase/migrations/0003_capacidades_planta.sql` (capacidades de la planta por grupo de
   materias primas: sorgo y maíz, soya, calcios, salvado/cáscara, ortofosfato). Va DESPUÉS del paso 5.
7. Repite con `supabase/migrations/0004_pantallas_planta.sql` (historial de llegadas, alta de usuarios
   desde la plataforma y actualización en vivo).
8. Repite con `supabase/migrations/0005_inventario_fisico.sql` (inventario de arranque, conteo físico
   semanal con ajustes, precios de referencia de septiembre).
9. Repite con `supabase/migrations/0006_ordenes_produccion.sql` (órdenes de producción con fórmula
   ajustable por orden y extras).
10. Repite con `supabase/migrations/0007_contratos_granos.sql` (contratos de materia prima, corte con
    las llegadas y alertas de cobertura de sorgo, maíz y pasta de soya).
11. Repite con `supabase/migrations/0008_orden_granja_destino.sql` (granja destino en las órdenes).
12. Repite con `supabase/migrations/0009_orden_area.sql` (área de cada orden: cerdos, aves, ganado, borregos).
13. Revisa en **Table Editor** que existan las tablas `granjas`, `materias_primas`, `formulas`.

Siempre en ese orden: 0001 → 0002 → seed → 0003 → 0004 → 0005 → 0006 → 0007 → 0008 → 0009.
Si un archivo marca "already exists", ese archivo ya se había ejecutado: pasa al siguiente. Si una ejecución marca error, no sigas con la siguiente: copia el mensaje y compártelo.

## Qué queda cargado
- Granjas: La Red, Durazno, Palenque, San Pablo, Rodadero, Ramari, Paraíso, Princesita, Josefino y La Mesa
  (las dos últimas inactivas mientras se construyen), con sus áreas.
- Materias primas, medicamentos y fórmulas.

## Qué falta capturar (catálogos del plan de acción)
Casetas, tolvas, bodegas y su capacidad, lote/banda actual en cada caseta, proveedores, clientes, camiones,
equivalencias de nombres de fórmulas, y el inventario físico de arranque.

## Antes del arranque real
Si hiciste capturas de prueba, ejecuta `supabase/limpiar_datos_de_prueba.sql`: borra llegadas, órdenes, contratos,
inventario de arranque, conteos y ajustes, y deja los catálogos (granjas, materias primas, fórmulas, proveedores,
usuarios). No se puede deshacer. Si en las pruebas cambiaste alguna fórmula base, revísala.
