-- Prueba 0017: pesada conjunta y nota de entrada con varios productos
\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-000000000001', 'captura@ramarierp.com');
insert into perfiles values ('00000000-0000-0000-0000-000000000001', 'Capturista planta', 'capturista', true);
insert into perfil_modulos values ('00000000-0000-0000-0000-000000000001', 'planta');
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select guardar_inventario_inicial('2026-11-20', (select jsonb_agg(jsonb_build_object('materia_prima_id', id, 'kg', 100000, 'costo_kg', coalesce(precio_referencia, 1))) from materias_primas));
-- 5 t de desarrollo + 10 t de gestación; la báscula da 16 t
select guardar_orden('2026-11-23', (select id from formulas where nombre = 'NX DESARROLLO'), 5000) as o1;
select guardar_orden('2026-11-23', (select id from formulas where nombre like 'NX GESTACI_N'), 10000) as o2;
select registrar_pesada_conjunta(array[1, 2]::bigint[], 16000) as pesada;
select id, formula, kg_solicitados, kg_reales, kg_producidos, pesada_conjunta_id, pesada_kg_total, pesada_ordenes, pesada_kg_solicitados from v_ordenes order by id;
-- Corrección: la báscula en realidad dio 15,700
select registrar_pesada_conjunta(array[1, 2]::bigint[], 15700, 1);
select id, kg_reales from v_ordenes order by id;
-- Pesada individual a la orden 2: sale de la conjunta
select registrar_pesada(2, 10100);
select id, kg_reales, pesada_conjunta_id from v_ordenes order by id;
\set ON_ERROR_STOP 0
select registrar_pesada_conjunta(array[1]::bigint[], 5000);
\set ON_ERROR_STOP 1

-- Nota con 3 productos encostalados (pesos de la nota), báscula 1,010 kg solo para comparar
insert into proveedores (nombre) values ('ECOZOO');
select crear_nota_entrada('2026-11-23', (select id from proveedores where nombre = 'ECOZOO'), 'n-501', null,
  jsonb_build_array(
    jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre = 'Toxad Plus'), 'kg', 500, 'precio_kg', 20),
    jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre = 'SAL'), 'kg', 400, 'precio_kg', 0.44),
    jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre = 'LIPOFEED'), 'kg', 100, 'precio_kg', 60)),
  1010) as nota1;
-- Otra nota ajustada a la báscula (1,050 kg contra 1,000 de la nota)
select crear_nota_entrada('2026-11-23', (select id from proveedores where nombre = 'ECOZOO'), 'N-502', 'F-9',
  jsonb_build_array(
    jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre = 'SAL'), 'kg', 600, 'precio_kg', 0.44),
    jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre = 'LIPOFEED'), 'kg', 400, 'precio_kg', 60)),
  1050, true) as nota2;
select id, materia_prima, kg_neto, factura, nota_id, nota_folio, nota_kg_bascula, nota_productos, pendientes, notas from v_llegadas order by id;
select factura_nota(1, 'F-8');
select id, factura, pendientes from v_llegadas where nota_id = 1;
\set ON_ERROR_STOP 0
select crear_nota_entrada('2026-11-23', null, 'N 501', null, '[{"materia_prima_id": 1, "kg": 10, "precio_kg": 1}]');
reset role;
