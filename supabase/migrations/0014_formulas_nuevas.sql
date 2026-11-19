-- =====================================================================
-- 0014_formulas_nuevas.sql — Alta de fórmulas desde la orden de producción
--   Cualquier capturista de planta puede crear una fórmula (nombre, área, etapa), partiendo de otra
--   fórmula (copia sus ingredientes) o vacía. Si queda vacía, los ingredientes de su primera orden se
--   vuelven su base. Queda "por revisar" hasta que el administrador la revisa.
-- =====================================================================

alter table formulas add column revisada boolean not null default true;
alter table formulas add column creada_por uuid references auth.users (id);
alter table formulas add column creada_en timestamptz;
alter table formulas add column copiada_de bigint references formulas (id);

create or replace function crear_formula(
  p_nombre text, p_especie text, p_etapa text default null, p_copiar_de bigint default null
) returns table (id bigint, nombre text, especie text)
language plpgsql security definer set search_path = public as $$
declare
  v_nombre text := regexp_replace(upper(trim(p_nombre)), '\s+', ' ', 'g');
  v_existe text;
  v_id bigint;
begin
  if not (puede_capturar('planta') or puede_capturar('catalogos')) then
    raise exception 'No tienes permiso para agregar fórmulas';
  end if;
  if coalesce(v_nombre, '') = '' then raise exception 'Escribe el nombre de la fórmula'; end if;
  if p_especie not in ('cerdos', 'aves', 'ganado', 'borregos', 'otro') then raise exception 'Elige el área de la fórmula'; end if;
  select f.nombre into v_existe from formulas f where nombre_normalizado(f.nombre) = nombre_normalizado(v_nombre) limit 1;
  if v_existe is not null then raise exception 'Ya existe la fórmula %', v_existe; end if;

  insert into formulas (nombre, especie, etapa, revisada, creada_por, creada_en, copiada_de, vigente_desde)
  values (v_nombre, p_especie, nullif(trim(p_etapa), ''), es_admin(), auth.uid(), now(), p_copiar_de, current_date)
  returning formulas.id into v_id;

  if p_copiar_de is not null then
    insert into formula_ingredientes (formula_id, materia_prima_id, kg_por_tonelada)
    select v_id, materia_prima_id, kg_por_tonelada from formula_ingredientes where formula_id = p_copiar_de;
  end if;

  return query select f.id, f.nombre, f.especie from formulas f where f.id = v_id;
end $$;
revoke execute on function crear_formula(text, text, text, bigint) from anon;

-- Llena la base de una fórmula SOLO si todavía no tiene ingredientes (fórmula recién creada).
-- Devuelve true si la llenó. La puede usar quien captura en planta.
create or replace function base_formula_vacia(p_formula_id bigint, p_ingredientes jsonb) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from formula_ingredientes where formula_id = p_formula_id)
     or jsonb_array_length(coalesce(p_ingredientes, '[]')) = 0 then
    return false;
  end if;
  if not (puede_capturar('planta') or puede_capturar('catalogos')) then
    raise exception 'No tienes permiso para capturar en planta';
  end if;
  insert into formula_ingredientes (formula_id, materia_prima_id, kg_por_tonelada)
  select p_formula_id, (x->>'materia_prima_id')::bigint, (x->>'kg_por_tonelada')::numeric
  from jsonb_array_elements(p_ingredientes) x;
  return true;
end $$;
revoke execute on function base_formula_vacia(bigint, jsonb) from anon;

-- guardar_orden(): igual que en 0010, más: una fórmula sin ingredientes toma los de su primera orden.
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

  -- Fórmula nueva sin ingredientes base: los de esta primera orden se vuelven su base.
  if base_formula_vacia(p_formula_id, p_ingredientes) then
    v_mod := false;
  end if;

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


-- Catálogo de fórmulas para la pantalla.
create or replace view v_formulas with (security_invoker = true) as
select f.id, f.nombre, f.especie, f.etapa, f.activa, f.revisada, f.notas, f.vigente_desde,
       pf.nombre as creada_por, f.creada_en, fc.nombre as copiada_de,
       count(fi.materia_prima_id) as ingredientes, coalesce(sum(fi.kg_por_tonelada), 0) as kg_por_tonelada,
       (select count(*) from ordenes_produccion o where o.formula_id = f.id) as ordenes,
       (select max(o.fecha) from ordenes_produccion o where o.formula_id = f.id) as ultima_orden
from formulas f
left join formula_ingredientes fi on fi.formula_id = f.id
left join perfiles pf on pf.id = f.creada_por
left join formulas fc on fc.id = f.copiada_de
group by f.id, pf.nombre, fc.nombre;

-- Ingredientes de cada fórmula con nombre (para ver el detalle).
create or replace view v_formula_ingredientes with (security_invoker = true) as
select fi.formula_id, fi.materia_prima_id, mp.nombre as materia_prima, mp.categoria, fi.kg_por_tonelada,
       coalesce(s.costo_promedio, 0) as costo_promedio
from formula_ingredientes fi
join materias_primas mp on mp.id = fi.materia_prima_id
left join saldos_mp s on s.materia_prima_id = fi.materia_prima_id;
