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
13. Repite con `supabase/migrations/0010_pesada_real.sql` (kg solicitados y kg reales de la pesada; edición de
    órdenes por capturistas de planta).
14. Repite con `supabase/migrations/0011_casetas_secciones.sql` (sección, unidad de capacidad y notas en casetas).
15. Repite con `supabase/migrations/0012_superficie_granjas.sql` (superficie en hectáreas, para berries).
16. Repite con `supabase/datos/0001_casetas_tolvas.sql` (100 casetas y sus tolvas del archivo de capacidades).
    Este archivo de datos se puede volver a correr: actualiza las casetas y reemplaza sus tolvas.
17. Repite con `supabase/migrations/0013_materias_nuevas.sql` (alta de materias primas desde llegadas, con revisión
    del administrador).
18. Repite con `supabase/migrations/0014_formulas_nuevas.sql` (alta de fórmulas desde la orden de producción, con
    revisión del administrador).
19. Repite con `supabase/datos/0002_formulas_maiz.sql` (17 fórmulas de cerdo con maíz: 8 SMC y 9 NX). Repetible.
20. Repite con `supabase/migrations/0015_llegadas_pendientes.sql` (editar llegadas, precio provisional,
    información pendiente y excedente de contrato).
21. Repite con `supabase/migrations/0016_folios_unicos.sql` (folio de contrato y boleta de báscula no se repiten).
22. Repite con `supabase/migrations/0017_pesadas_y_notas.sql` (pesada conjunta de varias órdenes; nota de
    entrada con varios productos).
23. Repite con `supabase/migrations/0018_ventas.sql` (ventas de huevo, cerdo, ganado y borregos; clientes con RFC;
    razones sociales; calidades).
24. Repite con `supabase/migrations/0019_berries_generales_cobranza.sql` (ventas de berries, ventas generales con
    catálogo de productos, y cobranza: pagos de clientes y saldos).
25. Repite con `supabase/migrations/0020_flete_por_caja.sql` (flete del huevo por caja según destino; las ventas
    ya capturadas con flete por kg pasan a flete por caja con el mismo total).
26. Repite con `supabase/migrations/0021_flete_descuenta.sql` (corrige 0020: el precio base ya incluye el flete; el flete
    se descuenta del total para sacar el neto recibido).
27. Repite con `supabase/migrations/0022_destino_huevo.sql` (huevo sin flete; destino con colonia, ciudad y estado, y
    aumento al destino en centavos por kg como dato de referencia).
28. Repite con `supabase/migrations/0023_sorgo_maiz_pagos.sql` (sorgo y maíz como almacenes separados; quien captura
    ventas puede eliminar un pago registrado por error). Repetible.
29. Repite con `supabase/migrations/0024_pesada_unica_facturas.sql` (huevo con una sola pesada repartida por cajas;
    varias facturas por venta).
30. Repite con `supabase/migrations/0025_cuentas_bancarias.sql` (cuenta de banco o caja donde se depositó cada cobro;
    depósitos por cuenta).
31. Repite con `supabase/migrations/0026_permisos_ver.sql` (permisos de ver y de capturar por módulo y por tipo de venta;
    cada quien ve solo lo autorizado). Repetible.
32. Revisa en **Table Editor** que existan las tablas `granjas`, `materias_primas`, `formulas`.

Siempre en ese orden: 0001 → 0002 → seed → 0003 → 0004 → 0005 → 0006 → 0007 → 0008 → 0009 → 0010 → 0011 → 0012 → datos/0001 → 0013 → 0014 → datos/0002 → 0015 → 0016 → 0017 → 0018 → 0019 → 0020 → 0021 → 0022 → 0023 → 0024 → 0025 → 0026.
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
