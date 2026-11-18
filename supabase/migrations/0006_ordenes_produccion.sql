-- =====================================================================
-- 0006_ordenes_produccion.sql — Órdenes de producción con fórmula ajustable y extras
--
--   * Cada orden guarda los ingredientes que REALMENTE se usaron (kg por tonelada), copiados de la
--     fórmula y modificables. Si después cambia la fórmula base, las órdenes anteriores no cambian.
--   * Extras: medicamentos o ingredientes agregados aparte, en kg por tonelada o en kg totales.
--   * Opcional (permiso de Catálogos): guardar los cambios como la nueva fórmula base.
-- Las órdenes se guardan con guardar_orden() para que todo quede en un solo paso.
-- =====================================================================

create table orden_ingredientes (
  orden_id          bigint not null references ordenes_produccion (id) on delete cascade,
  materia_prima_id  bigint not null references materias_primas (id),
  kg_por_tonelada   numeric(10,4) not null check (kg_por_tonelada > 0),
  primary key (orden_id, materia_prima_id)
);

create table orden_extras (
  id                bigint generated always as identity primary key,
  orden_id          bigint not null references ordenes_produccion (id) on delete cascade,
  materia_prima_id  bigint not null references materias_primas (id),
  cantidad          numeric(12,4) not null check (cantidad > 0),
  unidad            text not null default 'kg_por_tonelada' check (unidad in ('kg_por_tonelada', 'kg_total')),
  nota              text
);

alter table ordenes_produccion add column formula_modificada boolean not null default false;

select aplicar_seguridad('orden_ingredientes', 'planta');
select aplicar_seguridad('orden_extras', 'planta');

create or replace function sincronizar_movimientos(p_origen text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  afectadas bigint[];
  m bigint;
begin
  select coalesce(array_agg(distinct materia_prima_id), '{}') into afectadas
  from movimientos_mp where origen = p_origen and origen_id = p_id;

  delete from movimientos_mp where origen = p_origen and origen_id = p_id;

  if p_origen = 'inicial' then
    insert into movimientos_mp (fecha, materia_prima_id, bodega_id, tipo, kg, precio_kg, origen, origen_id)
    select i.fecha, i.materia_prima_id, mp.bodega_id, 'inicial', i.kg, i.costo_kg, 'inicial', i.materia_prima_id
    from inventario_inicial i join materias_primas mp on mp.id = i.materia_prima_id
    where i.materia_prima_id = p_id and i.kg > 0;

  elsif p_origen = 'llegada' then
    insert into movimientos_mp (fecha, materia_prima_id, bodega_id, tipo, kg, precio_kg, origen, origen_id)
    select l.fecha, l.materia_prima_id, coalesce(l.bodega_id, mp.bodega_id), 'llegada', l.kg_neto, l.precio_kg, 'llegada', l.id
    from llegadas_mp l join materias_primas mp on mp.id = l.materia_prima_id
    where l.id = p_id;

  elsif p_origen = 'orden' then
    -- Ingredientes que realmente se usaron en la orden; si la orden no los tiene, los de la fórmula.
    insert into movimientos_mp (fecha, materia_prima_id, bodega_id, tipo, kg, origen, origen_id)
    select o.fecha, i.materia_prima_id, mp.bodega_id, 'consumo',
           -(i.kg_por_tonelada * o.kg_producidos / 1000), 'orden', o.id
    from ordenes_produccion o
    join lateral (
      select oi.materia_prima_id, oi.kg_por_tonelada from orden_ingredientes oi where oi.orden_id = o.id
      union all
      select fi.materia_prima_id, fi.kg_por_tonelada from formula_ingredientes fi
      where fi.formula_id = o.formula_id
        and not exists (select 1 from orden_ingredientes oi2 where oi2.orden_id = o.id)
    ) i on true
    join materias_primas mp on mp.id = i.materia_prima_id
    where o.id = p_id
    union all
    -- Medicación por tonelada (tabla de la versión 0002)
    select o.fecha, om.materia_prima_id, mp.bodega_id, 'consumo',
           -(om.kg_por_tonelada * o.kg_producidos / 1000), 'orden', o.id
    from ordenes_produccion o
    join orden_medicacion om on om.orden_id = o.id
    join materias_primas mp on mp.id = om.materia_prima_id
    where o.id = p_id
    union all
    -- Extras: medicamentos o ingredientes agregados aparte
    select o.fecha, e.materia_prima_id, mp.bodega_id, 'consumo',
           -(case e.unidad when 'kg_total' then e.cantidad else e.cantidad * o.kg_producidos / 1000 end), 'orden', o.id
    from ordenes_produccion o
    join orden_extras e on e.orden_id = o.id
    join materias_primas mp on mp.id = e.materia_prima_id
    where o.id = p_id;

  elsif p_origen = 'ajuste' then
    insert into movimientos_mp (fecha, materia_prima_id, bodega_id, tipo, kg, origen, origen_id)
    select a.fecha, a.materia_prima_id, coalesce(a.bodega_id, mp.bodega_id), 'ajuste', a.kg, 'ajuste', a.id
    from ajustes_mp a join materias_primas mp on mp.id = a.materia_prima_id
    where a.id = p_id;
  end if;

  select coalesce(array_agg(distinct x), '{}') into afectadas
  from unnest(afectadas || array(
    select materia_prima_id from movimientos_mp where origen = p_origen and origen_id = p_id
  )) as x;

  foreach m in array afectadas loop
    perform recalcular_mp(m);
  end loop;
end $$;

-- p_ingredientes = [{"materia_prima_id": 1, "kg_por_tonelada": 745}, …]   (vacío = usar la fórmula tal cual)
-- p_extras       = [{"materia_prima_id": 60, "cantidad": 1, "unidad": "kg_por_tonelada", "nota": "…"}, …]
-- p_orden_id     = null para una orden nueva; el id para corregir una existente.
create or replace function guardar_orden(
  p_fecha date, p_formula_id bigint, p_kg numeric,
  p_ingredientes jsonb default '[]', p_extras jsonb default '[]',
  p_notas text default null, p_actualizar_formula boolean default false, p_orden_id bigint default null
) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_mod boolean;
begin
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
    insert into ordenes_produccion (fecha, formula_id, kg_producidos, notas, formula_modificada)
    values (p_fecha, p_formula_id, p_kg, nullif(trim(p_notas), ''), v_mod and not p_actualizar_formula)
    returning id into v_id;
  else
    update ordenes_produccion
      set fecha = p_fecha, formula_id = p_formula_id, kg_producidos = p_kg,
          notas = nullif(trim(p_notas), ''), formula_modificada = v_mod and not p_actualizar_formula
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

revoke execute on function guardar_orden(date, bigint, numeric, jsonb, jsonb, text, boolean, bigint) from anon;

-- Órdenes con su costo.
create or replace view v_ordenes with (security_invoker = true) as
select o.id, o.fecha, o.formula_id, f.nombre as formula, f.especie, o.kg_producidos, o.notas,
       o.formula_modificada,
       (select count(*) from orden_extras e where e.orden_id = o.id) as extras,
       coalesce(c.costo_mp, 0) as costo_mp,
       case when o.kg_producidos > 0 then round(coalesce(c.costo_mp, 0) / o.kg_producidos, 4) end as costo_kg,
       pf.nombre as capturado_por, o.capturado_en
from ordenes_produccion o
join formulas f on f.id = o.formula_id
left join perfiles pf on pf.id = o.capturado_por
left join lateral (
  select round(sum(-m.kg * m.costo_kg), 2) as costo_mp
  from movimientos_mp m where m.origen = 'orden' and m.origen_id = o.id
) c on true;

-- Lo que consumió cada orden.
create or replace view v_orden_consumos with (security_invoker = true) as
select m.origen_id as orden_id, mp.id as materia_prima_id, mp.nombre as materia_prima, mp.categoria,
       round(sum(-m.kg), 2) as kg, max(m.costo_kg) as costo_kg, round(sum(-m.kg * m.costo_kg), 2) as importe,
       exists (select 1 from orden_extras e where e.orden_id = m.origen_id and e.materia_prima_id = mp.id) as es_extra
from movimientos_mp m
join materias_primas mp on mp.id = m.materia_prima_id
where m.origen = 'orden'
group by m.origen_id, mp.id;

