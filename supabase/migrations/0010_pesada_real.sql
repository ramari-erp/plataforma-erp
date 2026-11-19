-- =====================================================================
-- 0010_pesada_real.sql — Kg solicitados y kg reales de la pesada en cada orden
--
--   kg_solicitados : lo que se pidió producir.
--   kg_reales      : el total del lote en la báscula (se puede capturar después).
--   kg_producidos  : lo que cuenta para el inventario = kg_reales si ya hay pesada; si no, kg_solicitados.
--                    Al capturar o corregir la pesada, la materia prima se recalcula sola
--                    (los ingredientes se descuentan en proporción al total).
--   Cualquier capturista de planta puede modificar la orden; queda quién y cuándo.
-- =====================================================================

alter table ordenes_produccion add column kg_solicitados numeric(14,2) check (kg_solicitados > 0);
alter table ordenes_produccion add column kg_reales numeric(14,2) check (kg_reales > 0);
alter table ordenes_produccion add column modificado_por uuid references auth.users (id);

-- Las órdenes que ya existían: lo producido se toma como solicitado y como pesada real.
update ordenes_produccion set kg_solicitados = kg_producidos, kg_reales = kg_producidos;
alter table ordenes_produccion alter column kg_solicitados set not null;

-- kg_producidos siempre se calcula; y se registra quién modificó.
create or replace function trg_kg_orden() returns trigger language plpgsql as $$
begin
  new.kg_producidos := coalesce(new.kg_reales, new.kg_solicitados, new.kg_producidos);
  if new.kg_solicitados is null then new.kg_solicitados := new.kg_producidos; end if;
  if tg_op = 'UPDATE' then new.modificado_por := auth.uid(); end if;
  return new;
end $$;
create trigger kg_orden before insert or update on ordenes_produccion
  for each row execute function trg_kg_orden();

-- Al editar una orden se reemplazan sus ingredientes y extras: planta debe poder borrarlos.
create policy borrar_planta on orden_ingredientes for delete to authenticated using (puede_capturar('planta'));
create policy borrar_planta on orden_extras for delete to authenticated using (puede_capturar('planta'));

-- Registrar o corregir solo la pesada real (sin tocar ingredientes).
create or replace function registrar_pesada(p_orden_id bigint, p_kg_reales numeric) returns void
language plpgsql as $$
begin
  if p_kg_reales is not null and p_kg_reales <= 0 then raise exception 'Los kg reales deben ser mayores a cero'; end if;
  update ordenes_produccion set kg_reales = p_kg_reales where id = p_orden_id;
  if not found then raise exception 'No se encontró la orden % o no tienes permiso para cambiarla', p_orden_id; end if;
end $$;
revoke execute on function registrar_pesada(bigint, numeric) from anon;

drop function guardar_orden(date, bigint, numeric, jsonb, jsonb, text, boolean, bigint, bigint, text);

create or replace function guardar_orden(
  p_fecha date, p_formula_id bigint, p_kg numeric,
  p_ingredientes jsonb default '[]', p_extras jsonb default '[]',
  p_notas text default null, p_actualizar_formula boolean default false, p_orden_id bigint default null,
  p_granja_id bigint default null, p_area text default null, p_kg_reales numeric default null
) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_mod boolean;
  v_area area_productiva;
begin
  -- Área: la que mandan; si no, la de la fórmula.
  v_area := coalesce(nullif(p_area, '')::area_productiva,
    (select case when especie in ('cerdos', 'aves', 'ganado', 'borregos') then especie::area_productiva end from formulas where id = p_formula_id));
  if coalesce(p_kg, 0) <= 0 then raise exception 'Los kg solicitados deben ser mayores a cero'; end if;
  if p_kg_reales is not null and p_kg_reales <= 0 then raise exception 'Los kg reales deben ser mayores a cero'; end if;

  -- ¿Lo usado es distinto de la fórmula base?
  select exists (
      select materia_prima_id, kg_por_tonelada::numeric(10,4) from formula_ingredientes where formula_id = p_formula_id
      except
      select (x->>'materia_prima_id')::bigint, (x->>'kg_por_tonelada')::numeric(10,4) from jsonb_array_elements(p_ingredientes) x
    ) or exists (
      select (x->>'materia_prima_id')::bigint, (x->>'kg_por_tonelada')::numeric(10,4) from jsonb_array_elements(p_ingredientes) x
      except
      select materia_prima_id, kg_por_tonelada::numeric(10,4) from formula_ingredientes where formula_id = p_formula_id
    )
  into v_mod;
  v_mod := v_mod and jsonb_array_length(p_ingredientes) > 0;

  if p_orden_id is null then
    insert into ordenes_produccion (fecha, formula_id, kg_solicitados, kg_reales, kg_producidos, notas, formula_modificada, granja_id, area)
    values (p_fecha, p_formula_id, p_kg, p_kg_reales, coalesce(p_kg_reales, p_kg), nullif(trim(p_notas), ''), v_mod and not p_actualizar_formula, p_granja_id, v_area)
    returning id into v_id;
  else
    update ordenes_produccion
      set fecha = p_fecha, formula_id = p_formula_id, kg_solicitados = p_kg, kg_reales = p_kg_reales,
          kg_producidos = coalesce(p_kg_reales, p_kg),
          notas = nullif(trim(p_notas), ''), formula_modificada = v_mod and not p_actualizar_formula,
          granja_id = p_granja_id, area = v_area
      where id = p_orden_id
      returning id into v_id;
    if v_id is null then raise exception 'No se encontró la orden % o no tienes permiso para cambiarla', p_orden_id; end if;
  end if;

  -- La orden siempre guarda su propia copia de ingredientes (si no mandan lista, la de la fórmula de hoy).
  delete from orden_ingredientes where orden_id = v_id;
  if jsonb_array_length(p_ingredientes) > 0 then
    insert into orden_ingredientes (orden_id, materia_prima_id, kg_por_tonelada)
    select v_id, (x->>'materia_prima_id')::bigint, (x->>'kg_por_tonelada')::numeric
    from jsonb_array_elements(p_ingredientes) x;
  else
    insert into orden_ingredientes (orden_id, materia_prima_id, kg_por_tonelada)
    select v_id, materia_prima_id, kg_por_tonelada from formula_ingredientes where formula_id = p_formula_id;
  end if;

  delete from orden_extras where orden_id = v_id;
  insert into orden_extras (orden_id, materia_prima_id, cantidad, unidad, nota)
  select v_id, (x->>'materia_prima_id')::bigint, (x->>'cantidad')::numeric,
         coalesce(x->>'unidad', 'kg_por_tonelada'), nullif(trim(x->>'nota'), '')
  from jsonb_array_elements(p_extras) x;

  if p_actualizar_formula and jsonb_array_length(p_ingredientes) > 0 then
    if not puede_capturar('catalogos') then
      raise exception 'Solo quien tiene permiso de Catálogos puede cambiar la fórmula base';
    end if;
    delete from formula_ingredientes where formula_id = p_formula_id;
    insert into formula_ingredientes (formula_id, materia_prima_id, kg_por_tonelada)
    select p_formula_id, (x->>'materia_prima_id')::bigint, (x->>'kg_por_tonelada')::numeric
    from jsonb_array_elements(p_ingredientes) x;
  end if;

  perform sincronizar_movimientos('orden', v_id);
  return v_id;
end $$;

revoke execute on function guardar_orden(date, bigint, numeric, jsonb, jsonb, text, boolean, bigint, bigint, text, numeric) from anon;

-- Órdenes con solicitado, real y diferencia (columnas nuevas al final).
create or replace view v_ordenes with (security_invoker = true) as
select o.id, o.fecha, o.formula_id, f.nombre as formula, f.especie, o.kg_producidos, o.notas,
       o.formula_modificada,
       (select count(*) from orden_extras e where e.orden_id = o.id) as extras,
       coalesce(c.costo_mp, 0) as costo_mp,
       case when o.kg_producidos > 0 then round(coalesce(c.costo_mp, 0) / o.kg_producidos, 4) end as costo_kg,
       pf.nombre as capturado_por, o.capturado_en,
       o.granja_id, g.nombre as granja, o.area,
       o.kg_solicitados, o.kg_reales,
       o.kg_reales - o.kg_solicitados as kg_diferencia,
       case when o.kg_reales is not null and o.kg_solicitados > 0
            then round(100 * (o.kg_reales - o.kg_solicitados) / o.kg_solicitados, 2) end as pct_diferencia,
       (o.kg_reales is null) as pendiente_pesada,
       pm.nombre as modificado_por, o.modificado_en
from ordenes_produccion o
join formulas f on f.id = o.formula_id
left join granjas g on g.id = o.granja_id
left join perfiles pf on pf.id = o.capturado_por
left join perfiles pm on pm.id = o.modificado_por
left join lateral (
  select round(sum(-m.kg * m.costo_kg), 2) as costo_mp
  from movimientos_mp m where m.origen = 'orden' and m.origen_id = o.id
) c on true;


-- Ingredientes guardados en cada orden (para editarla).
create or replace view v_orden_ingredientes with (security_invoker = true) as
select oi.orden_id, oi.materia_prima_id, mp.nombre as materia_prima, oi.kg_por_tonelada
from orden_ingredientes oi join materias_primas mp on mp.id = oi.materia_prima_id;
