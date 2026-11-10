-- =====================================================================
-- 0001_base.sql — Fase 0: usuarios, roles, permisos y catálogos generales
-- Plataforma ERP Pecuaria Real Victoria (Ramari)
-- Se ejecuta en Supabase: SQL Editor → pegar → Run.
-- =====================================================================

-- ---------- Usuarios y permisos ----------

create type rol_usuario as enum ('administrador', 'director', 'capturista', 'encargado_granja', 'consulta');

-- Un perfil por cada usuario de Supabase Auth.
create table perfiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  nombre      text not null,
  rol         rol_usuario not null default 'consulta',
  activo      boolean not null default true,
  creado_en   timestamptz not null default now()
);

-- Módulos de la plataforma. 'catalogos' = granjas, casetas, tolvas, proveedores, etc.
create table modulos (
  codigo  text primary key,
  nombre  text not null,
  orden   int  not null
);

insert into modulos (codigo, nombre, orden) values
  ('catalogos', 'Catálogos',            0),
  ('planta',    'Planta de alimentos',  1),
  ('finanzas',  'Finanzas',             2),
  ('cerdos',    'Cerdos',               3),
  ('aves',      'Aves',                 4),
  ('almacen',   'Almacén',              5),
  ('ganado',    'Ganado',               6),
  ('borregos',  'Borregos',             7),
  ('berries',   'Berries',              8),
  ('gastos',    'Gastos',               9),
  ('nomina',    'Nómina y empleados',  10),
  ('reportes',  'Reportes',            11);

-- Qué módulos puede capturar cada usuario (consultar: todos los usuarios activos).
create table perfil_modulos (
  perfil_id  uuid references perfiles (id) on delete cascade,
  modulo     text references modulos (codigo),
  primary key (perfil_id, modulo)
);

create or replace function es_usuario_activo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and activo);
$$;

create or replace function es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and activo and rol = 'administrador');
$$;

create or replace function puede_capturar(p_modulo text) returns boolean
language sql stable security definer set search_path = public as $$
  select es_admin() or exists (
    select 1 from perfil_modulos pm join perfiles p on p.id = pm.perfil_id
    where pm.perfil_id = auth.uid() and p.activo and pm.modulo = p_modulo
  );
$$;

-- Aplica las reglas de seguridad estándar a una tabla:
-- leer = cualquier usuario activo; capturar/editar = permiso del módulo; borrar = administrador.
create or replace function aplicar_seguridad(p_tabla text, p_modulo text) returns void
language plpgsql as $$
begin
  execute format('alter table %I enable row level security', p_tabla);
  execute format('create policy leer on %I for select to authenticated using (es_usuario_activo())', p_tabla);
  execute format('create policy capturar on %I for insert to authenticated with check (puede_capturar(%L))', p_tabla, p_modulo);
  execute format('create policy editar on %I for update to authenticated using (puede_capturar(%L)) with check (puede_capturar(%L))', p_tabla, p_modulo, p_modulo);
  execute format('create policy borrar on %I for delete to authenticated using (es_admin())', p_tabla);
end $$;

-- Quién capturó y cuándo, en todas las tablas de movimientos.
create or replace function marcar_captura() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.capturado_por := coalesce(new.capturado_por, auth.uid());
    new.capturado_en  := now();
  end if;
  new.modificado_en := now();
  return new;
end $$;

-- ---------- Granjas, casetas, tolvas ----------

create type area_productiva as enum ('cerdos', 'aves', 'ganado', 'borregos', 'berries');

create table granjas (
  id         bigint generated always as identity primary key,
  nombre     text not null unique,
  ubicacion  text,
  activa     boolean not null default true
);

-- Una granja puede tener varias áreas (La Red: cerdos S1 y S2, aves crianza, ganado, borregos).
-- subarea: cerdos → sitio1 | sitio2 | sitio3 | reemplazos | gestacion
--          aves   → postura | crianza
--          ganado → registro | comercial
create table granja_areas (
  id         bigint generated always as identity primary key,
  granja_id  bigint not null references granjas (id),
  area       area_productiva not null,
  subarea    text,
  unique (granja_id, area, subarea)
);

create table casetas (
  id                  bigint generated always as identity primary key,
  granja_id           bigint not null references granjas (id),
  area                area_productiva not null,
  nombre              text not null,          -- nombre como lo conocen en granja (aunque sea viejo, p. ej. "Engorda 2")
  uso                 text,                   -- uso real: gestación, maternidad, destete, engorda, postura, crianza…
  capacidad_animales  int,
  activa              boolean not null default true,
  unique (granja_id, nombre)
);

create table tolvas (
  id            bigint generated always as identity primary key,
  caseta_id     bigint not null references casetas (id),
  nombre        text not null,
  capacidad_kg  numeric(12,2) not null check (capacidad_kg > 0),
  activa        boolean not null default true,
  unique (caseta_id, nombre)
);

-- Lote, banda o parvada: el grupo de animales al que se le carga el alimento.
create table lotes (
  id            bigint generated always as identity primary key,
  area          area_productiva not null,
  tipo          text not null default 'lote' check (tipo in ('lote', 'banda', 'parvada', 'grupo')),
  codigo        text not null,
  granja_id     bigint references granjas (id),
  fecha_inicio  date,
  fecha_cierre  date,
  notas         text,
  unique (area, codigo)
);

-- Qué lote/banda está en cada caseta y desde cuándo (historial).
create table caseta_lotes (
  id         bigint generated always as identity primary key,
  caseta_id  bigint not null references casetas (id),
  lote_id    bigint not null references lotes (id),
  desde      date not null,
  hasta      date,
  check (hasta is null or hasta >= desde)
);

-- Lote que estaba en una caseta en una fecha (el más reciente si hay varios).
create or replace function lote_en_caseta(p_caseta bigint, p_fecha date) returns bigint
language sql stable as $$
  select lote_id from caseta_lotes
  where caseta_id = p_caseta and desde <= p_fecha and (hasta is null or hasta >= p_fecha)
  order by desde desc, id desc limit 1;
$$;

-- ---------- Personas y terceros ----------

create table empleados (
  id         bigint generated always as identity primary key,
  nombre     text not null,
  puesto     text,
  granja_id  bigint references granjas (id),
  area       text,              -- 'planta', 'cerdos', 'aves', … o administrativa
  activo     boolean not null default true,
  alta       date,
  baja       date
);

create table proveedores (
  id        bigint generated always as identity primary key,
  nombre    text not null unique,
  rfc       text,
  telefono  text,
  giro      text,               -- materia prima, medicamento, ferretería, servicios…
  activo    boolean not null default true
);

create table clientes (
  id        bigint generated always as identity primary key,
  nombre    text not null unique,
  rfc       text,
  telefono  text,
  areas     area_productiva[] not null default '{}',
  activo    boolean not null default true
);

-- ---------- Seguridad ----------

alter table perfiles enable row level security;
create policy leer on perfiles for select to authenticated using (id = auth.uid() or es_usuario_activo());
create policy administrar on perfiles for all to authenticated using (es_admin()) with check (es_admin());

alter table perfil_modulos enable row level security;
create policy leer on perfil_modulos for select to authenticated using (perfil_id = auth.uid() or es_admin());
create policy administrar on perfil_modulos for all to authenticated using (es_admin()) with check (es_admin());

alter table modulos enable row level security;
create policy leer on modulos for select to authenticated using (true);

select aplicar_seguridad(t, 'catalogos') from unnest(array[
  'granjas', 'granja_areas', 'casetas', 'tolvas', 'empleados', 'proveedores', 'clientes'
]) as t;

-- Lotes y su ubicación los mueven los capturistas de cada área.
select aplicar_seguridad('lotes', 'cerdos');
select aplicar_seguridad('caseta_lotes', 'cerdos');
-- (aves y otras áreas también podrán moverlos)
drop policy capturar on lotes;
drop policy editar on lotes;
create policy capturar on lotes for insert to authenticated
  with check (puede_capturar(area::text));
create policy editar on lotes for update to authenticated
  using (puede_capturar(area::text)) with check (puede_capturar(area::text));
drop policy capturar on caseta_lotes;
drop policy editar on caseta_lotes;
create policy capturar on caseta_lotes for insert to authenticated
  with check (puede_capturar((select area::text from casetas c where c.id = caseta_id)));
create policy editar on caseta_lotes for update to authenticated
  using (puede_capturar((select area::text from casetas c where c.id = caseta_id)))
  with check (puede_capturar((select area::text from casetas c where c.id = caseta_id)));

-- ---------- Granjas conocidas (las casetas y tolvas se capturan después) ----------

insert into granjas (nombre) values
  ('La Red'), ('Durazno'), ('Palenque'), ('San Pablo'), ('Rodadero'), ('Ramari'),
  ('Paraíso'), ('Princesita'), ('Josefino'), ('La Mesa');

insert into granja_areas (granja_id, area, subarea)
select g.id, x.area::area_productiva, x.subarea
from (values
  ('La Red', 'cerdos', 'sitio1'), ('La Red', 'cerdos', 'sitio2'),
  ('Durazno', 'cerdos', 'sitio1'), ('Palenque', 'cerdos', 'sitio1'),
  ('San Pablo', 'cerdos', 'sitio3'), ('Rodadero', 'cerdos', 'sitio3'), ('Ramari', 'cerdos', 'sitio3'),
  ('La Red', 'aves', 'crianza'),
  ('Durazno', 'aves', 'postura'), ('Paraíso', 'aves', 'postura'), ('Princesita', 'aves', 'postura'),
  ('Josefino', 'aves', 'postura'), ('La Mesa', 'aves', 'postura'),
  ('La Red', 'ganado', null), ('Rodadero', 'ganado', null), ('San Pablo', 'ganado', null),
  ('La Red', 'borregos', null), ('Ramari', 'borregos', null)
) as x (granja, area, subarea)
join granjas g on g.nombre = x.granja;

update granjas set activa = false where nombre in ('Josefino', 'La Mesa');  -- en construcción
