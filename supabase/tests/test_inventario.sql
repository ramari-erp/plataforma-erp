-- Prueba 0005: inventario de arranque y conteo físico (correr después de cargar_todo.sh)
\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-000000000001', 'captura@ramarierp.com');
insert into perfiles values ('00000000-0000-0000-0000-000000000001', 'Capturista planta', 'capturista', true);
insert into perfil_modulos values ('00000000-0000-0000-0000-000000000001', 'planta');
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select nombre, precio_referencia from v_existencias_mp where nombre in ($$SORGO$$, $$Toxad Plus$$, $$CÁSCARA DE SOYA$$) order by 1;

-- Arranque el 20-nov: 1,000 t de sorgo a $5.10 y 50 t de soya a $6.34
select guardar_inventario_inicial('2026-11-20', jsonb_build_array(
  jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre='SORGO'), 'kg', 1000000, 'costo_kg', 5.10),jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre='PASTA DE SOYA'), 'kg', 50000, 'costo_kg', 6.34))) as guardados;
-- Llega sorgo a $5.40 → promedio (1000×5.10 + 200×5.40)/1200 = 5.15
insert into llegadas_mp (fecha, materia_prima_id, kg_neto, precio_kg) select '2026-11-21', id, 200000, 5.40 from materias_primas where nombre='SORGO';
select nombre, existencia_kg, costo_promedio from v_existencias_mp where nombre in ('SORGO', 'PASTA DE SOYA');

-- Conteo semanal: hay 1,195 t de sorgo (faltan 5 t) y la soya cuadra
select * from registrar_conteo('2026-11-27', jsonb_build_array(
  jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre='SORGO'), 'kg_fisicos', 1195000),
  jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre='PASTA DE SOYA'), 'kg_fisicos', 50000)));
select nombre, existencia_kg, costo_promedio from v_existencias_mp where nombre in ('SORGO', 'PASTA DE SOYA');
select fecha, materia_prima, kg_sistema, kg_fisicos, diferencia, capturado_por from v_conteos;
select materia_prima_id, kg, motivo from ajustes_mp;
reset role;
