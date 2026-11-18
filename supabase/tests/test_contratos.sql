-- Prueba 0007: contratos y su corte (correr después de cargar_todo.sh)
\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-000000000001', 'captura@ramarierp.com');
insert into perfiles values ('00000000-0000-0000-0000-000000000001', 'Capturista planta', 'capturista', true);
insert into perfil_modulos values ('00000000-0000-0000-0000-000000000001', 'planta');
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
insert into proveedores (nombre) values ('LANDUS'), ('MULTIMERCADO');
-- Contrato de 500 t de sorgo con Landus, vence en 10 días; contrato USD de maíz
insert into contratos_mp (folio, proveedor_id, materia_prima_id, kg_contratados, precio, fecha_fin)
select 'PRV-101', p.id, m.id, 500000, 5.12, current_date + 10 from proveedores p, materias_primas m where p.nombre='LANDUS' and m.nombre='SORGO';
insert into contratos_mp (folio, proveedor_id, materia_prima_id, kg_contratados, moneda, precio, fecha_fin)
select 'LND-7', p.id, m.id, 300000, 'USD', 0.2786, current_date - 1 from proveedores p, materias_primas m where p.nombre='LANDUS' and m.nombre='MAIZ';
-- Dos llegadas al contrato de sorgo (60 t) y una de maíz a tipo de cambio 17.43
insert into llegadas_mp (fecha, materia_prima_id, proveedor_id, contrato_id, kg_neto, precio_kg)
select current_date - 2, m.id, p.id, 1, 30000, 5.12 from proveedores p, materias_primas m where p.nombre='LANDUS' and m.nombre='SORGO';
insert into llegadas_mp (fecha, materia_prima_id, proveedor_id, contrato_id, kg_neto, precio_kg)
select current_date - 1, m.id, p.id, 1, 30210, 5.12 from proveedores p, materias_primas m where p.nombre='LANDUS' and m.nombre='SORGO';
insert into llegadas_mp (fecha, materia_prima_id, proveedor_id, contrato_id, kg_neto, precio_kg, tipo_cambio)
select current_date, m.id, p.id, 2, 25000, round(0.2786 * 17.43, 4), 17.43 from proveedores p, materias_primas m where p.nombre='LANDUS' and m.nombre='MAIZ';
-- Producción de 10 t de NX Finalizador para tener consumo
select guardar_orden(current_date, (select id from formulas where nombre='NX FINALIZADOR'), 10000);
select folio, materia_prima, kg_contratados, kg_surtidos, kg_pendientes, pct_surtido, llegadas, estado_actual, dias_para_vencer from v_contratos order by id;
select nombre, existencia_kg, kg_contratados_pendientes, contratos_abiertos, consumo_kg_dia, dias_existencia, dias_cobertura from v_cobertura_mp order by nombre;
select fecha, materia_prima, contrato, kg_neto, precio_kg, tipo_cambio from v_llegadas order by id;
\set ON_ERROR_STOP 0
-- Llegada de soya ligada al contrato de sorgo → error
insert into llegadas_mp (fecha, materia_prima_id, contrato_id, kg_neto, precio_kg) select current_date, id, 1, 1000, 6 from materias_primas where nombre='PASTA DE SOYA';
reset role;
