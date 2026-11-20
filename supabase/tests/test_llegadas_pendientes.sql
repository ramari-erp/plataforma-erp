-- Prueba 0015: excedente de contrato, pendientes y edición
\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-000000000001', 'captura@ramarierp.com'), ('00000000-0000-0000-0000-000000000002', 'otro@ramarierp.com');
insert into perfiles values ('00000000-0000-0000-0000-000000000001', 'Capturista planta', 'capturista', true), ('00000000-0000-0000-0000-000000000002', 'Encargado', 'capturista', true);
insert into perfil_modulos values ('00000000-0000-0000-0000-000000000001', 'planta'), ('00000000-0000-0000-0000-000000000002', 'planta');
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
insert into proveedores (nombre) values ('LANDUS');
-- Contrato de 60 t de soya en USD
insert into contratos_mp (folio, proveedor_id, materia_prima_id, kg_contratados, moneda, precio)
select 'SOY-1', p.id, m.id, 60000, 'USD', 0.36 from proveedores p, materias_primas m where m.nombre = 'PASTA DE SOYA';
-- 3 llegadas: 30 t (completa), 25 t con TC provisional y sin factura, 10 t (5 t de excedente)
insert into llegadas_mp (fecha, materia_prima_id, contrato_id, kg_neto, precio_kg, tipo_cambio, factura)
select '2026-11-18', id, 1, 30000, round(0.36 * 18.10, 4), 18.10, 'F-100' from materias_primas where nombre = 'PASTA DE SOYA';
insert into llegadas_mp (fecha, materia_prima_id, contrato_id, kg_neto, precio_kg, tipo_cambio, precio_provisional)
select '2026-11-19', id, 1, 25000, round(0.36 * 18.00, 4), 18.00, true from materias_primas where nombre = 'PASTA DE SOYA';
insert into llegadas_mp (fecha, materia_prima_id, contrato_id, kg_neto, precio_kg, tipo_cambio, factura)
select '2026-11-20', id, 1, 10000, round(0.36 * 18.05, 4), 18.05, 'F-102' from materias_primas where nombre = 'PASTA DE SOYA';
select id, fecha, kg_neto, kg_excedente_contrato, pendientes, precio_provisional from v_llegadas order by id;
select folio, kg_contratados, kg_surtidos, kg_pendientes, pct_surtido, kg_excedente, estado_actual from v_contratos;
select existencia_kg, costo_promedio from v_existencias_mp where nombre = 'PASTA DE SOYA';
-- Otro capturista corrige la llegada 2 con el TC real (18.42) y la factura
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
update llegadas_mp set tipo_cambio = 18.42, precio_kg = round(0.36 * 18.42, 4), precio_provisional = false, factura = 'F-101' where id = 2;
select id, precio_kg, pendientes, modificado_por from v_llegadas where id = 2;
select existencia_kg, costo_promedio as costo_corregido from v_existencias_mp where nombre = 'PASTA DE SOYA';
reset role;
