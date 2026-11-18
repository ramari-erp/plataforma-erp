-- =====================================================================
-- 0009_orden_area.sql — Área a la que va cada orden (cerdos, aves, ganado, borregos)
--   Por omisión, la de la fórmula; se puede cambiar en la orden.
-- =====================================================================

alter table ordenes_produccion add column area area_productiva;
update ordenes_produccion o set area = f.especie::area_productiva
from formulas f where f.id = o.formula_id and f.especie in ('cerdos', 'aves', 'ganado', 'borregos');
create index on ordenes_produccion (area, fecha);

drop function guardar_orden(date, bigint, numeric, jsonb, jsonb, text, boolean, bigint, bigint);

create or replace function guardar_orden(
  p_fecha date, p_formula_id bigint, p_kg numeric,
  p_ingredientes jsonb default '[]', p_extras jsonb default '[]',
  p_notas text default null, p_actualizar_formula boolean default false, p_orden_id bigint default null,
  p_granja_id bigint default null, p_area text default null
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
  if coalesce(p_kg, 0) <= 0 then raise exception 'Las toneladas producidas deben ser mayores a cero'; end if;

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
    insert into ordenes_produccion (fecha, formula_id, kg_producidos, notas, formula_modificada, granja_id, area)
    values (p_fecha, p_formula_id, p_kg, nullif(trim(p_notas), ''), v_mod and not p_actualizar_formula, p_granja_id, v_area)
    returning id into v_id;
  else
    update ordenes_produccion
      set fecha = p_fecha, formula_id = p_formula_id, kg_producidos = p_kg,
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

revoke execute on function guardar_orden(date, bigint, numeric, jsonb, jsonb, text, boolean, bigint, bigint, text) from anon;

create or replace view v_ordenes with (security_invoker = true) as
select o.id, o.fecha, o.formula_id, f.nombre as formula, f.especie, o.kg_producidos, o.notas,
       o.formula_modificada,
       (select count(*) from orden_extras e where e.orden_id = o.id) as extras,
       coalesce(c.costo_mp, 0) as costo_mp,
       case when o.kg_producidos > 0 then round(coalesce(c.costo_mp, 0) / o.kg_producidos, 4) end as costo_kg,
       pf.nombre as capturado_por, o.capturado_en,
       o.granja_id, g.nombre as granja, o.area
from ordenes_produccion o
join formulas f on f.id = o.formula_id
left join granjas g on g.id = o.granja_id
left join perfiles pf on pf.id = o.capturado_por
left join lateral (
  select round(sum(-m.kg * m.costo_kg), 2) as costo_mp
  from movimientos_mp m where m.origen = 'orden' and m.origen_id = o.id
) c on true;

drop view v_produccion_granja;
create view v_produccion_granja with (security_invoker = true) as
select o.fecha, o.area, coalesce(g.nombre, 'Sin granja') as granja, f.nombre as formula,
       count(*) as ordenes, sum(o.kg_producidos) as kg
from ordenes_produccion o
join formulas f on f.id = o.formula_id
left join granjas g on g.id = o.granja_id
group by o.fecha, o.area, g.nombre, f.nombre;

-- Qué áreas tiene cada granja (para filtrar la lista de granjas en la pantalla).
create or replace view v_granja_areas with (security_invoker = true) as
select distinct g.id as granja_id, g.nombre as granja, g.activa, ga.area
from granjas g join granja_areas ga on ga.granja_id = g.id;
