\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-000000000001', 'captura@ramarierp.com');
insert into perfiles values ('00000000-0000-0000-0000-000000000001', 'Capturista planta', 'capturista', true);
insert into perfil_modulos values ('00000000-0000-0000-0000-000000000001', 'planta');
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
insert into proveedores (nombre) values ('LANDUS');
insert into contratos_mp (folio, proveedor_id, materia_prima_id, kg_contratados, precio) select ' prv-101 ', 1, id, 1000, 5 from materias_primas where nombre = 'SORGO';
select folio from contratos_mp;
insert into llegadas_mp (fecha, materia_prima_id, kg_neto, precio_kg, boleta) select current_date, id, 1000, 5, 'b-77' from materias_primas where nombre = 'SORGO';
update llegadas_mp set boleta = 'B-77' where id = 1;   -- la misma llegada: permitido
\set ON_ERROR_STOP 0
insert into contratos_mp (folio, proveedor_id, materia_prima_id, kg_contratados, precio) select 'PRV-101', 1, id, 1000, 5 from materias_primas where nombre = 'MAIZ';
insert into llegadas_mp (fecha, materia_prima_id, kg_neto, precio_kg, boleta) select current_date, id, 1000, 5, 'B-77' from materias_primas where nombre = 'MAIZ';
\set ON_ERROR_STOP 1
insert into contratos_mp (proveedor_id, materia_prima_id, kg_contratados, precio) select 1, id, 1000, 5 from materias_primas where nombre = 'MAIZ';
insert into contratos_mp (folio, proveedor_id, materia_prima_id, kg_contratados, precio) select '', 1, id, 1000, 5 from materias_primas where nombre = 'MAIZ';
select count(*) as contratos_sin_folio from contratos_mp where folio is null;
reset role;
