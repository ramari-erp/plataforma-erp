\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002');
insert into perfiles values ('00000000-0000-0000-0000-000000000001', 'Capturista planta', 'capturista', true),
                            ('00000000-0000-0000-0000-000000000002', 'Director', 'director', true);
insert into perfil_modulos values ('00000000-0000-0000-0000-000000000001', 'planta');
insert into bodegas (nombre, tipo, capacidad_kg) values ('Silo 1', 'silo', 500000);
update materias_primas set bodega_id = 1 where nombre in ('SORGO');
insert into casetas (granja_id, area, nombre, uso) select id, 'cerdos', 'Engorda 2', 'gestación' from granjas where nombre = 'La Red';
insert into lotes (area, tipo, codigo) values ('cerdos', 'banda', 'B-45');
insert into caseta_lotes (caseta_id, lote_id, desde) values (1, 1, '2026-11-01');
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- Capturista
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
insert into llegadas_mp (fecha, materia_prima_id, kg_neto, precio_kg) select '2026-11-02', id, 100000, 5.00 from materias_primas where nombre='SORGO';
insert into llegadas_mp (fecha, materia_prima_id, kg_neto, precio_kg) select '2026-11-04', id, 100000, 5.20 from materias_primas where nombre='SORGO';
insert into llegadas_mp (fecha, materia_prima_id, kg_neto, precio_kg) select '2026-11-02', id, 20000, 6.40 from materias_primas where nombre='PASTA DE SOYA';
insert into ordenes_produccion (fecha, formula_id, kg_producidos) select '2026-11-05', id, 30000 from formulas where nombre='NX FINALIZADOR';
insert into orden_medicacion select 1, id, 1 from materias_primas where nombre='Toxad Plus';
insert into salidas_alimento (folio, fecha, granja_id, kg_neto_bascula) select '14500', '2026-11-05', id, 29950 from granjas where nombre='La Red';
insert into salida_detalle (salida_id, caseta_id, formula_id, kg) select 1, 1, id, 29950 from formulas where nombre='NX FINALIZADOR';
reset role;

select nombre, existencia_kg, costo_promedio, valor_inventario from v_existencias_mp where existencia_kg <> 0 order by nombre;
select * from v_costo_ordenes;
select * from v_salidas;
select * from v_producto_terminado;
select nombre, existencia_kg, ocupacion_pct from v_bodegas;

-- Llegada con fecha atrasada: recalcula todo en orden
insert into llegadas_mp (fecha, materia_prima_id, kg_neto, precio_kg) select '2026-11-01', id, 50000, 4.00 from materias_primas where nombre='SORGO';
select nombre, existencia_kg, costo_promedio from v_existencias_mp where nombre='SORGO';

-- Director no puede capturar planta
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
\set ON_ERROR_STOP 0
insert into llegadas_mp (fecha, materia_prima_id, kg_neto, precio_kg) values ('2026-11-06', 1, 10, 1);
select count(*) as llegadas_visibles_director from llegadas_mp;
reset role;
