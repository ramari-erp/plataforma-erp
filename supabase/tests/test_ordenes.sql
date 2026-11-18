-- Prueba 0006: órdenes con fórmula modificada y extras (correr después de cargar_todo.sh)
\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-000000000001', 'captura@ramarierp.com'), ('00000000-0000-0000-0000-000000000003', 'admin@ramarierp.com');
insert into perfiles values ('00000000-0000-0000-0000-000000000001', 'Capturista planta', 'capturista', true),
                            ('00000000-0000-0000-0000-000000000003', 'Admin', 'administrador', true);
insert into perfil_modulos values ('00000000-0000-0000-0000-000000000001', 'planta');
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
create temp table ids as select
  (select id from formulas where nombre = 'NX FINALIZADOR') as f,
  (select id from materias_primas where nombre = 'SORGO') as sorgo,
  (select id from materias_primas where nombre = 'PASTA DE SOYA') as soya,
  (select id from materias_primas where nombre = 'Toxad Plus') as toxad,
  (select id from materias_primas where nombre = 'Tylosin 22%') as tylo;
grant select on ids to authenticated;

set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select guardar_inventario_inicial('2026-11-20', (select jsonb_agg(jsonb_build_object('materia_prima_id', id, 'kg', 100000, 'costo_kg', coalesce(precio_referencia, 1))) from materias_primas));

-- Orden 1: 30 t de NX Finalizador, sorgo de 745 → 760 kg/t y soya de su valor → −15; extras: Toxad 1 kg/t y Tylosin 5 kg totales
select guardar_orden('2026-11-21', (select f from ids), 30000,
  (select jsonb_agg(jsonb_build_object('materia_prima_id', fi.materia_prima_id, 'kg_por_tonelada',
      case when fi.materia_prima_id = (select sorgo from ids) then 760
           when fi.materia_prima_id = (select soya from ids) then fi.kg_por_tonelada - 15 else fi.kg_por_tonelada end))
   from formula_ingredientes fi where fi.formula_id = (select f from ids)),
  jsonb_build_array(jsonb_build_object('materia_prima_id', (select toxad from ids), 'cantidad', 1, 'unidad', 'kg_por_tonelada'),
                    jsonb_build_object('materia_prima_id', (select tylo from ids), 'cantidad', 5, 'unidad', 'kg_total', 'nota', 'Brote respiratorio caseta 3')),
  'Prueba') as orden1;
-- Orden 2: misma fórmula sin cambios (lista vacía = fórmula tal cual)
select guardar_orden('2026-11-21', (select f from ids), 10000) as orden2;

select id, formula, kg_producidos, formula_modificada, extras, costo_mp, costo_kg, capturado_por from v_ordenes order by id;
select orden_id, materia_prima, kg, es_extra from v_orden_consumos
 where materia_prima in ('SORGO', 'Toxad Plus', 'Tylosin 22%') order by orden_id, materia_prima;

-- Capturista no puede cambiar la fórmula base
\set ON_ERROR_STOP 0
select guardar_orden('2026-11-22', (select f from ids), 1000, '[{"materia_prima_id": 1, "kg_por_tonelada": 1000}]', '[]', null, true);
\set ON_ERROR_STOP 1

-- Admin cambia la fórmula base con una orden: sorgo 770; la orden 1 conserva sus 760
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
select guardar_orden('2026-11-22', (select f from ids), 1000,
  (select jsonb_agg(jsonb_build_object('materia_prima_id', fi.materia_prima_id, 'kg_por_tonelada',
      case when fi.materia_prima_id = (select sorgo from ids) then 770 else fi.kg_por_tonelada end))
   from formula_ingredientes fi where fi.formula_id = (select f from ids)), '[]', null, true) as orden3;
select kg_por_tonelada as sorgo_formula_base from formula_ingredientes where formula_id = (select f from ids) and materia_prima_id = (select sorgo from ids);
select perform_resync from (select sincronizar_movimientos('orden', 1) as perform_resync) x;
select sincronizar_movimientos('orden', 2);
select orden_id, kg as sorgo_kg from v_orden_consumos where materia_prima = 'SORGO' order by orden_id;  -- 1: 22,800 · 2: 7,450 (no cambian) · 4: 770
select id, formula_modificada from v_ordenes order by id;

-- Borrar una orden devuelve la materia prima
select existencia_kg as sorgo_antes from v_existencias_mp where nombre = 'SORGO';
delete from ordenes_produccion where id = 2;
select existencia_kg as sorgo_despues from v_existencias_mp where nombre = 'SORGO';
reset role;
