-- Prueba 0013: alta de materias primas por capturista y revisión del administrador
\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-000000000001', 'captura@ramarierp.com'), ('00000000-0000-0000-0000-000000000003', 'admin@ramarierp.com'), ('00000000-0000-0000-0000-000000000004', 'consulta@ramarierp.com');
insert into perfiles values ('00000000-0000-0000-0000-000000000001', 'Capturista planta', 'capturista', true),
                            ('00000000-0000-0000-0000-000000000003', 'Admin', 'administrador', true),
                            ('00000000-0000-0000-0000-000000000004', 'Director', 'director', true);
insert into perfil_modulos values ('00000000-0000-0000-0000-000000000001', 'planta');
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select * from crear_materia_prima('  gluten   de maíz ', 'ingrediente', 'saco 40 kg', null);
select nombre, categoria, presentacion, revisada, creada_por from v_materias_primas where nombre like 'GLUTEN%';
\set ON_ERROR_STOP 0
select * from crear_materia_prima('Gluten de Maiz');      -- duplicado (acentos)
select * from crear_materia_prima('pasta de soya');       -- duplicado
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';
select * from crear_materia_prima('DDGS');                -- director sin permiso
\set ON_ERROR_STOP 1
-- La capturista no puede marcarla como revisada (catálogo = administrador)
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
update materias_primas set revisada = true where nombre = 'GLUTEN DE MAÍZ';
select revisada as sigue_por_revisar_false from materias_primas where nombre = 'GLUTEN DE MAÍZ';
-- El administrador la revisa
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
update materias_primas set revisada = true, stock_minimo_kg = 2000 where nombre = 'GLUTEN DE MAÍZ';
select nombre, revisada, stock_minimo_kg from materias_primas where nombre = 'GLUTEN DE MAÍZ';
select * from crear_materia_prima('DDGS', 'ingrediente');  -- creada por admin: ya revisada
select nombre, revisada from materias_primas where nombre = 'DDGS';
reset role;
