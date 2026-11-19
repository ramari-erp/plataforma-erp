-- Prueba 0010: solicitado vs pesada real, edición por capturista (correr después de cargar_todo.sh)
\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-000000000001', 'captura@ramarierp.com'), ('00000000-0000-0000-0000-000000000002', 'otro@ramarierp.com');
insert into perfiles values ('00000000-0000-0000-0000-000000000001', 'Capturista planta', 'capturista', true),
                            ('00000000-0000-0000-0000-000000000002', 'Encargado planta', 'capturista', true);
insert into perfil_modulos values ('00000000-0000-0000-0000-000000000001', 'planta'), ('00000000-0000-0000-0000-000000000002', 'planta');
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select guardar_inventario_inicial('2026-11-20', (select jsonb_agg(jsonb_build_object('materia_prima_id', id, 'kg', 100000, 'costo_kg', coalesce(precio_referencia, 1))) from materias_primas));
-- Se solicitan 30,000 kg; aún sin pesada → descuenta lo solicitado
select guardar_orden('2026-11-21', (select id from formulas where nombre = 'NX FINALIZADOR'), 30000) as orden;
select kg_solicitados, kg_reales, kg_producidos, pendiente_pesada from v_ordenes;
select kg as sorgo_consumido from v_orden_consumos where materia_prima = 'SORGO';
-- Otro capturista registra la pesada: 29,450 kg
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
select registrar_pesada(1, 29450);
select kg_solicitados, kg_reales, kg_producidos, kg_diferencia, pct_diferencia, pendiente_pesada, capturado_por, modificado_por from v_ordenes;
select kg as sorgo_consumido from v_orden_consumos where materia_prima = 'SORGO';
select existencia_kg as sorgo_existencia from v_existencias_mp where nombre = 'SORGO';
-- Edición completa por capturista (cambia ingredientes y agrega un extra) → debe poder
select guardar_orden('2026-11-21', (select id from formulas where nombre = 'NX FINALIZADOR'), 30000,
  (select jsonb_agg(jsonb_build_object('materia_prima_id', materia_prima_id, 'kg_por_tonelada', kg_por_tonelada)) from v_orden_ingredientes where orden_id = 1),
  jsonb_build_array(jsonb_build_object('materia_prima_id', (select id from materias_primas where nombre = 'Toxad Plus'), 'cantidad', 1)),
  'Corregida', false, 1, null, 'cerdos', 29500) as editada;
select kg_solicitados, kg_reales, kg_producidos, extras, notas from v_ordenes;
select count(*) as ingredientes_guardados from v_orden_ingredientes where orden_id = 1;
\set ON_ERROR_STOP 0
select registrar_pesada(1, -5);
reset role;
