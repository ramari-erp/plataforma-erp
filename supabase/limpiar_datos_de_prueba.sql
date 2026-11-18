-- =====================================================================
-- Borra TODOS los movimientos de planta (pruebas) para arrancar en limpio.
-- Conserva: usuarios, granjas, materias primas, fórmulas, proveedores, grupos de almacén.
-- Borra: llegadas, órdenes de producción, contratos, inventario de arranque, conteos, ajustes,
--        pedidos y salidas, y el kárdex/saldos que se calculan de ellos.
-- ¡No se puede deshacer! Úsalo solo antes del arranque real.
-- =====================================================================
truncate table
  llegadas_mp, contratos_mp,
  orden_ingredientes, orden_extras, orden_medicacion, ordenes_produccion,
  pedido_detalle, pedidos_alimento, salida_detalle, salidas_alimento,
  inventario_inicial, conteos_mp, ajustes_mp,
  movimientos_mp, saldos_mp
restart identity;

-- Para revisar que quedó vacío:
select (select count(*) from llegadas_mp) as llegadas, (select count(*) from ordenes_produccion) as ordenes,
       (select count(*) from contratos_mp) as contratos, (select count(*) from movimientos_mp) as movimientos;
