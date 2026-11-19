-- Prueba 0014: fórmulas nuevas desde la orden (correr después de cargar_todo.sh)
\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-000000000001', 'captura@ramarierp.com'), ('00000000-0000-0000-0000-000000000004', 'director@ramarierp.com');
insert into perfiles values ('00000000-0000-0000-0000-000000000001', 'Capturista planta', 'capturista', true),
                            ('00000000-0000-0000-0000-000000000004', 'Director', 'director', true);
insert into perfil_modulos values ('00000000-0000-0000-0000-000000000001', 'planta');
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
-- 1) Copiada de NX FINALIZADOR
select * from crear_formula('nx finalizador  verano', 'cerdos', 'Finalizador', (select id from formulas where nombre = 'NX FINALIZADOR'));
-- 2) Vacía: su base sale de la primera orden
select * from crear_formula('Prueba aves', 'aves');
select nombre, especie, revisada, ingredientes, kg_por_tonelada, copiada_de, creada_por from v_formulas where not revisada order by id;
select guardar_orden(current_date, (select id from formulas where nombre = 'PRUEBA AVES'), 2000,
  jsonb_build_array(jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre = 'SORGO'), 'kg_por_tonelada', 700),
                    jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre = 'PASTA DE SOYA'), 'kg_por_tonelada', 300))) as orden;
select nombre, ingredientes, kg_por_tonelada, ordenes from v_formulas where nombre = 'PRUEBA AVES';
select formula, formula_modificada, kg_producidos from v_ordenes;
-- Segunda orden con otra cantidad: la base NO cambia (ya tiene ingredientes) y se marca modificada
select guardar_orden(current_date, (select id from formulas where nombre = 'PRUEBA AVES'), 1000,
  jsonb_build_array(jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre = 'SORGO'), 'kg_por_tonelada', 650),
                    jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre = 'PASTA DE SOYA'), 'kg_por_tonelada', 350))) as orden2;
select materia_prima, kg_por_tonelada from v_formula_ingredientes where formula_id = (select id from formulas where nombre = 'PRUEBA AVES') order by 1;
select formula, formula_modificada from v_ordenes order by id;
\set ON_ERROR_STOP 0
select * from crear_formula('NX FINALIZADOR', 'cerdos');     -- duplicada
select * from crear_formula('Otra', 'peces');                -- área inválida
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';
select * from crear_formula('Director', 'cerdos');           -- sin permiso
reset role;
