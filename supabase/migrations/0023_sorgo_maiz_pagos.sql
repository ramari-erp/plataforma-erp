-- =====================================================================
-- 0023_sorgo_maiz_pagos.sql — Sorgo y maíz como almacenes separados; corrección de pagos de clientes
--
--   Sorgo: zona roja 4,800 t + 10 t de tolvas. Maíz: zona amarilla 1,350 t + 10 t de tolvas.
--   Pagos: quien captura ventas puede eliminar un pago registrado por error (antes solo el administrador).
--   Repetible: se puede volver a correr.
-- =====================================================================

update grupos_almacen set nombre = 'Sorgo', capacidad_planta_kg = 4800000, capacidad_tolvas_kg = 10000,
       notas = 'Zona roja 4,800 t + 10 t en tolvas de la planta.'
where nombre = 'Sorgo y maíz';

update grupos_almacen set orden = orden + 1 where orden >= 2 and nombre <> 'Maíz'
  and not exists (select 1 from grupos_almacen where nombre = 'Maíz');

insert into grupos_almacen (nombre, capacidad_planta_kg, capacidad_tolvas_kg, orden, notas)
values ('Maíz', 1350000, 10000, 2, 'Zona amarilla 1,350 t + 10 t en tolvas de la planta.')
on conflict (nombre) do nothing;

-- Las materias primas de maíz que estaban en el grupo compartido pasan al grupo Maíz.
update materias_primas mp set grupo_almacen_id = (select id from grupos_almacen where nombre = 'Maíz')
where mp.grupo_almacen_id = (select id from grupos_almacen where nombre = 'Sorgo')
  and nombre_normalizado(mp.nombre) like '%MAIZ%';

drop policy if exists borrar_ventas on pagos_cliente;
create policy borrar_ventas on pagos_cliente for delete to authenticated using (puede_capturar('ventas'));
