-- =====================================================================
-- 0013_materias_nuevas.sql — Alta de materias primas desde la captura de llegadas
--   Cualquier capturista de planta puede agregar una materia prima nueva; queda "por revisar"
--   hasta que el administrador la revisa (nombre, categoría, mínimo, contrato…).
-- =====================================================================

alter table materias_primas add column revisada boolean not null default true;
alter table materias_primas add column creada_por uuid references auth.users (id);
alter table materias_primas add column creada_en timestamptz;

-- Nombre sin acentos, mayúsculas ni espacios de más (para detectar duplicados).
create or replace function nombre_normalizado(p text) returns text
language sql immutable as $$
  select regexp_replace(translate(upper(trim(p)), 'ÁÉÍÓÚÜÑ', 'AEIOUUN'), '\s+', ' ', 'g');
$$;

create or replace function crear_materia_prima(
  p_nombre text, p_categoria text default 'ingrediente', p_presentacion text default null,
  p_grupo_almacen_id bigint default null
) returns table (id bigint, nombre text)
language plpgsql security definer set search_path = public as $$
declare
  v_nombre text := regexp_replace(upper(trim(p_nombre)), '\s+', ' ', 'g');
  v_existe text;
begin
  if not (puede_capturar('planta') or puede_capturar('catalogos')) then
    raise exception 'No tienes permiso para agregar materias primas';
  end if;
  if coalesce(v_nombre, '') = '' then raise exception 'Escribe el nombre de la materia prima'; end if;
  select mp.nombre into v_existe from materias_primas mp
  where nombre_normalizado(mp.nombre) = nombre_normalizado(v_nombre) limit 1;
  if v_existe is not null then
    raise exception 'Ya existe la materia prima %', v_existe;
  end if;
  return query
    insert into materias_primas (nombre, categoria, presentacion, grupo_almacen_id, revisada, creada_por, creada_en)
    values (v_nombre, coalesce(nullif(p_categoria, ''), 'ingrediente'), nullif(trim(p_presentacion), ''),
            p_grupo_almacen_id, es_admin(), auth.uid(), now())
    returning materias_primas.id, materias_primas.nombre;
end $$;
revoke execute on function crear_materia_prima(text, text, text, bigint) from anon;

-- Catálogo completo para la pantalla de materias primas.
create or replace view v_materias_primas with (security_invoker = true) as
select mp.id, mp.nombre, mp.categoria, mp.presentacion, mp.kg_por_presentacion, mp.grupo_almacen_id,
       ga.nombre as grupo_almacen, mp.stock_minimo_kg, mp.requiere_contrato, mp.precio_referencia,
       mp.activa, mp.revisada, pf.nombre as creada_por, mp.creada_en,
       coalesce(s.existencia_kg, 0) as existencia_kg, coalesce(s.costo_promedio, 0) as costo_promedio
from materias_primas mp
left join grupos_almacen ga on ga.id = mp.grupo_almacen_id
left join saldos_mp s on s.materia_prima_id = mp.id
left join perfiles pf on pf.id = mp.creada_por;

alter publication supabase_realtime add table materias_primas;
