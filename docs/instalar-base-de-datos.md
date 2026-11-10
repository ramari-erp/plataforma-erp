# Cómo instalar la base de datos en Supabase

1. Entra a supabase.com con la cuenta de la empresa y abre el proyecto **ramari-erp**.
2. En el menú de la izquierda abre **SQL Editor** → **New query**.
3. Copia todo el contenido de `supabase/migrations/0001_base.sql`, pégalo y presiona **Run**.
   Debe decir "Success. No rows returned".
4. Repite con `supabase/migrations/0002_planta.sql`.
5. Repite con `supabase/seed/0001_catalogo_planta.sql` (carga 67 materias primas y medicamentos,
   y 29 fórmulas con sus ingredientes, tomadas del archivo de costo de alimento jul–sep 2026).
6. Revisa en **Table Editor** que existan las tablas `granjas`, `materias_primas`, `formulas`.

Siempre en ese orden. Si una ejecución marca error, no sigas con la siguiente: copia el mensaje y compártelo.

## Qué queda cargado
- Granjas: La Red, Durazno, Palenque, San Pablo, Rodadero, Ramari, Paraíso, Princesita, Josefino y La Mesa
  (las dos últimas inactivas mientras se construyen), con sus áreas.
- Materias primas, medicamentos y fórmulas.

## Qué falta capturar (catálogos del plan de acción)
Casetas, tolvas, bodegas y su capacidad, lote/banda actual en cada caseta, proveedores, clientes, camiones,
equivalencias de nombres de fórmulas, y el inventario físico de arranque.
