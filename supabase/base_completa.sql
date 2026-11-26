-- =====================================================================
-- base_completa.sql — GENERADO por scripts/juntar_base.sh; no editar a mano.
-- Instala la base completa en un proyecto de Supabase NUEVO (vacío), en un solo paso.
-- En la base que ya está en uso NO se corre: ahí se siguen corriendo solo las migraciones nuevas.
-- Contiene, en orden: 29 archivos.
-- =====================================================================

-- >>>>>>>>>> migrations/0001_base.sql
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

-- >>>>>>>>>> migrations/0002_planta.sql
-- =====================================================================
-- 0002_planta.sql — Fase 1: Planta de alimentos
--
-- Regla: las existencias no se capturan, se calculan.
--   Llegada de materia prima  → entra al inventario (y recalcula el costo promedio ponderado)
--   Orden de producción       → descuenta materia prima según la fórmula + medicación agregada
--   Ajuste por conteo físico  → corrige diferencias
--   Salida a granja           → descuenta producto terminado; el alimento queda cargado
--                               a la granja, caseta y lote/banda.
-- Todo movimiento de materia prima queda en el kárdex `movimientos_mp`.
-- =====================================================================

-- ---------- Catálogos de planta ----------

create table bodegas (
  id            bigint generated always as identity primary key,
  nombre        text not null unique,
  tipo          text not null default 'bodega' check (tipo in ('silo', 'bodega', 'tanque', 'otro')),
  capacidad_kg  numeric(14,2) check (capacidad_kg > 0),
  activa        boolean not null default true
);

create table materias_primas (
  id                  bigint generated always as identity primary key,
  nombre              text not null unique,
  categoria           text not null default 'ingrediente'
                      check (categoria in ('grano', 'pasta', 'ingrediente', 'nucleo', 'aminoacido', 'mineral', 'medicamento', 'alimento_comprado', 'otro')),
  presentacion        text,                     -- granel, saco 25 kg, cubeta…
  kg_por_presentacion numeric(10,3),
  bodega_id           bigint references bodegas (id),   -- bodega donde normalmente se guarda
  stock_minimo_kg     numeric(14,2),
  activa              boolean not null default true
);

create table formulas (
  id              bigint generated always as identity primary key,
  nombre          text not null unique,
  especie         text not null check (especie in ('cerdos', 'aves', 'ganado', 'borregos', 'otro')),
  etapa           text,
  activa          boolean not null default true,
  vigente_desde   date,
  notas           text
);

-- kg de cada materia prima por tonelada (1,000 kg) de alimento terminado.
create table formula_ingredientes (
  formula_id        bigint references formulas (id) on delete cascade,
  materia_prima_id  bigint references materias_primas (id),
  kg_por_tonelada   numeric(10,3) not null check (kg_por_tonelada > 0),
  primary key (formula_id, materia_prima_id)
);

-- Nombres con que aparece cada fórmula en notas y pedidos ("Churro Fase 1 (H1)", "Fase 4 SMC"…).
create table formula_alias (
  alias       text primary key,
  formula_id  bigint not null references formulas (id) on delete cascade
);

create table camiones (
  id      bigint generated always as identity primary key,
  nombre  text not null unique,
  placas  text,
  capacidad_kg numeric(12,2),
  activo  boolean not null default true
);

-- ---------- Movimientos ----------

create table llegadas_mp (
  id                bigint generated always as identity primary key,
  fecha             date not null default current_date,
  proveedor_id      bigint references proveedores (id),
  materia_prima_id  bigint not null references materias_primas (id),
  bodega_id         bigint references bodegas (id),
  kg_bruto          numeric(14,2),
  kg_tara           numeric(14,2),
  kg_neto           numeric(14,2) not null check (kg_neto > 0),
  humedad_pct       numeric(5,2),
  precio_kg         numeric(12,4) not null check (precio_kg >= 0),  -- MXN/kg sin IVA, flete incluido
  total             numeric(16,2) generated always as (round(kg_neto * precio_kg, 2)) stored,
  factura           text,
  boleta            text,
  foto_url          text,
  notas             text,
  capturado_por     uuid references auth.users (id),
  capturado_en      timestamptz,
  modificado_en     timestamptz
);

create table pedidos_alimento (
  id               bigint generated always as identity primary key,
  fecha            date not null default current_date,
  granja_id        bigint not null references granjas (id),
  fecha_requerida  date,
  estado           text not null default 'pendiente' check (estado in ('pendiente', 'en_produccion', 'surtido', 'cancelado')),
  notas            text,
  capturado_por    uuid references auth.users (id),
  capturado_en     timestamptz,
  modificado_en    timestamptz
);

create table pedido_detalle (
  id          bigint generated always as identity primary key,
  pedido_id   bigint not null references pedidos_alimento (id) on delete cascade,
  caseta_id   bigint references casetas (id),
  formula_id  bigint not null references formulas (id),
  kg          numeric(12,2) not null check (kg > 0)
);

create table ordenes_produccion (
  id              bigint generated always as identity primary key,
  fecha           date not null default current_date,
  formula_id      bigint not null references formulas (id),
  kg_producidos   numeric(14,2) not null check (kg_producidos > 0),
  pedido_id       bigint references pedidos_alimento (id),
  notas           text,
  capturado_por   uuid references auth.users (id),
  capturado_en    timestamptz,
  modificado_en   timestamptz
);

-- Medicación o aditivos agregados a una orden (kg por tonelada de alimento).
create table orden_medicacion (
  orden_id          bigint references ordenes_produccion (id) on delete cascade,
  materia_prima_id  bigint references materias_primas (id),
  kg_por_tonelada   numeric(10,4) not null check (kg_por_tonelada > 0),
  primary key (orden_id, materia_prima_id)
);

create table salidas_alimento (
  id               bigint generated always as identity primary key,
  folio            text unique,
  fecha            date not null default current_date,
  granja_id        bigint not null references granjas (id),
  camion_id        bigint references camiones (id),
  chofer           text,
  kg_neto_bascula  numeric(14,2),
  foto_url         text,
  notas            text,
  capturado_por    uuid references auth.users (id),
  capturado_en     timestamptz,
  modificado_en    timestamptz
);

-- Un renglón por fórmula y caseta dentro del viaje. El lote/banda se llena solo.
create table salida_detalle (
  id          bigint generated always as identity primary key,
  salida_id   bigint not null references salidas_alimento (id) on delete cascade,
  caseta_id   bigint references casetas (id),
  lote_id     bigint references lotes (id),
  formula_id  bigint not null references formulas (id),
  kg          numeric(12,2) not null check (kg > 0)
);

-- Diferencias del inventario físico semanal (kg positivos = sobrante, negativos = faltante).
create table ajustes_mp (
  id                bigint generated always as identity primary key,
  fecha             date not null default current_date,
  materia_prima_id  bigint not null references materias_primas (id),
  bodega_id         bigint references bodegas (id),
  kg                numeric(14,2) not null check (kg <> 0),
  motivo            text not null,
  capturado_por     uuid references auth.users (id),
  capturado_en      timestamptz,
  modificado_en     timestamptz
);

-- Conteo físico semanal tal como se reporta (para comparar contra el sistema).
create table conteos_mp (
  id                bigint generated always as identity primary key,
  fecha             date not null default current_date,
  materia_prima_id  bigint not null references materias_primas (id),
  bodega_id         bigint references bodegas (id),
  kg_fisicos        numeric(14,2) not null check (kg_fisicos >= 0),
  kg_sistema        numeric(14,2),     -- se llena solo al guardar
  capturado_por     uuid references auth.users (id),
  capturado_en      timestamptz,
  modificado_en     timestamptz
);

-- ---------- Kárdex de materia prima ----------

create table movimientos_mp (
  id                  bigint generated always as identity primary key,
  fecha               date not null,
  materia_prima_id    bigint not null references materias_primas (id),
  bodega_id           bigint references bodegas (id),
  tipo                text not null check (tipo in ('llegada', 'consumo', 'ajuste')),
  kg                  numeric(16,4) not null,      -- + entra, − sale
  precio_kg           numeric(12,4),               -- solo llegadas
  costo_kg            numeric(12,4),               -- costo promedio aplicado (se calcula)
  existencia_despues  numeric(16,4),
  origen              text not null,               -- 'llegada' | 'orden' | 'ajuste'
  origen_id           bigint not null
);
create index on movimientos_mp (materia_prima_id, fecha, id);
create index on movimientos_mp (origen, origen_id);

-- Existencia y costo promedio ponderado vigentes.
create table saldos_mp (
  materia_prima_id  bigint primary key references materias_primas (id),
  existencia_kg     numeric(16,4) not null default 0,
  costo_promedio    numeric(12,4) not null default 0,
  actualizado_en    timestamptz not null default now()
);

-- Recalcula en orden cronológico la existencia y el costo promedio ponderado de una materia prima.
-- Llegada: costo = (existencia × costo + kg × precio) ÷ (existencia + kg).
-- Consumo/ajuste: se valúa al costo promedio del momento.
-- Al recorrer todo en orden, una captura con fecha atrasada queda bien calculada.
create or replace function recalcular_mp(p_mp bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  r      record;
  v_ex   numeric := 0;
  v_cost numeric := 0;
begin
  for r in
    select * from movimientos_mp where materia_prima_id = p_mp
    order by fecha, case tipo when 'llegada' then 0 when 'ajuste' then 1 else 2 end, id
  loop
    if r.tipo = 'llegada' then
      if v_ex > 0 then
        v_cost := (v_ex * v_cost + r.kg * r.precio_kg) / (v_ex + r.kg);
      else
        v_cost := r.precio_kg;
      end if;
    end if;
    v_ex := v_ex + r.kg;
    update movimientos_mp
      set costo_kg = round(v_cost, 4), existencia_despues = round(v_ex, 4)
      where id = r.id;
  end loop;

  insert into saldos_mp (materia_prima_id, existencia_kg, costo_promedio, actualizado_en)
  values (p_mp, round(v_ex, 4), round(v_cost, 4), now())
  on conflict (materia_prima_id) do update
    set existencia_kg = excluded.existencia_kg,
        costo_promedio = excluded.costo_promedio,
        actualizado_en = now();
end $$;

-- Rehace los movimientos de un documento (llegada, orden o ajuste) y recalcula lo afectado.
create or replace function sincronizar_movimientos(p_origen text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  afectadas bigint[];
  m bigint;
begin
  select coalesce(array_agg(distinct materia_prima_id), '{}') into afectadas
  from movimientos_mp where origen = p_origen and origen_id = p_id;

  delete from movimientos_mp where origen = p_origen and origen_id = p_id;

  if p_origen = 'llegada' then
    insert into movimientos_mp (fecha, materia_prima_id, bodega_id, tipo, kg, precio_kg, origen, origen_id)
    select l.fecha, l.materia_prima_id, coalesce(l.bodega_id, mp.bodega_id), 'llegada', l.kg_neto, l.precio_kg, 'llegada', l.id
    from llegadas_mp l join materias_primas mp on mp.id = l.materia_prima_id
    where l.id = p_id;

  elsif p_origen = 'orden' then
    insert into movimientos_mp (fecha, materia_prima_id, bodega_id, tipo, kg, origen, origen_id)
    select o.fecha, fi.materia_prima_id, mp.bodega_id, 'consumo',
           -(fi.kg_por_tonelada * o.kg_producidos / 1000), 'orden', o.id
    from ordenes_produccion o
    join formula_ingredientes fi on fi.formula_id = o.formula_id
    join materias_primas mp on mp.id = fi.materia_prima_id
    where o.id = p_id
    union all
    select o.fecha, om.materia_prima_id, mp.bodega_id, 'consumo',
           -(om.kg_por_tonelada * o.kg_producidos / 1000), 'orden', o.id
    from ordenes_produccion o
    join orden_medicacion om on om.orden_id = o.id
    join materias_primas mp on mp.id = om.materia_prima_id
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

create or replace function trg_sync_llegada() returns trigger language plpgsql as $$
begin
  perform sincronizar_movimientos('llegada', coalesce(new.id, old.id));
  return null;
end $$;

create or replace function trg_sync_orden() returns trigger language plpgsql as $$
begin
  perform sincronizar_movimientos('orden', coalesce(new.id, old.id));
  return null;
end $$;

create or replace function trg_sync_orden_medicacion() returns trigger language plpgsql as $$
begin
  perform sincronizar_movimientos('orden', coalesce(new.orden_id, old.orden_id));
  return null;
end $$;

create or replace function trg_sync_ajuste() returns trigger language plpgsql as $$
begin
  perform sincronizar_movimientos('ajuste', coalesce(new.id, old.id));
  return null;
end $$;

create trigger sync_mov after insert or update or delete on llegadas_mp
  for each row execute function trg_sync_llegada();
create trigger sync_mov after insert or update or delete on ordenes_produccion
  for each row execute function trg_sync_orden();
create trigger sync_mov after insert or update or delete on orden_medicacion
  for each row execute function trg_sync_orden_medicacion();
create trigger sync_mov after insert or update or delete on ajustes_mp
  for each row execute function trg_sync_ajuste();

-- Si cambia una fórmula, las órdenes ya registradas NO cambian: se recalculan solo si
-- el administrador lo pide con  select sincronizar_movimientos('orden', <id>);

-- Lote/banda automático en cada renglón de salida.
create or replace function trg_lote_salida() returns trigger language plpgsql as $$
begin
  if new.lote_id is null and new.caseta_id is not null then
    new.lote_id := lote_en_caseta(new.caseta_id, (select fecha from salidas_alimento where id = new.salida_id));
  end if;
  return new;
end $$;
create trigger lote_auto before insert or update on salida_detalle
  for each row execute function trg_lote_salida();

-- Existencia del sistema al momento del conteo físico.
create or replace function trg_conteo_sistema() returns trigger language plpgsql as $$
begin
  new.kg_sistema := coalesce((
    select sum(kg) from movimientos_mp
    where materia_prima_id = new.materia_prima_id and fecha <= new.fecha
  ), 0);
  return new;
end $$;
create trigger kg_sistema before insert or update on conteos_mp
  for each row execute function trg_conteo_sistema();

-- Quién capturó.
create trigger captura before insert or update on llegadas_mp        for each row execute function marcar_captura();
create trigger captura before insert or update on pedidos_alimento   for each row execute function marcar_captura();
create trigger captura before insert or update on ordenes_produccion for each row execute function marcar_captura();
create trigger captura before insert or update on salidas_alimento   for each row execute function marcar_captura();
create trigger captura before insert or update on ajustes_mp         for each row execute function marcar_captura();
create trigger captura before insert or update on conteos_mp         for each row execute function marcar_captura();

-- ---------- Vistas para el tablero ----------

-- Existencia por materia prima, contra mínimo.
create or replace view v_existencias_mp with (security_invoker = true) as
select mp.id, mp.nombre, mp.categoria, b.nombre as bodega,
       coalesce(s.existencia_kg, 0) as existencia_kg,
       coalesce(s.costo_promedio, 0) as costo_promedio,
       round(coalesce(s.existencia_kg, 0) * coalesce(s.costo_promedio, 0), 2) as valor_inventario,
       mp.stock_minimo_kg,
       (mp.stock_minimo_kg is not null and coalesce(s.existencia_kg, 0) < mp.stock_minimo_kg) as bajo_minimo
from materias_primas mp
left join saldos_mp s on s.materia_prima_id = mp.id
left join bodegas b on b.id = mp.bodega_id
where mp.activa;

-- Ocupación de cada bodega contra su capacidad.
create or replace view v_bodegas with (security_invoker = true) as
select b.id, b.nombre, b.tipo, b.capacidad_kg,
       coalesce(sum(m.kg), 0) as existencia_kg,
       case when b.capacidad_kg > 0 then round(100 * coalesce(sum(m.kg), 0) / b.capacidad_kg, 1) end as ocupacion_pct
from bodegas b
left join movimientos_mp m on m.bodega_id = b.id
where b.activa
group by b.id;

-- Costo de materia prima (incl. medicación) por kg de cada orden producida.
create or replace view v_costo_ordenes with (security_invoker = true) as
select o.id, o.fecha, f.nombre as formula, o.kg_producidos,
       round(sum(-m.kg * m.costo_kg), 2) as costo_mp,
       round(sum(-m.kg * m.costo_kg) / o.kg_producidos, 4) as costo_kg
from ordenes_produccion o
join formulas f on f.id = o.formula_id
left join movimientos_mp m on m.origen = 'orden' and m.origen_id = o.id
group by o.id, f.nombre;

-- Costo teórico por kg de cada fórmula con los costos promedio de hoy.
create or replace view v_costo_formulas with (security_invoker = true) as
select f.id, f.nombre, f.especie,
       sum(fi.kg_por_tonelada) as kg_por_tonelada,
       round(sum(fi.kg_por_tonelada * coalesce(s.costo_promedio, 0)) / 1000, 4) as costo_kg_hoy
from formulas f
join formula_ingredientes fi on fi.formula_id = f.id
left join saldos_mp s on s.materia_prima_id = fi.materia_prima_id
where f.activa
group by f.id;

-- Producto terminado en planta: producido − despachado, por fórmula.
create or replace view v_producto_terminado with (security_invoker = true) as
select f.id, f.nombre,
       coalesce(p.kg, 0) as kg_producidos,
       coalesce(d.kg, 0) as kg_despachados,
       coalesce(p.kg, 0) - coalesce(d.kg, 0) as kg_en_planta
from formulas f
left join (select formula_id, sum(kg_producidos) kg from ordenes_produccion group by 1) p on p.formula_id = f.id
left join (select formula_id, sum(kg) kg from salida_detalle group by 1) d on d.formula_id = f.id
where p.kg is not null or d.kg is not null;

-- Alimento enviado: un renglón por viaje, fórmula y caseta, con granja y lote.
create or replace view v_salidas with (security_invoker = true) as
select s.id as salida_id, s.folio, s.fecha, g.nombre as granja, c.nombre as caseta, c.area,
       l.codigo as lote, f.nombre as formula, d.kg, s.kg_neto_bascula, cam.nombre as camion, s.chofer
from salidas_alimento s
join granjas g on g.id = s.granja_id
join salida_detalle d on d.salida_id = s.id
join formulas f on f.id = d.formula_id
left join casetas c on c.id = d.caseta_id
left join lotes l on l.id = d.lote_id
left join camiones cam on cam.id = s.camion_id;

-- Viajes y kg enviados por día.
create or replace view v_viajes_dia with (security_invoker = true) as
select s.fecha, count(distinct s.id) as viajes, sum(d.kg) as kg
from salidas_alimento s join salida_detalle d on d.salida_id = s.id
group by s.fecha;

-- ---------- Seguridad ----------

select aplicar_seguridad(t, 'catalogos') from unnest(array[
  'bodegas', 'materias_primas', 'formulas', 'formula_ingredientes', 'formula_alias', 'camiones'
]) as t;

select aplicar_seguridad(t, 'planta') from unnest(array[
  'llegadas_mp', 'pedidos_alimento', 'pedido_detalle', 'ordenes_produccion', 'orden_medicacion',
  'salidas_alimento', 'salida_detalle', 'ajustes_mp', 'conteos_mp'
]) as t;

-- El kárdex y los saldos solo los escribe el sistema (funciones security definer).
alter table movimientos_mp enable row level security;
create policy leer on movimientos_mp for select to authenticated using (es_usuario_activo());
alter table saldos_mp enable row level security;
create policy leer on saldos_mp for select to authenticated using (es_usuario_activo());

-- >>>>>>>>>> seed/0001_catalogo_planta.sql
-- Generado desde Costo_Alimento_por_Granja_Jul-Sep_2026.xlsx (hojas Precios_MP, Precios_Med, Formulas).
-- Catálogo inicial: revisar y completar. No carga inventario (eso es el conteo de arranque).

insert into materias_primas (nombre, categoria) values
  ('SORGO', 'grano'),
  ('MAIZ', 'grano'),
  ('PASTA DE SOYA', 'pasta'),
  ('SALVADO', 'ingrediente'),
  ('LIPOFEED', 'ingrediente'),
  ('SAL', 'mineral'),
  ('CALCIO MOLIDO', 'mineral'),
  ('CALCIO QUEBRADO / GRANULADO', 'mineral'),
  ('ORTOFOSFATO', 'mineral'),
  ('CARBONATO', 'mineral'),
  ('NÚCLEO AMARILLO (VITAMINA PV)', 'nucleo'),
  ('METIONINA', 'aminoacido'),
  ('LISINA', 'aminoacido'),
  ('TREONINA', 'aminoacido'),
  ('VALINA', 'aminoacido'),
  ('ISOLEUCINA', 'aminoacido'),
  ('TRIPTÓFANO', 'aminoacido'),
  ('BIOCOLINA', 'ingrediente'),
  ('LIQUITRACE', 'ingrediente'),
  ('NÚCLEO CRECIMIENTO NX', 'nucleo'),
  ('NÚCLEO DESARROLLO NX', 'nucleo'),
  ('NÚCLEO FINALIZADOR NX', 'nucleo'),
  ('NÚCLEO GESTACIÓN NX', 'nucleo'),
  ('NÚCLEO INICIADOR REFORZADO NX', 'nucleo'),
  ('NÚCLEO LACTANCIA NX', 'nucleo'),
  ('NÚCLEO REEMPLAZOS 1 NX', 'nucleo'),
  ('NÚCLEO REEMPLAZOS 2 NX', 'nucleo'),
  ('NÚCLEO REEMPLAZOS 3 NX', 'nucleo'),
  ('NÚCLEO CRECIMIENTO SMC', 'nucleo'),
  ('NÚCLEO DESARROLLO SMC', 'nucleo'),
  ('NÚCLEO FINALIZADOR SMC', 'nucleo'),
  ('NÚCLEO INICIADOR SMC', 'nucleo'),
  ('NÚCLEO PREINICIADOR 2-3', 'nucleo'),
  ('NÚCLEO SMC GESTACIÓN', 'nucleo'),
  ('NÚCLEO SMC LACTANCIA', 'nucleo'),
  ('NÚCLEO INICIADOR MNA', 'nucleo'),
  ('NÚCLEO MNA DESARROLLO GANADO', 'nucleo'),
  ('NÚCLEO MNA FINALIZADOR GANADO', 'nucleo'),
  ('NÚCLEO MNA BORREGOS ENGORDA', 'nucleo'),
  ('POWER FEED UNO- CHURRO FASE 1', 'alimento_comprado'),
  ('POWER FEED DOS- CHURRO FASE 2', 'alimento_comprado'),
  ('POWER FEED TRES- CHURRO FASE 3', 'alimento_comprado'),
  ('Linco-Zoo 11%', 'medicamento'),
  ('Eco-Mutin CTC', 'medicamento'),
  ('Myco-Ad ZT', 'medicamento'),
  ('Bz Farm', 'medicamento'),
  ('Fosfomicina', 'medicamento'),
  ('Dysguard-S', 'medicamento'),
  ('Tylosin 22%', 'medicamento'),
  ('Zytra PM', 'medicamento'),
  ('AM80', 'medicamento'),
  ('TM40', 'medicamento'),
  ('Eco-Flor 4%', 'medicamento'),
  ('Eco-Flor Plus / premix', 'medicamento'),
  ('Flor FC', 'medicamento'),
  ('Colistina', 'medicamento'),
  ('Neumoenter', 'medicamento'),
  ('Elan C-12', 'medicamento'),
  ('Certyl', 'medicamento'),
  ('Suramox', 'medicamento'),
  ('Liquitrace', 'medicamento'),
  ('Saborizante', 'medicamento'),
  ('Ivermix / desparasitante', 'medicamento'),
  ('Aflorax Maxx', 'medicamento'),
  ('Toxad Plus', 'medicamento'),
  ('Oxitetraciclina', 'medicamento'),
  ('Terradina', 'medicamento')
on conflict (nombre) do nothing;

insert into formulas (nombre, especie) values
  ('MNA INICIADOR', 'ganado'),
  ('MOLIDO SORGO', 'ganado'),
  ('NX CRECIMIENTO', 'cerdos'),
  ('NX DESARROLLO', 'cerdos'),
  ('NX FINALIZADOR', 'cerdos'),
  ('NX GESTACIÓN', 'cerdos'),
  ('NX INICIADOR REFORZADO', 'cerdos'),
  ('NX LACTANCIA', 'cerdos'),
  ('NX REEMPLAZOS 1', 'cerdos'),
  ('NX REEMPLAZOS 2', 'cerdos'),
  ('NX REEMPLAZOS 3', 'cerdos'),
  ('SMC CRECIMIENTO', 'cerdos'),
  ('SMC DESARROLLO', 'cerdos'),
  ('SMC FINALIZADOR', 'cerdos'),
  ('SMC INICIADOR (FASE 4 SMC)', 'cerdos'),
  ('SMC PREINICIADOR 2-3', 'cerdos'),
  ('SMC GESTACIÓN', 'cerdos'),
  ('SMC LACTANCIA', 'cerdos'),
  ('MNA DESARROLLO GANADO', 'ganado'),
  ('MNA FINALIZADOR GANADO', 'ganado'),
  ('MNA BORREGOS ENGORDA', 'borregos'),
  ('BOOSTER', 'aves'),
  ('CHURRO FASE 2 (POWER FEED DOS)', 'cerdos'),
  ('CHURRO FASE 1 (POWER FEED UNO)', 'cerdos'),
  ('CHURRO FASE 3 (POWER FEED TRES)', 'cerdos'),
  ('FASE 1', 'aves'),
  ('FASE 2', 'aves'),
  ('PELECHA 3', 'aves'),
  ('PELECHA 4', 'aves')
on conflict (nombre) do nothing;

insert into formula_ingredientes (formula_id, materia_prima_id, kg_por_tonelada)
select f.id, m.id, x.kg from (values
  ('MNA INICIADOR', 'SORGO', 458),
  ('MOLIDO SORGO', 'SORGO', 1000),
  ('NX CRECIMIENTO', 'SORGO', 742),
  ('NX DESARROLLO', 'SORGO', 783),
  ('NX FINALIZADOR', 'SORGO', 745),
  ('NX GESTACIÓN', 'SORGO', 644),
  ('NX INICIADOR REFORZADO', 'SORGO', 684),
  ('NX LACTANCIA', 'SORGO', 706),
  ('NX REEMPLAZOS 1', 'SORGO', 744),
  ('NX REEMPLAZOS 2', 'SORGO', 817),
  ('NX REEMPLAZOS 3', 'SORGO', 807),
  ('SMC CRECIMIENTO', 'SORGO', 758),
  ('SMC DESARROLLO', 'SORGO', 784),
  ('SMC FINALIZADOR', 'SORGO', 738),
  ('SMC INICIADOR (FASE 4 SMC)', 'SORGO', 697),
  ('SMC PREINICIADOR 2-3', 'SORGO', 561),
  ('SMC GESTACIÓN', 'SORGO', 669),
  ('SMC LACTANCIA', 'SORGO', 636),
  ('MNA DESARROLLO GANADO', 'SORGO', 698),
  ('MNA FINALIZADOR GANADO', 'SORGO', 870),
  ('MNA BORREGOS ENGORDA', 'SORGO', 767),
  ('MNA INICIADOR', 'PASTA DE SOYA', 290),
  ('NX CRECIMIENTO', 'PASTA DE SOYA', 225),
  ('NX DESARROLLO', 'PASTA DE SOYA', 185),
  ('NX FINALIZADOR', 'PASTA DE SOYA', 225),
  ('NX GESTACIÓN', 'PASTA DE SOYA', 130),
  ('NX INICIADOR REFORZADO', 'PASTA DE SOYA', 275),
  ('NX LACTANCIA', 'PASTA DE SOYA', 250),
  ('NX REEMPLAZOS 1', 'PASTA DE SOYA', 225),
  ('NX REEMPLAZOS 2', 'PASTA DE SOYA', 155),
  ('NX REEMPLAZOS 3', 'PASTA DE SOYA', 115),
  ('SMC CRECIMIENTO', 'PASTA DE SOYA', 215),
  ('SMC DESARROLLO', 'PASTA DE SOYA', 190),
  ('SMC FINALIZADOR', 'PASTA DE SOYA', 235),
  ('SMC INICIADOR (FASE 4 SMC)', 'PASTA DE SOYA', 260),
  ('SMC PREINICIADOR 2-3', 'PASTA DE SOYA', 260),
  ('SMC GESTACIÓN', 'PASTA DE SOYA', 105),
  ('SMC LACTANCIA', 'PASTA DE SOYA', 240),
  ('MNA DESARROLLO GANADO', 'PASTA DE SOYA', 198),
  ('MNA FINALIZADOR GANADO', 'PASTA DE SOYA', 109),
  ('BOOSTER', 'PASTA DE SOYA', 185),
  ('MNA BORREGOS ENGORDA', 'PASTA DE SOYA', 105),
  ('MNA INICIADOR', 'SALVADO', 200),
  ('NX GESTACIÓN', 'SALVADO', 200),
  ('NX REEMPLAZOS 3', 'SALVADO', 50),
  ('SMC GESTACIÓN', 'SALVADO', 190),
  ('SMC LACTANCIA', 'SALVADO', 80),
  ('MNA DESARROLLO GANADO', 'SALVADO', 79),
  ('MNA BORREGOS ENGORDA', 'SALVADO', 100),
  ('MNA INICIADOR', 'LIPOFEED', 2),
  ('NX CRECIMIENTO', 'LIPOFEED', 2),
  ('NX DESARROLLO', 'LIPOFEED', 2),
  ('NX FINALIZADOR', 'LIPOFEED', 2),
  ('NX INICIADOR REFORZADO', 'LIPOFEED', 4),
  ('NX LACTANCIA', 'LIPOFEED', 4),
  ('NX REEMPLAZOS 1', 'LIPOFEED', 2),
  ('SMC CRECIMIENTO', 'LIPOFEED', 2),
  ('SMC DESARROLLO', 'LIPOFEED', 1),
  ('SMC FINALIZADOR', 'LIPOFEED', 2),
  ('SMC INICIADOR (FASE 4 SMC)', 'LIPOFEED', 3),
  ('SMC PREINICIADOR 2-3', 'LIPOFEED', 4),
  ('SMC GESTACIÓN', 'LIPOFEED', 1),
  ('SMC LACTANCIA', 'LIPOFEED', 4),
  ('MNA DESARROLLO GANADO', 'LIPOFEED', 1),
  ('MNA FINALIZADOR GANADO', 'LIPOFEED', 2),
  ('BOOSTER', 'LIPOFEED', 2),
  ('MNA BORREGOS ENGORDA', 'LIPOFEED', 3),
  ('MNA INICIADOR', 'SAL', 25),
  ('BOOSTER', 'SAL', 2.6),
  ('NX CRECIMIENTO', 'CALCIO QUEBRADO / GRANULADO', 9),
  ('NX DESARROLLO', 'CALCIO QUEBRADO / GRANULADO', 9),
  ('NX FINALIZADOR', 'CALCIO QUEBRADO / GRANULADO', 8),
  ('NX GESTACIÓN', 'CALCIO QUEBRADO / GRANULADO', 10),
  ('NX INICIADOR REFORZADO', 'CALCIO QUEBRADO / GRANULADO', 8),
  ('NX LACTANCIA', 'CALCIO QUEBRADO / GRANULADO', 10),
  ('NX REEMPLAZOS 1', 'CALCIO QUEBRADO / GRANULADO', 9),
  ('NX REEMPLAZOS 2', 'CALCIO QUEBRADO / GRANULADO', 10),
  ('NX REEMPLAZOS 3', 'CALCIO QUEBRADO / GRANULADO', 10),
  ('BOOSTER', 'CALCIO QUEBRADO / GRANULADO', 40),
  ('NX CRECIMIENTO', 'ORTOFOSFATO', 4),
  ('NX DESARROLLO', 'ORTOFOSFATO', 2),
  ('NX FINALIZADOR', 'ORTOFOSFATO', 1),
  ('NX GESTACIÓN', 'ORTOFOSFATO', 6),
  ('NX INICIADOR REFORZADO', 'ORTOFOSFATO', 5),
  ('NX LACTANCIA', 'ORTOFOSFATO', 8),
  ('NX REEMPLAZOS 1', 'ORTOFOSFATO', 5),
  ('NX REEMPLAZOS 2', 'ORTOFOSFATO', 3),
  ('NX REEMPLAZOS 3', 'ORTOFOSFATO', 3),
  ('BOOSTER', 'ORTOFOSFATO', 11),
  ('NX CRECIMIENTO', 'NÚCLEO CRECIMIENTO NX', 18),
  ('SMC CRECIMIENTO', 'NÚCLEO CRECIMIENTO SMC', 25),
  ('NX DESARROLLO', 'NÚCLEO DESARROLLO NX', 19),
  ('SMC DESARROLLO', 'NÚCLEO DESARROLLO SMC', 25),
  ('NX FINALIZADOR', 'NÚCLEO FINALIZADOR NX', 19),
  ('SMC FINALIZADOR', 'NÚCLEO FINALIZADOR SMC', 25),
  ('NX GESTACIÓN', 'NÚCLEO GESTACIÓN NX', 10),
  ('NX INICIADOR REFORZADO', 'NÚCLEO INICIADOR REFORZADO NX', 24),
  ('SMC INICIADOR (FASE 4 SMC)', 'NÚCLEO INICIADOR SMC', 40),
  ('NX LACTANCIA', 'NÚCLEO LACTANCIA NX', 22),
  ('MNA INICIADOR', 'NÚCLEO INICIADOR MNA', 25),
  ('NX REEMPLAZOS 1', 'NÚCLEO REEMPLAZOS 1 NX', 15),
  ('NX REEMPLAZOS 2', 'NÚCLEO REEMPLAZOS 2 NX', 15),
  ('NX REEMPLAZOS 3', 'NÚCLEO REEMPLAZOS 3 NX', 15),
  ('SMC GESTACIÓN', 'NÚCLEO SMC GESTACIÓN', 35),
  ('SMC LACTANCIA', 'NÚCLEO SMC LACTANCIA', 40),
  ('SMC PREINICIADOR 2-3', 'NÚCLEO PREINICIADOR 2-3', 175),
  ('MNA DESARROLLO GANADO', 'NÚCLEO MNA DESARROLLO GANADO', 24),
  ('MNA FINALIZADOR GANADO', 'NÚCLEO MNA FINALIZADOR GANADO', 19),
  ('BOOSTER', 'MAIZ', 690.17),
  ('BOOSTER', 'CALCIO MOLIDO', 60),
  ('MNA BORREGOS ENGORDA', 'NÚCLEO MNA BORREGOS ENGORDA', 25),
  ('CHURRO FASE 2 (POWER FEED DOS)', 'POWER FEED DOS- CHURRO FASE 2', 1000),
  ('CHURRO FASE 1 (POWER FEED UNO)', 'POWER FEED UNO- CHURRO FASE 1', 1000),
  ('CHURRO FASE 3 (POWER FEED TRES)', 'POWER FEED TRES- CHURRO FASE 3', 1000),
  ('BOOSTER', 'NÚCLEO AMARILLO (VITAMINA PV)', 3),
  ('BOOSTER', 'METIONINA', 2.43),
  ('BOOSTER', 'LISINA', 2.25),
  ('BOOSTER', 'TREONINA', 0.7),
  ('BOOSTER', 'VALINA', 0.75),
  ('BOOSTER', 'TRIPTÓFANO', 0.1),
  ('FASE 1', 'MAIZ', 671.3),
  ('FASE 1', 'PASTA DE SOYA', 205),
  ('FASE 1', 'CALCIO MOLIDO', 42),
  ('FASE 1', 'CALCIO QUEBRADO / GRANULADO', 63),
  ('FASE 1', 'LIPOFEED', 2.5),
  ('FASE 1', 'ORTOFOSFATO', 8),
  ('FASE 1', 'NÚCLEO AMARILLO (VITAMINA PV)', 3),
  ('FASE 1', 'SAL', 2.6),
  ('FASE 1', 'METIONINA', 1.16),
  ('FASE 1', 'LISINA', 1.1),
  ('FASE 1', 'BIOCOLINA', 0.19),
  ('FASE 1', 'ISOLEUCINA', 0.15),
  ('FASE 2', 'MAIZ', 683),
  ('FASE 2', 'PASTA DE SOYA', 191),
  ('FASE 2', 'CALCIO MOLIDO', 44),
  ('FASE 2', 'CALCIO QUEBRADO / GRANULADO', 66),
  ('FASE 2', 'LIPOFEED', 2),
  ('FASE 2', 'ORTOFOSFATO', 6),
  ('FASE 2', 'NÚCLEO AMARILLO (VITAMINA PV)', 3),
  ('FASE 2', 'SAL', 2.6),
  ('FASE 2', 'METIONINA', 1.06),
  ('FASE 2', 'ISOLEUCINA', 0.15),
  ('FASE 2', 'LISINA', 1.2),
  ('FASE 2', 'BIOCOLINA', 0.19),
  ('PELECHA 3', 'MAIZ', 728.2),
  ('PELECHA 3', 'PASTA DE SOYA', 145),
  ('PELECHA 3', 'CALCIO MOLIDO', 44),
  ('PELECHA 3', 'CALCIO QUEBRADO / GRANULADO', 66),
  ('PELECHA 3', 'ORTOFOSFATO', 9),
  ('PELECHA 3', 'NÚCLEO AMARILLO (VITAMINA PV)', 3),
  ('PELECHA 3', 'SAL', 2.8),
  ('PELECHA 3', 'METIONINA', 0.64),
  ('PELECHA 3', 'LISINA', 1.2),
  ('PELECHA 3', 'BIOCOLINA', 0.19),
  ('PELECHA 4', 'MAIZ', 734.3),
  ('PELECHA 4', 'PASTA DE SOYA', 138),
  ('PELECHA 4', 'CALCIO MOLIDO', 45),
  ('PELECHA 4', 'CALCIO QUEBRADO / GRANULADO', 67),
  ('PELECHA 4', 'ORTOFOSFATO', 8),
  ('PELECHA 4', 'NÚCLEO AMARILLO (VITAMINA PV)', 3),
  ('PELECHA 4', 'SAL', 2.8),
  ('PELECHA 4', 'METIONINA', 0.54),
  ('PELECHA 4', 'LISINA', 1.2),
  ('PELECHA 4', 'BIOCOLINA', 0.19)
) as x (formula, ingrediente, kg)
join formulas f on f.nombre = x.formula
join materias_primas m on m.nombre = x.ingrediente
on conflict do nothing;

-- >>>>>>>>>> migrations/0003_capacidades_planta.sql
-- =====================================================================
-- 0003_capacidades_planta.sql — Capacidad de almacenamiento de la planta
--
-- En la planta los espacios se comparten (la zona roja del croquis es "sorgo y/o maíz"),
-- así que la capacidad se controla por GRUPO de materias primas, no por bodega:
--   existencia del grupo = suma de las existencias de sus materias primas
--   capacidad del grupo  = capacidad en piso/bodega + capacidad en tolvas de la planta
-- Fuente: tabla de capacidades y croquis de planta (17-nov-2026).
-- =====================================================================

create table grupos_almacen (
  id                    bigint generated always as identity primary key,
  nombre                text not null unique,
  capacidad_planta_kg   numeric(14,2) not null default 0 check (capacidad_planta_kg >= 0),
  capacidad_tolvas_kg   numeric(14,2) not null default 0 check (capacidad_tolvas_kg >= 0),
  orden                 int not null default 0,
  notas                 text
);

-- Cada materia prima pertenece a lo más a un grupo.
alter table materias_primas add column grupo_almacen_id bigint references grupos_almacen (id);

select aplicar_seguridad('grupos_almacen', 'catalogos');

-- Ocupación por grupo, para el resumen de la planta.
create or replace view v_capacidad_planta with (security_invoker = true) as
select g.id, g.nombre, g.orden,
       g.capacidad_planta_kg, g.capacidad_tolvas_kg,
       g.capacidad_planta_kg + g.capacidad_tolvas_kg as capacidad_total_kg,
       coalesce(sum(s.existencia_kg), 0) as existencia_kg,
       case when g.capacidad_planta_kg + g.capacidad_tolvas_kg > 0
            then round(100 * coalesce(sum(s.existencia_kg), 0) / (g.capacidad_planta_kg + g.capacidad_tolvas_kg), 1)
       end as ocupacion_pct,
       g.capacidad_planta_kg + g.capacidad_tolvas_kg - coalesce(sum(s.existencia_kg), 0) as espacio_libre_kg,
       string_agg(mp.nombre, ', ' order by mp.nombre) as materias,
       g.notas
from grupos_almacen g
left join materias_primas mp on mp.grupo_almacen_id = g.id and mp.activa
left join saldos_mp s on s.materia_prima_id = mp.id
group by g.id;

-- ---------- Datos de la tabla de capacidades ----------

insert into materias_primas (nombre, categoria) values ('CÁSCARA DE SOYA', 'ingrediente')
on conflict (nombre) do nothing;

insert into grupos_almacen (nombre, capacidad_planta_kg, capacidad_tolvas_kg, orden, notas) values
  ('Sorgo y maíz',       6150000, 20000, 1, 'Zona roja 4,800 t (sorgo o maíz) + zona amarilla 1,350 t (solo maíz). El sorgo solo cabe en la zona roja.'),
  ('Soya',               1000000, 60000, 2, null),
  ('Calcio molido',        20000, 25000, 3, null),
  ('Calcio entero',        20000, 25000, 4, 'Calcio quebrado / granulado.'),
  ('Salvado o cáscara',    35000, 28000, 5, 'Salvado y/o cáscara de soya.'),
  ('Ortofosfato',          40000,     0, 6, null);

update materias_primas mp set grupo_almacen_id = g.id
from (values
  ('SORGO', 'Sorgo y maíz'), ('MAIZ', 'Sorgo y maíz'),
  ('PASTA DE SOYA', 'Soya'),
  ('CALCIO MOLIDO', 'Calcio molido'),
  ('CALCIO QUEBRADO / GRANULADO', 'Calcio entero'),
  ('SALVADO', 'Salvado o cáscara'), ('CÁSCARA DE SOYA', 'Salvado o cáscara'),
  ('ORTOFOSFATO', 'Ortofosfato')
) as x (materia, grupo)
join grupos_almacen g on g.nombre = x.grupo
where mp.nombre = x.materia;

-- >>>>>>>>>> migrations/0004_pantallas_planta.sql
-- =====================================================================
-- 0004_pantallas_planta.sql — Lo que necesitan las primeras pantallas
--   * Historial de llegadas con nombres (materia, proveedor, quién capturó)
--   * Capturistas de planta y finanzas pueden dar de alta proveedores
--   * Administración de usuarios desde la plataforma
--   * Actualización en vivo del historial de llegadas
-- =====================================================================

-- Proveedores: los dan de alta también planta y finanzas (al capturar una llegada o una compra).
create policy capturar_operacion on proveedores for insert to authenticated
  with check (puede_capturar('planta') or puede_capturar('finanzas'));

-- Historial de llegadas con nombres.
create or replace view v_llegadas with (security_invoker = true) as
select l.id, l.fecha, l.kg_bruto, l.kg_tara, l.kg_neto, l.humedad_pct, l.precio_kg, l.total,
       l.factura, l.boleta, l.notas, l.capturado_en,
       l.materia_prima_id, mp.nombre as materia_prima,
       l.proveedor_id, pr.nombre as proveedor,
       l.bodega_id, b.nombre as bodega,
       pf.nombre as capturado_por
from llegadas_mp l
join materias_primas mp on mp.id = l.materia_prima_id
left join proveedores pr on pr.id = l.proveedor_id
left join bodegas b on b.id = l.bodega_id
left join perfiles pf on pf.id = l.capturado_por;

-- ---------- Administración de usuarios ----------
-- El usuario se crea primero en Supabase → Authentication → Users (correo y contraseña);
-- después el administrador le asigna nombre, rol y módulos desde la plataforma.

create or replace function guardar_perfil(p_email text, p_nombre text, p_rol rol_usuario, p_modulos text[], p_activo boolean default true)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not es_admin() then
    raise exception 'Solo el administrador puede dar de alta usuarios';
  end if;
  select id into v_id from auth.users where lower(email) = lower(trim(p_email));
  if v_id is null then
    raise exception 'No existe el correo %. Primero créalo en Supabase → Authentication → Users', p_email;
  end if;
  if v_id = auth.uid() and (p_rol <> 'administrador' or not p_activo) then
    raise exception 'No puedes quitarte a ti mismo el rol de administrador';
  end if;
  insert into perfiles (id, nombre, rol, activo) values (v_id, trim(p_nombre), p_rol, p_activo)
  on conflict (id) do update set nombre = excluded.nombre, rol = excluded.rol, activo = excluded.activo;
  delete from perfil_modulos where perfil_id = v_id;
  insert into perfil_modulos (perfil_id, modulo)
  select v_id, m from unnest(coalesce(p_modulos, '{}')) as m
  where m in (select codigo from modulos);
  return v_id;
end $$;

create or replace function listar_usuarios()
returns table (id uuid, email text, nombre text, rol rol_usuario, activo boolean, modulos text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not es_admin() then
    raise exception 'Solo el administrador puede ver los usuarios';
  end if;
  return query
    select p.id, u.email::text, p.nombre, p.rol, p.activo,
           coalesce(array_agg(pm.modulo order by pm.modulo) filter (where pm.modulo is not null), '{}')
    from perfiles p
    join auth.users u on u.id = p.id
    left join perfil_modulos pm on pm.perfil_id = p.id
    group by p.id, u.email
    order by p.nombre;
end $$;

-- Mis datos y permisos (para armar el menú).
create or replace function mi_perfil()
returns table (id uuid, nombre text, rol rol_usuario, activo boolean, modulos text[])
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, p.rol, p.activo,
         case when p.rol = 'administrador' then array(select codigo from modulos order by orden)
              else coalesce(array_agg(pm.modulo) filter (where pm.modulo is not null), '{}') end
  from perfiles p
  left join perfil_modulos pm on pm.perfil_id = p.id
  where p.id = auth.uid()
  group by p.id;
$$;

revoke execute on function guardar_perfil(text, text, rol_usuario, text[], boolean) from anon;
revoke execute on function listar_usuarios() from anon;
revoke execute on function mi_perfil() from anon;

-- ---------- En vivo ----------
-- Cuando alguien captura una llegada, las pantallas abiertas se actualizan solas.
alter publication supabase_realtime add table llegadas_mp;

-- >>>>>>>>>> migrations/0005_inventario_fisico.sql
-- =====================================================================
-- 0005_inventario_fisico.sql — Inventario de arranque y conteo físico semanal
--
--   Inventario de arranque: kg y costo de cada materia prima el día que empieza la plataforma.
--     Entra al kárdex como movimiento 'inicial' (cuenta para el costo promedio, igual que una llegada).
--   Conteo físico: se compara contra el sistema y la diferencia se registra como ajuste.
-- =====================================================================

-- Precio de referencia (septiembre 2026, archivo de costo de alimento) para sugerir el costo del arranque.
alter table materias_primas add column precio_referencia numeric(12,4);

update materias_primas mp set precio_referencia = x.precio
from (values
  ('SORGO', 5.1),
  ('MAIZ', 5.04),
  ('PASTA DE SOYA', 6.34),
  ('SALVADO', 3.7),
  ('LIPOFEED', 2.3),
  ('SAL', 0.44),
  ('CALCIO MOLIDO', 0.7),
  ('CALCIO QUEBRADO / GRANULADO', 0.7),
  ('ORTOFOSFATO', 25.16),
  ('CARBONATO', 0.37),
  ('NÚCLEO AMARILLO (VITAMINA PV)', 78.57),
  ('METIONINA', 36.21),
  ('LISINA', 33.11),
  ('TREONINA', 29.35),
  ('VALINA', 57.9),
  ('ISOLEUCINA', 80.43),
  ('TRIPTÓFANO', 118.43),
  ('BIOCOLINA', 146),
  ('LIQUITRACE', 134),
  ('NÚCLEO CRECIMIENTO NX', 49.98),
  ('NÚCLEO DESARROLLO NX', 57.23),
  ('NÚCLEO FINALIZADOR NX', 52.89),
  ('NÚCLEO GESTACIÓN NX', 55.82),
  ('NÚCLEO INICIADOR REFORZADO NX', 62.03),
  ('NÚCLEO LACTANCIA NX', 65.49),
  ('NÚCLEO REEMPLAZOS 1 NX', 49.84),
  ('NÚCLEO REEMPLAZOS 2 NX', 49.84),
  ('NÚCLEO REEMPLAZOS 3 NX', 54.51),
  ('NÚCLEO CRECIMIENTO SMC', 36.5),
  ('NÚCLEO DESARROLLO SMC', 33),
  ('NÚCLEO FINALIZADOR SMC', 44),
  ('NÚCLEO INICIADOR SMC', 40),
  ('NÚCLEO PREINICIADOR 2-3', 35),
  ('NÚCLEO SMC GESTACIÓN', 22),
  ('NÚCLEO SMC LACTANCIA', 36.5),
  ('NÚCLEO INICIADOR MNA', 6.6),
  ('NÚCLEO MNA DESARROLLO GANADO', 17.19),
  ('NÚCLEO MNA FINALIZADOR GANADO', 16.15),
  ('NÚCLEO MNA BORREGOS ENGORDA', 15.24),
  ('POWER FEED UNO- CHURRO FASE 1', 21),
  ('POWER FEED DOS- CHURRO FASE 2', 16),
  ('POWER FEED TRES- CHURRO FASE 3', 13.75),
  ('Linco-Zoo 11%', 149.08),
  ('Eco-Mutin CTC', 99.08),
  ('Myco-Ad ZT', 210.47),
  ('Bz Farm', 100),
  ('Fosfomicina', 510),
  ('Dysguard-S', 180),
  ('Tylosin 22%', 220.04),
  ('Zytra PM', 96.95),
  ('AM80', 1190),
  ('TM40', 1108.4),
  ('Eco-Flor 4%', 39.48),
  ('Eco-Flor Plus / premix', 144.12),
  ('Flor FC', 144.12),
  ('Colistina', 100),
  ('Neumoenter', 176.31),
  ('Elan C-12', 137.53),
  ('Certyl', 695),
  ('Suramox', 6.72),
  ('Liquitrace', 134),
  ('Saborizante', 33.38),
  ('Ivermix / desparasitante', 92),
  ('Aflorax Maxx', 26),
  ('Toxad Plus', 20),
  ('Oxitetraciclina', 35),
  ('Terradina', 26)
) as x (nombre, precio)
where mp.nombre = x.nombre;

create table inventario_inicial (
  materia_prima_id  bigint primary key references materias_primas (id),
  fecha             date not null,
  kg                numeric(14,2) not null check (kg >= 0),
  costo_kg          numeric(12,4) not null check (costo_kg >= 0),
  capturado_por     uuid references auth.users (id),
  capturado_en      timestamptz,
  modificado_en     timestamptz
);
create trigger captura before insert or update on inventario_inicial for each row execute function marcar_captura();
select aplicar_seguridad('inventario_inicial', 'planta');

-- El kárdex acepta el tipo 'inicial'.
alter table movimientos_mp drop constraint movimientos_mp_tipo_check;
alter table movimientos_mp add constraint movimientos_mp_tipo_check
  check (tipo in ('inicial', 'llegada', 'consumo', 'ajuste'));

-- Mismo cálculo que en 0002, ahora con el inventario inicial como primera entrada.
create or replace function recalcular_mp(p_mp bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  r      record;
  v_ex   numeric := 0;
  v_cost numeric := 0;
begin
  for r in
    select * from movimientos_mp where materia_prima_id = p_mp
    order by fecha, case tipo when 'inicial' then 0 when 'llegada' then 1 when 'ajuste' then 2 else 3 end, id
  loop
    if r.tipo in ('inicial', 'llegada') then
      if v_ex > 0 and v_ex + r.kg > 0 then
        v_cost := (v_ex * v_cost + r.kg * r.precio_kg) / (v_ex + r.kg);
      else
        v_cost := r.precio_kg;
      end if;
    end if;
    v_ex := v_ex + r.kg;
    update movimientos_mp
      set costo_kg = round(v_cost, 4), existencia_despues = round(v_ex, 4)
      where id = r.id;
  end loop;

  insert into saldos_mp (materia_prima_id, existencia_kg, costo_promedio, actualizado_en)
  values (p_mp, round(v_ex, 4), round(v_cost, 4), now())
  on conflict (materia_prima_id) do update
    set existencia_kg = excluded.existencia_kg,
        costo_promedio = excluded.costo_promedio,
        actualizado_en = now();
end $$;

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
    insert into movimientos_mp (fecha, materia_prima_id, bodega_id, tipo, kg, origen, origen_id)
    select o.fecha, fi.materia_prima_id, mp.bodega_id, 'consumo',
           -(fi.kg_por_tonelada * o.kg_producidos / 1000), 'orden', o.id
    from ordenes_produccion o
    join formula_ingredientes fi on fi.formula_id = o.formula_id
    join materias_primas mp on mp.id = fi.materia_prima_id
    where o.id = p_id
    union all
    select o.fecha, om.materia_prima_id, mp.bodega_id, 'consumo',
           -(om.kg_por_tonelada * o.kg_producidos / 1000), 'orden', o.id
    from ordenes_produccion o
    join orden_medicacion om on om.orden_id = o.id
    join materias_primas mp on mp.id = om.materia_prima_id
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

create or replace function trg_sync_inicial() returns trigger language plpgsql as $$
begin
  perform sincronizar_movimientos('inicial', coalesce(new.materia_prima_id, old.materia_prima_id));
  return null;
end $$;
create trigger sync_mov after insert or update or delete on inventario_inicial
  for each row execute function trg_sync_inicial();

-- ---------- Guardado en un solo paso (todo o nada) ----------
-- p_items = [{"materia_prima_id": 1, "kg": 1000, "costo_kg": 5.1}, …]
-- Corre con los permisos de quien llama: necesita permiso de Planta.
create or replace function guardar_inventario_inicial(p_fecha date, p_items jsonb) returns int
language plpgsql as $$
declare n int;
begin
  insert into inventario_inicial (materia_prima_id, fecha, kg, costo_kg)
  select (x->>'materia_prima_id')::bigint, p_fecha, (x->>'kg')::numeric, coalesce((x->>'costo_kg')::numeric, 0)
  from jsonb_array_elements(p_items) as x
  on conflict (materia_prima_id) do update
    set fecha = excluded.fecha, kg = excluded.kg, costo_kg = excluded.costo_kg;
  get diagnostics n = row_count;
  return n;
end $$;

-- p_items = [{"materia_prima_id": 1, "kg_fisicos": 980}, …]
-- Guarda el conteo y, si no coincide con el sistema, registra el ajuste por la diferencia.
create or replace function registrar_conteo(p_fecha date, p_items jsonb) returns table (materia text, kg_sistema numeric, kg_fisicos numeric, diferencia numeric)
language plpgsql as $$
declare
  x jsonb;
  c conteos_mp;
begin
  for x in select * from jsonb_array_elements(p_items) loop
    insert into conteos_mp (fecha, materia_prima_id, kg_fisicos)
    values (p_fecha, (x->>'materia_prima_id')::bigint, (x->>'kg_fisicos')::numeric)
    returning * into c;
    if round(c.kg_fisicos - c.kg_sistema, 2) <> 0 then
      insert into ajustes_mp (fecha, materia_prima_id, kg, motivo)
      values (p_fecha, c.materia_prima_id, round(c.kg_fisicos - c.kg_sistema, 2), 'Conteo físico del ' || to_char(p_fecha, 'DD/MM/YYYY'));
    end if;
    materia := (select nombre from materias_primas where id = c.materia_prima_id);
    kg_sistema := c.kg_sistema; kg_fisicos := c.kg_fisicos; diferencia := round(c.kg_fisicos - c.kg_sistema, 2);
    return next;
  end loop;
end $$;

revoke execute on function guardar_inventario_inicial(date, jsonb) from anon;
revoke execute on function registrar_conteo(date, jsonb) from anon;

-- Historial de conteos.
create or replace view v_conteos with (security_invoker = true) as
select c.id, c.fecha, mp.nombre as materia_prima, c.kg_sistema, c.kg_fisicos,
       round(c.kg_fisicos - c.kg_sistema, 2) as diferencia, pf.nombre as capturado_por, c.capturado_en
from conteos_mp c
join materias_primas mp on mp.id = c.materia_prima_id
left join perfiles pf on pf.id = c.capturado_por;

-- Existencias con el id (para capturar el conteo) y precio de referencia.
create or replace view v_existencias_mp with (security_invoker = true) as
select mp.id, mp.nombre, mp.categoria, b.nombre as bodega,
       coalesce(s.existencia_kg, 0) as existencia_kg,
       coalesce(s.costo_promedio, 0) as costo_promedio,
       round(coalesce(s.existencia_kg, 0) * coalesce(s.costo_promedio, 0), 2) as valor_inventario,
       mp.stock_minimo_kg,
       (mp.stock_minimo_kg is not null and coalesce(s.existencia_kg, 0) < mp.stock_minimo_kg) as bajo_minimo,
       mp.precio_referencia,
       ga.nombre as grupo_almacen
from materias_primas mp
left join saldos_mp s on s.materia_prima_id = mp.id
left join bodegas b on b.id = mp.bodega_id
left join grupos_almacen ga on ga.id = mp.grupo_almacen_id
where mp.activa;

-- >>>>>>>>>> migrations/0006_ordenes_produccion.sql
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


-- >>>>>>>>>> migrations/0007_contratos_granos.sql
-- =====================================================================
-- 0007_contratos_granos.sql — Contratos de materia prima y su corte con las llegadas
--
--   * Contrato: proveedor, materia prima, kg contratados, precio (MXN o USD), vigencia.
--   * Cada llegada puede ligarse a un contrato; lo surtido = suma de sus llegadas.
--   * Materias que requieren contrato (sorgo, maíz, pasta de soya): alerta si no hay contrato abierto
--     y cobertura en días según el consumo de los últimos 30 días.
-- =====================================================================

create table contratos_mp (
  id                bigint generated always as identity primary key,
  folio             text,
  proveedor_id      bigint not null references proveedores (id),
  materia_prima_id  bigint not null references materias_primas (id),
  fecha             date not null default current_date,           -- fecha en que se cerró el contrato
  kg_contratados    numeric(14,2) not null check (kg_contratados > 0),
  moneda            text not null default 'MXN' check (moneda in ('MXN', 'USD')),
  precio            numeric(12,4) not null check (precio >= 0),    -- por kg, en la moneda del contrato, con flete si aplica
  fecha_inicio      date,                                          -- desde cuándo se puede surtir
  fecha_fin         date,                                          -- fecha límite de entrega
  estado            text not null default 'abierto' check (estado in ('abierto', 'cerrado', 'cancelado')),
  notas             text,
  capturado_por     uuid references auth.users (id),
  capturado_en      timestamptz,
  modificado_en     timestamptz,
  check (fecha_fin is null or fecha_inicio is null or fecha_fin >= fecha_inicio)
);
create trigger captura before insert or update on contratos_mp for each row execute function marcar_captura();
select aplicar_seguridad('contratos_mp', 'planta');
-- Finanzas también puede capturar y editar contratos.
create policy capturar_finanzas on contratos_mp for insert to authenticated with check (puede_capturar('finanzas'));
create policy editar_finanzas on contratos_mp for update to authenticated
  using (puede_capturar('finanzas')) with check (puede_capturar('finanzas'));

alter table llegadas_mp add column contrato_id bigint references contratos_mp (id);
alter table llegadas_mp add column tipo_cambio numeric(10,4) check (tipo_cambio > 0);   -- si el contrato es en USD
create index on llegadas_mp (contrato_id);

-- La llegada debe ser de la misma materia prima que su contrato, y el contrato no puede estar cancelado.
create or replace function trg_validar_contrato_llegada() returns trigger language plpgsql as $$
declare c record;
begin
  if new.contrato_id is null then return new; end if;
  select materia_prima_id, estado into c from contratos_mp where id = new.contrato_id;
  if c.materia_prima_id is distinct from new.materia_prima_id then
    raise exception 'El contrato es de otra materia prima';
  end if;
  if c.estado = 'cancelado' then
    raise exception 'El contrato está cancelado';
  end if;
  return new;
end $$;
create trigger validar_contrato before insert or update on llegadas_mp
  for each row execute function trg_validar_contrato_llegada();

-- Materias primas que deben tener contrato vigente.
alter table materias_primas add column requiere_contrato boolean not null default false;
update materias_primas set requiere_contrato = true where nombre in ('SORGO', 'MAIZ', 'PASTA DE SOYA');

-- ---------- Corte de contratos ----------
create or replace view v_contratos with (security_invoker = true) as
select c.id, c.folio, c.fecha, c.proveedor_id, pr.nombre as proveedor, c.materia_prima_id, mp.nombre as materia_prima,
       c.kg_contratados, c.moneda, c.precio, c.fecha_inicio, c.fecha_fin, c.estado, c.notas,
       coalesce(s.kg, 0) as kg_surtidos,
       greatest(c.kg_contratados - coalesce(s.kg, 0), 0) as kg_pendientes,
       round(100 * coalesce(s.kg, 0) / c.kg_contratados, 1) as pct_surtido,
       coalesce(s.n, 0) as llegadas, s.ultima as ultima_llegada,
       case when c.estado <> 'abierto' then c.estado
            when coalesce(s.kg, 0) >= c.kg_contratados then 'surtido'
            when c.fecha_fin < current_date then 'vencido'
            else 'abierto' end as estado_actual,
       c.fecha_fin - current_date as dias_para_vencer,
       pf.nombre as capturado_por
from contratos_mp c
join proveedores pr on pr.id = c.proveedor_id
join materias_primas mp on mp.id = c.materia_prima_id
left join perfiles pf on pf.id = c.capturado_por
left join lateral (
  select sum(l.kg_neto) as kg, count(*) as n, max(l.fecha) as ultima
  from llegadas_mp l where l.contrato_id = c.id
) s on true;

-- ---------- Cobertura de las materias que requieren contrato ----------
create or replace view v_cobertura_mp with (security_invoker = true) as
with consumo as (
  select materia_prima_id, sum(-kg) / 30.0 as kg_dia
  from movimientos_mp
  where tipo = 'consumo' and fecha > current_date - 30
  group by materia_prima_id
), pendiente as (
  select materia_prima_id, sum(kg_pendientes) as kg, count(*) as contratos
  from v_contratos where estado_actual = 'abierto'
  group by materia_prima_id
)
select mp.id, mp.nombre,
       coalesce(s.existencia_kg, 0) as existencia_kg,
       coalesce(p.kg, 0) as kg_contratados_pendientes,
       coalesce(p.contratos, 0) as contratos_abiertos,
       round(coalesce(c.kg_dia, 0), 2) as consumo_kg_dia,
       case when c.kg_dia > 0 then greatest(0, floor(coalesce(s.existencia_kg, 0) / c.kg_dia)) end as dias_existencia,
       case when c.kg_dia > 0 then greatest(0, floor((greatest(coalesce(s.existencia_kg, 0), 0) + coalesce(p.kg, 0)) / c.kg_dia)) end as dias_cobertura
from materias_primas mp
left join saldos_mp s on s.materia_prima_id = mp.id
left join consumo c on c.materia_prima_id = mp.id
left join pendiente p on p.materia_prima_id = mp.id
where mp.requiere_contrato and mp.activa;

-- Historial de llegadas con su contrato (columnas nuevas al final).
create or replace view v_llegadas with (security_invoker = true) as
select l.id, l.fecha, l.kg_bruto, l.kg_tara, l.kg_neto, l.humedad_pct, l.precio_kg, l.total,
       l.factura, l.boleta, l.notas, l.capturado_en,
       l.materia_prima_id, mp.nombre as materia_prima,
       l.proveedor_id, pr.nombre as proveedor,
       l.bodega_id, b.nombre as bodega,
       pf.nombre as capturado_por,
       l.contrato_id, coalesce(c.folio, '#' || c.id) as contrato, l.tipo_cambio
from llegadas_mp l
join materias_primas mp on mp.id = l.materia_prima_id
left join proveedores pr on pr.id = l.proveedor_id
left join bodegas b on b.id = l.bodega_id
left join perfiles pf on pf.id = l.capturado_por
left join contratos_mp c on c.id = l.contrato_id;

alter publication supabase_realtime add table contratos_mp;

-- >>>>>>>>>> migrations/0008_orden_granja_destino.sql
-- =====================================================================
-- 0008_orden_granja_destino.sql — Granja a la que va cada orden de producción
--   Mientras no estén las salidas a granja por caseta, la orden indica la granja destino.
--   Opcional: una orden puede quedar sin granja (por ejemplo, producción para inventario).
-- =====================================================================

alter table ordenes_produccion add column granja_id bigint references granjas (id);
create index on ordenes_produccion (granja_id);

-- Se reemplaza guardar_orden() con el parámetro nuevo p_granja_id (al final, opcional).
drop function guardar_orden(date, bigint, numeric, jsonb, jsonb, text, boolean, bigint);

create or replace function guardar_orden(
  p_fecha date, p_formula_id bigint, p_kg numeric,
  p_ingredientes jsonb default '[]', p_extras jsonb default '[]',
  p_notas text default null, p_actualizar_formula boolean default false, p_orden_id bigint default null,
  p_granja_id bigint default null
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
    insert into ordenes_produccion (fecha, formula_id, kg_producidos, notas, formula_modificada, granja_id)
    values (p_fecha, p_formula_id, p_kg, nullif(trim(p_notas), ''), v_mod and not p_actualizar_formula, p_granja_id)
    returning id into v_id;
  else
    update ordenes_produccion
      set fecha = p_fecha, formula_id = p_formula_id, kg_producidos = p_kg,
          notas = nullif(trim(p_notas), ''), formula_modificada = v_mod and not p_actualizar_formula,
          granja_id = p_granja_id
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

revoke execute on function guardar_orden(date, bigint, numeric, jsonb, jsonb, text, boolean, bigint, bigint) from anon;

-- Órdenes con su granja destino (columnas nuevas al final).
create or replace view v_ordenes with (security_invoker = true) as
select o.id, o.fecha, o.formula_id, f.nombre as formula, f.especie, o.kg_producidos, o.notas,
       o.formula_modificada,
       (select count(*) from orden_extras e where e.orden_id = o.id) as extras,
       coalesce(c.costo_mp, 0) as costo_mp,
       case when o.kg_producidos > 0 then round(coalesce(c.costo_mp, 0) / o.kg_producidos, 4) end as costo_kg,
       pf.nombre as capturado_por, o.capturado_en,
       o.granja_id, g.nombre as granja
from ordenes_produccion o
join formulas f on f.id = o.formula_id
left join granjas g on g.id = o.granja_id
left join perfiles pf on pf.id = o.capturado_por
left join lateral (
  select round(sum(-m.kg * m.costo_kg), 2) as costo_mp
  from movimientos_mp m where m.origen = 'orden' and m.origen_id = o.id
) c on true;

-- Producción por granja destino y fórmula, por día.
create or replace view v_produccion_granja with (security_invoker = true) as
select o.fecha, coalesce(g.nombre, 'Sin granja') as granja, f.nombre as formula, f.especie,
       count(*) as ordenes, sum(o.kg_producidos) as kg
from ordenes_produccion o
join formulas f on f.id = o.formula_id
left join granjas g on g.id = o.granja_id
group by o.fecha, g.nombre, f.nombre, f.especie;

-- >>>>>>>>>> migrations/0009_orden_area.sql
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

-- >>>>>>>>>> migrations/0010_pesada_real.sql
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

-- >>>>>>>>>> migrations/0011_casetas_secciones.sql
-- =====================================================================
-- 0011_casetas_secciones.sql — Casetas con sección, unidad de capacidad y notas
--   Rodadero y San Pablo repiten "Caseta 1" en varias secciones: la caseta se identifica por
--   granja + área + sección + nombre. La capacidad puede ser en cerdos, camas, corrales, salas,
--   cacheteras, gallinas, borregos, vientres…
-- =====================================================================

alter table casetas add column seccion text;
alter table casetas add column unidad_capacidad text not null default 'animales';
alter table casetas add column notas text;
alter table casetas add column orden int not null default 0;

alter table casetas drop constraint casetas_granja_id_nombre_key;
create unique index casetas_unica on casetas (granja_id, area, coalesce(seccion, ''), nombre);

-- Casetas con sus tolvas, para las pantallas.
create or replace view v_casetas with (security_invoker = true) as
select c.id, c.granja_id, g.nombre as granja, g.activa as granja_activa, c.area, c.seccion, c.nombre, c.uso,
       c.capacidad_animales as capacidad, c.unidad_capacidad, c.notas, c.activa, c.orden,
       count(t.id) filter (where t.activa) as tolvas,
       coalesce(sum(t.capacidad_kg) filter (where t.activa), 0) as capacidad_tolvas_kg
from casetas c
join granjas g on g.id = c.granja_id
left join tolvas t on t.caseta_id = c.id
group by c.id, g.nombre, g.activa;

-- >>>>>>>>>> migrations/0012_superficie_granjas.sql
-- =====================================================================
-- 0012_superficie_granjas.sql — Superficie y notas por granja (berries se mide en hectáreas)
-- =====================================================================
alter table granjas add column superficie_ha numeric(10,2) check (superficie_ha > 0);
alter table granjas add column notas text;

-- >>>>>>>>>> datos/0001_casetas_tolvas.sql
-- CARGA DE CASETAS Y TOLVAS v3 (19-nov-2026) — generado por scripts/generar_casetas.py desde CAPACIDADES.xlsx.
-- Se puede volver a correr: actualiza casetas y tolvas sin duplicar. No usa tablas auxiliares.

-- 1) Bellavista: arándanos, 10 hectáreas.
insert into granjas (nombre, superficie_ha, notas) values ('Bellavista', 10, 'Arándanos')
on conflict (nombre) do update set superficie_ha = excluded.superficie_ha, notas = excluded.notas;

-- 2) Áreas que faltaban.
insert into granja_areas (granja_id, area, subarea)
select g.id, x.area::area_productiva, x.subarea from (values
  ('Rodadero', 'borregos', null), ('Palenque', 'cerdos', 'sitio2'), ('Palenque', 'cerdos', 'sitio3'),
  ('Bellavista', 'berries', 'arándano')
) as x (granja, area, subarea) join granjas g on g.nombre = x.granja
on conflict do nothing;

-- 3) Casetas y sus tolvas, en una sola instrucción. La capacidad de tolva es la de CADA tolva.
with datos (granja, area, seccion, nombre, uso, capacidad, unidad, tolvas, ton_tolvas, notas, orden) as (values
    ('Ramari', 'cerdos', null, 'Caseta 1', 'engorda', 900, 'cerdos', 1, 10, null, 0),
    ('Ramari', 'cerdos', null, 'Caseta 2', 'engorda', 850, 'cerdos', 1, 10, null, 1),
    ('Ramari', 'cerdos', null, 'Caseta 4', 'engorda', 500, 'cerdos', 1, 7, null, 2),
    ('Ramari', 'cerdos', null, 'Caseta 5', 'engorda', 500, 'cerdos', 1, 7, null, 3),
    ('Ramari', 'cerdos', null, 'Caseta 6', 'engorda', 950, 'cerdos', 1, 10, null, 4),
    ('Ramari', 'cerdos', null, 'Caseta 7', 'engorda', 1100, 'cerdos', 1, 15, null, 5),
    ('Ramari', 'borregos', null, 'Caseta 3', 'engorda', 200, 'borregos', 0, 0, 'A granel, se manda de planta', 6),
    ('Ramari', 'borregos', null, 'Caseta adicional', 'engorda', 150, 'borregos', 0, 0, 'Solo se usa cuando se llena la caseta 3', 7),
    ('Ramari', 'borregos', null, 'Pie de cría', 'pie de cría', 108, 'borregos', 0, 0, '100 vientres y 8 sementales', 8),
    ('Rodadero', 'cerdos', 'Sección 1', 'Caseta 1', 'engorda', 1100, 'cerdos', 1, 15, null, 9),
    ('Rodadero', 'cerdos', 'Sección 1', 'Caseta 2', 'engorda', 1100, 'cerdos', 1, 15, null, 10),
    ('Rodadero', 'cerdos', 'Sección 1', 'Caseta 3', 'engorda', 1100, 'cerdos', 1, 15, null, 11),
    ('Rodadero', 'cerdos', 'Sección 1', 'Caseta 4', 'engorda', 1100, 'cerdos', 1, 15, null, 12),
    ('Rodadero', 'cerdos', 'Sección 1', 'Caseta 5', 'engorda', 1100, 'cerdos', 1, 15, null, 13),
    ('Rodadero', 'cerdos', 'Sección 1', 'Caseta 6', 'engorda', 1100, 'cerdos', 1, 15, null, 14),
    ('Rodadero', 'cerdos', 'Sección 2', 'Caseta 1', 'engorda', 1100, 'cerdos', 1, 15, null, 15),
    ('Rodadero', 'cerdos', 'Sección 2', 'Caseta 2', 'engorda', 1100, 'cerdos', 1, 15, null, 16),
    ('Rodadero', 'cerdos', 'Sección 2', 'Caseta 3', 'engorda', 1100, 'cerdos', 1, 15, null, 17),
    ('Rodadero', 'cerdos', 'Sección 2', 'Caseta 4', 'engorda', 1100, 'cerdos', 1, 15, null, 18),
    ('Rodadero', 'cerdos', 'Sección 2', 'Caseta 5', 'engorda', 1100, 'cerdos', 1, 15, null, 19),
    ('Rodadero', 'cerdos', 'Sección 2', 'Caseta 6', 'engorda', 1100, 'cerdos', 1, 15, null, 20),
    ('Rodadero', 'borregos', null, 'Pie de cría', 'pie de cría', 110, 'borregos', 0, 0, '100 vientres y 10 sementales. Se envía en costales, usualmente viajes de 3 t', 21),
    ('La Red', 'cerdos', null, 'Gestación 1', 'gestación', 620, 'camas', 0, 0, null, 22),
    ('La Red', 'cerdos', null, 'Gestación 2', 'gestación', 612, 'camas', 0, 0, null, 23),
    ('La Red', 'cerdos', null, 'Gestación 3', 'gestación', 616, 'camas', 0, 0, null, 24),
    ('La Red', 'cerdos', null, 'Gestación 4', 'gestación', 744, 'camas', 0, 0, null, 25),
    ('La Red', 'cerdos', null, 'Gestación 5', 'gestación', 744, 'camas', 0, 0, null, 26),
    ('La Red', 'cerdos', null, 'Gestación Mesita 6', 'gestación', 744, 'camas', 0, 0, null, 27),
    ('La Red', 'cerdos', null, 'Reemplazos Chequeo Salas', 'reemplazos', 37, 'corrales', 0, 0, null, 28),
    ('La Red', 'cerdos', null, 'Reemplazos Destete', 'reemplazos', 10, 'salas', 0, 0, null, 29),
    ('La Red', 'cerdos', null, 'Reemplazos Cuarentena', 'reemplazos', 160, 'cacheteras', 0, 0, null, 30),
    ('La Red', 'cerdos', null, 'Destetes 3', 'destete', 1000, 'cerdos', 1, 10, null, 31),
    ('La Red', 'cerdos', null, 'Destetes 4', 'destete', 1000, 'cerdos', 1, 10, null, 32),
    ('La Red', 'cerdos', null, 'Destetes 5', 'destete', 1000, 'cerdos', 1, 10, null, 33),
    ('La Red', 'cerdos', 'Maternidad', 'Sección 2', 'maternidad', 110, 'camas', 0, 0, null, 34),
    ('La Red', 'cerdos', 'Maternidad', 'Sección 3', 'maternidad', 110, 'camas', 0, 0, null, 35),
    ('La Red', 'cerdos', 'Maternidad', 'Sección 4', 'maternidad', 280, 'camas', 0, 0, null, 36),
    ('La Red', 'cerdos', 'Casetas satélite', 'Engorda 1', 'maternidad', 159, 'camas', 0, 0, null, 37),
    ('La Red', 'cerdos', 'Casetas satélite', 'Engorda 2', 'maternidad', 114, 'camas', 0, 0, null, 38),
    ('La Red', 'cerdos', 'Casetas satélite', 'Engorda 6', 'maternidad', 159, 'camas', 0, 0, null, 39),
    ('La Red', 'cerdos', 'Casetas satélite', 'Caseta 7', 'maternidad', 79, 'camas', 0, 0, null, 40),
    ('La Red', 'cerdos', 'Casetas satélite', 'Caseta 8', 'maternidad', 79, 'camas', 0, 0, null, 41),
    ('La Red', 'cerdos', 'Casetas satélite', 'Caseta 9', 'maternidad', 87, 'camas', 0, 0, null, 42),
    ('La Red', 'cerdos', 'Casetas satélite', 'Sección 5 Capilla', 'maternidad', 160, 'camas', 0, 0, null, 43),
    ('La Red', 'aves', null, 'Caseta 1', 'crianza', 100000, 'aves', 2, 18.22, null, 44),
    ('La Red', 'aves', null, 'Caseta 2', 'crianza', 100000, 'aves', 2, 18.22, null, 45),
    ('La Red', 'borregos', null, 'Pie de cría', 'pie de cría', 370, 'borregos', 0, 0, '350 vientres y 20 sementales', 46),
    ('La Red', 'borregos', null, 'Pariciones', 'parición', 10, 'corrales', 0, 0, 'Los corrales se utilizan conforme se presentan los partos; no tiene una capacidad exacta', 47),
    ('La Red', 'borregos', null, 'Engorda', 'engorda', 246, 'borregos', 1, 5, null, 48),
    ('San Pablo', 'cerdos', 'Sección 1', 'Caseta 1', 'engorda', 1100, 'cerdos', 1, 15, null, 49),
    ('San Pablo', 'cerdos', 'Sección 1', 'Caseta 2', 'engorda', 1100, 'cerdos', 1, 15, null, 50),
    ('San Pablo', 'cerdos', 'Sección 1', 'Caseta 3', 'engorda', 1100, 'cerdos', 1, 15, null, 51),
    ('San Pablo', 'cerdos', 'Sección 1', 'Caseta 4', 'engorda', 1100, 'cerdos', 1, 15, null, 52),
    ('San Pablo', 'cerdos', 'Sección 1', 'Caseta 5', 'engorda', 1100, 'cerdos', 1, 15, null, 53),
    ('San Pablo', 'cerdos', 'Sección 1', 'Caseta 6', 'engorda', 1100, 'cerdos', 1, 15, null, 54),
    ('San Pablo', 'cerdos', 'Sección 2', 'Caseta Doble 1', 'engorda', 2200, 'cerdos', 2, 15, null, 55),
    ('San Pablo', 'cerdos', 'Sección 2', 'Caseta Doble 2', 'engorda', 2200, 'cerdos', 2, 15, null, 56),
    ('San Pablo', 'cerdos', 'Sección 2', 'Caseta Doble 3', 'engorda', 2200, 'cerdos', 2, 15, null, 57),
    ('San Pablo', 'cerdos', 'Sección 3', 'Caseta Doble 1', 'engorda', 2200, 'cerdos', 2, 15, null, 58),
    ('San Pablo', 'cerdos', 'Sección 3', 'Caseta Doble 2', 'engorda', 2200, 'cerdos', 2, 15, null, 59),
    ('San Pablo', 'cerdos', 'Sección 3', 'Caseta Doble 3', 'engorda', 2200, 'cerdos', 2, 15, null, 60),
    ('San Pablo', 'cerdos', 'Sección 3', 'Caseta Doble 4', 'engorda', 2200, 'cerdos', 2, 15, null, 61),
    ('San Pablo', 'cerdos', 'Sección 4', 'Caseta 1', 'engorda', 1100, 'cerdos', 1, 15, null, 62),
    ('San Pablo', 'cerdos', 'Sección 4', 'Caseta 2', 'engorda', 1100, 'cerdos', 1, 15, null, 63),
    ('San Pablo', 'cerdos', 'Sección 4', 'Caseta 3', 'engorda', 1100, 'cerdos', 1, 15, null, 64),
    ('San Pablo', 'cerdos', 'Sección 4', 'Caseta 4', 'engorda', 1100, 'cerdos', 1, 15, null, 65),
    ('San Pablo', 'cerdos', 'Sección 4', 'Caseta 5', 'engorda', 1100, 'cerdos', 1, 15, null, 66),
    ('San Pablo', 'cerdos', 'Sección 4', 'Caseta 6', 'engorda', 1100, 'cerdos', 1, 15, null, 67),
    ('Princesita', 'aves', null, 'Caseta 1', 'postura', 20000, 'gallinas', 1, 10, null, 68),
    ('Princesita', 'aves', null, 'Caseta 2', 'postura', 20000, 'gallinas', 1, 10, null, 69),
    ('Princesita', 'aves', null, 'Caseta 3', 'postura', 20000, 'gallinas', 1, 10, null, 70),
    ('Princesita', 'aves', null, 'Caseta 4', 'postura', 20000, 'gallinas', 1, 10, null, 71),
    ('Princesita', 'aves', null, 'Caseta 5', 'postura', 20000, 'gallinas', 1, 10, null, 72),
    ('Princesita', 'aves', null, 'Caseta 6', 'postura', 20000, 'gallinas', 1, 6, null, 73),
    ('Durazno', 'aves', null, 'Caseta 1', 'postura', 17760, 'gallinas', 1, 10, null, 74),
    ('Durazno', 'aves', null, 'Caseta 2', 'postura', 17760, 'gallinas', 1, 10, null, 75),
    ('Durazno', 'aves', null, 'Caseta 3', 'postura', 17760, 'gallinas', 1, 10, null, 76),
    ('Durazno', 'aves', null, 'Caseta 4', 'postura', 17760, 'gallinas', 1, 10, null, 77),
    ('Durazno', 'aves', null, 'Caseta 5', 'postura', 17760, 'gallinas', 1, 10, null, 78),
    ('Durazno', 'aves', null, 'Caseta 6', 'postura', 26640, 'gallinas', 1, 10, null, 79),
    ('Durazno', 'aves', null, 'Caseta 7', 'postura', 17760, 'gallinas', 1, 10, null, 80),
    ('Durazno', 'aves', null, 'Caseta 8', 'postura', 26640, 'gallinas', 1, 12, null, 81),
    ('Durazno', 'aves', null, 'Caseta 9', 'postura', 33300, 'gallinas', 1, 12, null, 82),
    ('Paraíso', 'aves', null, 'Caseta 1', 'postura', 15000, 'gallinas', 1, 12, null, 83),
    ('Paraíso', 'aves', null, 'Caseta 2', 'postura', 15000, 'gallinas', 1, 12, null, 84),
    ('Paraíso', 'aves', null, 'Caseta 3', 'postura', 15000, 'gallinas', 1, 12, null, 85),
    ('Josefino', 'aves', null, 'Caseta 1', 'postura', 100000, 'gallinas', 2, 18.22, null, 86),
    ('Josefino', 'aves', null, 'Caseta 2', 'postura', 100000, 'gallinas', 2, 18.22, null, 87),
    ('La Mesa', 'aves', null, 'Caseta 1', 'postura', 100000, 'gallinas', 2, 18.22, null, 88),
    ('La Mesa', 'aves', null, 'Caseta 2', 'postura', 100000, 'gallinas', 2, 18.22, null, 89),
    ('Palenque', 'cerdos', 'Lactancia', 'Tolva 1', 'maternidad', null, 'animales', 1, 1.5, 'Capacidad de animales pendiente', 90),
    ('Palenque', 'cerdos', 'Lactancia', 'Tolva 2', 'maternidad', null, 'animales', 1, 1.5, 'Capacidad de animales pendiente', 91),
    ('Palenque', 'cerdos', 'Lactancia', 'Tolva 3', 'maternidad', null, 'animales', 1, 1.5, 'Capacidad de animales pendiente', 92),
    ('Palenque', 'cerdos', 'Gestación', 'Tolva 1', 'gestación', null, 'animales', 1, 3, 'Capacidad de animales pendiente', 93),
    ('Palenque', 'cerdos', 'Gestación', 'Tolva 2', 'gestación', null, 'animales', 1, 9, 'Capacidad de animales pendiente', 94),
    ('Palenque', 'cerdos', 'Gestación', 'Tolva 3', 'gestación', null, 'animales', 1, 9, 'Capacidad de animales pendiente', 95),
    ('Palenque', 'cerdos', 'Reemplazo', 'Tolva 1', 'reemplazos', null, 'animales', 1, 6, 'Capacidad de animales pendiente', 96),
    ('Palenque', 'cerdos', 'Reemplazo', 'Tolva 2', 'reemplazos', null, 'animales', 1, 9, 'Capacidad de animales pendiente', 97),
    ('Palenque', 'cerdos', 'Sitio 2-3', 'Tolva 1', 'destete y engorda', null, 'animales', 1, 4, 'Capacidad de animales pendiente', 98),
    ('Palenque', 'cerdos', 'Lactancia-iniciador', 'Tolva 1', 'maternidad', null, 'animales', 1, 10, 'Capacidad de animales pendiente', 99)
),
guardadas as (
  insert into casetas (granja_id, area, seccion, nombre, uso, capacidad_animales, unidad_capacidad, notas, orden)
  select g.id, d.area::area_productiva, d.seccion, d.nombre, d.uso, d.capacidad, d.unidad, d.notas, d.orden
  from datos d join granjas g on g.nombre = d.granja
  on conflict (granja_id, area, coalesce(seccion, ''), nombre) do update
    set uso = excluded.uso, capacidad_animales = excluded.capacidad_animales,
        unidad_capacidad = excluded.unidad_capacidad, notas = excluded.notas, orden = excluded.orden
  returning id, orden
)
insert into tolvas (caseta_id, nombre, capacidad_kg, activa)
select k.id, 'Tolva ' || n, round(d.ton_tolvas * 1000, 2), true
from guardadas k
join datos d on d.orden = k.orden
cross join generate_series(1, d.tolvas) as n
where d.tolvas > 0 and d.ton_tolvas > 0
on conflict (caseta_id, nombre) do update set capacidad_kg = excluded.capacidad_kg, activa = true;

-- 4) Resultado: casetas y tolvas por granja
select g.nombre as granja, k.area, count(distinct k.id) as casetas, count(t.id) as tolvas,
       round(sum(t.capacidad_kg) / 1000, 1) as toneladas_en_tolvas
from casetas k join granjas g on g.id = k.granja_id left join tolvas t on t.caseta_id = k.id and t.activa
group by g.nombre, k.area order by g.nombre, k.area;

-- >>>>>>>>>> migrations/0013_materias_nuevas.sql
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

-- >>>>>>>>>> migrations/0014_formulas_nuevas.sql
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

-- >>>>>>>>>> datos/0002_formulas_maiz.sql
-- FÓRMULAS CON MAÍZ v1 (20-nov-2026) — 8 SMC y 9 NX, transcritas de la hoja "FORMULA DE MATERIAS" (sección MAIZ).
-- Cada fórmula suma 1,000 kg/t. Se puede volver a correr: actualiza las fórmulas y sus ingredientes sin duplicar.
-- Las órdenes ya registradas no cambian (cada orden guarda su propia copia de ingredientes).

-- 1) Núcleo que no existía en el catálogo (SMC Reemplazos 2). Queda por revisar.
insert into materias_primas (nombre, categoria, revisada, creada_en)
values ('NÚCLEO REEMPLAZOS 2 SMC', 'nucleo', false, now())
on conflict (nombre) do nothing;

-- 2) Fórmulas
insert into formulas (nombre, especie, etapa, notas, vigente_desde)
select x.nombre, 'cerdos', x.etapa, x.notas, date '2026-11-20' from (values
  ('SMC PREINICIADOR MAÍZ', 'Preiniciador', 'Código SMC P-200 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC FASE 4 MAÍZ', 'Fase 4', 'Código SMC P-120 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC CRECIMIENTO MAÍZ', 'Crecimiento', 'Código SMC P-121 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC DESARROLLO MAÍZ', 'Desarrollo', 'Código SMC P-122 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC FINALIZADOR MAÍZ', 'Finalizador', 'Código SMC P-125 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC GESTACIÓN MAÍZ', 'Gestación', 'Código SMC P-130 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC LACTANCIA MAÍZ', 'Lactancia', 'Código SMC P-133 A. Fórmula con maíz (20-nov-2026).'),
  ('SMC REEMPLAZOS 2 MAÍZ', 'Reemplazos 2', 'Código SMC P-223 A. Fórmula con maíz (20-nov-2026).'),
  ('NX INICIADOR MAÍZ', 'Iniciador', 'Fórmula con maíz (20-nov-2026).'),
  ('NX CRECIMIENTO MAÍZ', 'Crecimiento', 'Fórmula con maíz (20-nov-2026).'),
  ('NX DESARROLLO MAÍZ', 'Desarrollo', 'Fórmula con maíz (20-nov-2026).'),
  ('NX FINALIZADOR MAÍZ', 'Finalizador', 'Fórmula con maíz (20-nov-2026).'),
  ('NX GESTACIÓN MAÍZ', 'Gestación', 'Fórmula con maíz (20-nov-2026).'),
  ('NX LACTANCIA MAÍZ', 'Lactancia', 'Fórmula con maíz (20-nov-2026).'),
  ('NX REEMPLAZOS 1 MAÍZ', 'Reemplazos 1', 'Fórmula con maíz (20-nov-2026).'),
  ('NX REEMPLAZOS 2 MAÍZ', 'Reemplazos 2', 'Fórmula con maíz (20-nov-2026).'),
  ('NX REEMPLAZOS 3 MAÍZ', 'Reemplazos 3', 'Fórmula con maíz (20-nov-2026).')
) as x (nombre, etapa, notas)
on conflict (nombre) do update set especie = excluded.especie, etapa = excluded.etapa, notas = excluded.notas, activa = true;

-- 3) Ingredientes (kg por tonelada): se reemplazan los de estas fórmulas
delete from formula_ingredientes fi using formulas f
where fi.formula_id = f.id and f.nombre in ('SMC PREINICIADOR MAÍZ', 'SMC FASE 4 MAÍZ', 'SMC CRECIMIENTO MAÍZ', 'SMC DESARROLLO MAÍZ', 'SMC FINALIZADOR MAÍZ', 'SMC GESTACIÓN MAÍZ', 'SMC LACTANCIA MAÍZ', 'SMC REEMPLAZOS 2 MAÍZ', 'NX INICIADOR MAÍZ', 'NX CRECIMIENTO MAÍZ', 'NX DESARROLLO MAÍZ', 'NX FINALIZADOR MAÍZ', 'NX GESTACIÓN MAÍZ', 'NX LACTANCIA MAÍZ', 'NX REEMPLAZOS 1 MAÍZ', 'NX REEMPLAZOS 2 MAÍZ', 'NX REEMPLAZOS 3 MAÍZ');

insert into formula_ingredientes (formula_id, materia_prima_id, kg_por_tonelada)
select f.id, m.id, x.kg from (values
  ('SMC PREINICIADOR MAÍZ', 'NÚCLEO PREINICIADOR 2-3', 175),
  ('SMC PREINICIADOR MAÍZ', 'MAIZ', 559),
  ('SMC PREINICIADOR MAÍZ', 'PASTA DE SOYA', 260),
  ('SMC PREINICIADOR MAÍZ', 'LIPOFEED', 6),
  ('SMC FASE 4 MAÍZ', 'NÚCLEO INICIADOR SMC', 40),
  ('SMC FASE 4 MAÍZ', 'MAIZ', 696),
  ('SMC FASE 4 MAÍZ', 'PASTA DE SOYA', 260),
  ('SMC FASE 4 MAÍZ', 'LIPOFEED', 4),
  ('SMC CRECIMIENTO MAÍZ', 'NÚCLEO CRECIMIENTO SMC', 25),
  ('SMC CRECIMIENTO MAÍZ', 'MAIZ', 764),
  ('SMC CRECIMIENTO MAÍZ', 'PASTA DE SOYA', 210),
  ('SMC CRECIMIENTO MAÍZ', 'LIPOFEED', 1),
  ('SMC DESARROLLO MAÍZ', 'NÚCLEO DESARROLLO SMC', 25),
  ('SMC DESARROLLO MAÍZ', 'MAIZ', 795),
  ('SMC DESARROLLO MAÍZ', 'PASTA DE SOYA', 180),
  ('SMC FINALIZADOR MAÍZ', 'NÚCLEO FINALIZADOR SMC', 25),
  ('SMC FINALIZADOR MAÍZ', 'MAIZ', 739),
  ('SMC FINALIZADOR MAÍZ', 'PASTA DE SOYA', 235),
  ('SMC FINALIZADOR MAÍZ', 'LIPOFEED', 1),
  ('SMC GESTACIÓN MAÍZ', 'NÚCLEO SMC GESTACIÓN', 35),
  ('SMC GESTACIÓN MAÍZ', 'MAIZ', 649),
  ('SMC GESTACIÓN MAÍZ', 'PASTA DE SOYA', 105),
  ('SMC GESTACIÓN MAÍZ', 'LIPOFEED', 1),
  ('SMC GESTACIÓN MAÍZ', 'SALVADO', 210),
  ('SMC LACTANCIA MAÍZ', 'NÚCLEO SMC LACTANCIA', 50),
  ('SMC LACTANCIA MAÍZ', 'MAIZ', 633),
  ('SMC LACTANCIA MAÍZ', 'PASTA DE SOYA', 230),
  ('SMC LACTANCIA MAÍZ', 'LIPOFEED', 7),
  ('SMC LACTANCIA MAÍZ', 'SALVADO', 80),
  ('SMC REEMPLAZOS 2 MAÍZ', 'NÚCLEO REEMPLAZOS 2 SMC', 30),
  ('SMC REEMPLAZOS 2 MAÍZ', 'MAIZ', 643),
  ('SMC REEMPLAZOS 2 MAÍZ', 'PASTA DE SOYA', 175),
  ('SMC REEMPLAZOS 2 MAÍZ', 'LIPOFEED', 2),
  ('SMC REEMPLAZOS 2 MAÍZ', 'SALVADO', 150),
  ('NX INICIADOR MAÍZ', 'NÚCLEO INICIADOR REFORZADO NX', 24),
  ('NX INICIADOR MAÍZ', 'MAIZ', 673),
  ('NX INICIADOR MAÍZ', 'PASTA DE SOYA', 285),
  ('NX INICIADOR MAÍZ', 'LIPOFEED', 4),
  ('NX INICIADOR MAÍZ', 'ORTOFOSFATO', 5),
  ('NX INICIADOR MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 9),
  ('NX CRECIMIENTO MAÍZ', 'NÚCLEO CRECIMIENTO NX', 18),
  ('NX CRECIMIENTO MAÍZ', 'MAIZ', 731),
  ('NX CRECIMIENTO MAÍZ', 'PASTA DE SOYA', 235),
  ('NX CRECIMIENTO MAÍZ', 'LIPOFEED', 2),
  ('NX CRECIMIENTO MAÍZ', 'ORTOFOSFATO', 4),
  ('NX CRECIMIENTO MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 10),
  ('NX DESARROLLO MAÍZ', 'NÚCLEO DESARROLLO NX', 19),
  ('NX DESARROLLO MAÍZ', 'MAIZ', 773),
  ('NX DESARROLLO MAÍZ', 'PASTA DE SOYA', 195),
  ('NX DESARROLLO MAÍZ', 'LIPOFEED', 1),
  ('NX DESARROLLO MAÍZ', 'ORTOFOSFATO', 2),
  ('NX DESARROLLO MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 10),
  ('NX FINALIZADOR MAÍZ', 'NÚCLEO FINALIZADOR NX', 19),
  ('NX FINALIZADOR MAÍZ', 'MAIZ', 728),
  ('NX FINALIZADOR MAÍZ', 'PASTA DE SOYA', 240),
  ('NX FINALIZADOR MAÍZ', 'LIPOFEED', 2),
  ('NX FINALIZADOR MAÍZ', 'ORTOFOSFATO', 2),
  ('NX FINALIZADOR MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 9),
  ('NX GESTACIÓN MAÍZ', 'NÚCLEO GESTACIÓN NX', 10),
  ('NX GESTACIÓN MAÍZ', 'MAIZ', 623),
  ('NX GESTACIÓN MAÍZ', 'PASTA DE SOYA', 150),
  ('NX GESTACIÓN MAÍZ', 'SALVADO', 200),
  ('NX GESTACIÓN MAÍZ', 'ORTOFOSFATO', 6),
  ('NX GESTACIÓN MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 11),
  ('NX LACTANCIA MAÍZ', 'NÚCLEO LACTANCIA NX', 22),
  ('NX LACTANCIA MAÍZ', 'MAIZ', 700),
  ('NX LACTANCIA MAÍZ', 'PASTA DE SOYA', 255),
  ('NX LACTANCIA MAÍZ', 'LIPOFEED', 4),
  ('NX LACTANCIA MAÍZ', 'ORTOFOSFATO', 8),
  ('NX LACTANCIA MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 11),
  ('NX REEMPLAZOS 1 MAÍZ', 'NÚCLEO REEMPLAZOS 1 NX', 15),
  ('NX REEMPLAZOS 1 MAÍZ', 'MAIZ', 733),
  ('NX REEMPLAZOS 1 MAÍZ', 'PASTA DE SOYA', 235),
  ('NX REEMPLAZOS 1 MAÍZ', 'LIPOFEED', 2),
  ('NX REEMPLAZOS 1 MAÍZ', 'ORTOFOSFATO', 5),
  ('NX REEMPLAZOS 1 MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 10),
  ('NX REEMPLAZOS 2 MAÍZ', 'NÚCLEO REEMPLAZOS 2 NX', 15),
  ('NX REEMPLAZOS 2 MAÍZ', 'MAIZ', 806),
  ('NX REEMPLAZOS 2 MAÍZ', 'PASTA DE SOYA', 165),
  ('NX REEMPLAZOS 2 MAÍZ', 'ORTOFOSFATO', 3),
  ('NX REEMPLAZOS 2 MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 11),
  ('NX REEMPLAZOS 3 MAÍZ', 'NÚCLEO REEMPLAZOS 3 NX', 15),
  ('NX REEMPLAZOS 3 MAÍZ', 'MAIZ', 786),
  ('NX REEMPLAZOS 3 MAÍZ', 'PASTA DE SOYA', 125),
  ('NX REEMPLAZOS 3 MAÍZ', 'SALVADO', 60),
  ('NX REEMPLAZOS 3 MAÍZ', 'ORTOFOSFATO', 3),
  ('NX REEMPLAZOS 3 MAÍZ', 'CALCIO QUEBRADO / GRANULADO', 11)
) as x (formula, materia, kg)
join formulas f on f.nombre = x.formula
join materias_primas m on m.nombre = x.materia;

-- 4) Códigos SMC como nombres alternos (para buscar la fórmula por su código)
insert into formula_alias (alias, formula_id)
select x.alias, f.id from (values
  ('P-200 A', 'SMC PREINICIADOR MAÍZ'),
  ('P-120 A', 'SMC FASE 4 MAÍZ'),
  ('P-121 A', 'SMC CRECIMIENTO MAÍZ'),
  ('P-122 A', 'SMC DESARROLLO MAÍZ'),
  ('P-125 A', 'SMC FINALIZADOR MAÍZ'),
  ('P-130 A', 'SMC GESTACIÓN MAÍZ'),
  ('P-133 A', 'SMC LACTANCIA MAÍZ'),
  ('P-223 A', 'SMC REEMPLAZOS 2 MAÍZ')
) as x (alias, formula) join formulas f on f.nombre = x.formula
on conflict (alias) do update set formula_id = excluded.formula_id;

-- 5) Revisión: cada fórmula con su número de ingredientes y su total (debe dar 1,000)
select f.nombre, f.etapa, count(fi.materia_prima_id) as ingredientes, sum(fi.kg_por_tonelada) as total_kg_t
from formulas f left join formula_ingredientes fi on fi.formula_id = f.id
where f.nombre in ('SMC PREINICIADOR MAÍZ', 'SMC FASE 4 MAÍZ', 'SMC CRECIMIENTO MAÍZ', 'SMC DESARROLLO MAÍZ', 'SMC FINALIZADOR MAÍZ', 'SMC GESTACIÓN MAÍZ', 'SMC LACTANCIA MAÍZ', 'SMC REEMPLAZOS 2 MAÍZ', 'NX INICIADOR MAÍZ', 'NX CRECIMIENTO MAÍZ', 'NX DESARROLLO MAÍZ', 'NX FINALIZADOR MAÍZ', 'NX GESTACIÓN MAÍZ', 'NX LACTANCIA MAÍZ', 'NX REEMPLAZOS 1 MAÍZ', 'NX REEMPLAZOS 2 MAÍZ', 'NX REEMPLAZOS 3 MAÍZ')
group by f.nombre, f.etapa order by f.nombre;

-- >>>>>>>>>> migrations/0015_llegadas_pendientes.sql
-- =====================================================================
-- 0015_llegadas_pendientes.sql — Editar llegadas, información pendiente y excedente de contrato
--   * precio_provisional: el precio o el tipo de cambio aún no es el definitivo (no se ha pagado).
--   * Pendientes de una llegada: sin factura, precio provisional.
--   * Excedente de contrato: lo que una llegada rebasó de lo contratado; se registra al precio del contrato.
--   * Quién modificó la llegada.
-- =====================================================================

alter table llegadas_mp add column precio_provisional boolean not null default false;
alter table llegadas_mp add column modificado_por uuid references auth.users (id);

create or replace function trg_modifico_llegada() returns trigger language plpgsql as $$
begin
  new.modificado_por := auth.uid();
  return new;
end $$;
create trigger modifico before update on llegadas_mp for each row execute function trg_modifico_llegada();

-- Historial de llegadas (columnas nuevas al final).
create or replace view v_llegadas with (security_invoker = true) as
select l.id, l.fecha, l.kg_bruto, l.kg_tara, l.kg_neto, l.humedad_pct, l.precio_kg, l.total,
       l.factura, l.boleta, l.notas, l.capturado_en,
       l.materia_prima_id, mp.nombre as materia_prima,
       l.proveedor_id, pr.nombre as proveedor,
       l.bodega_id, b.nombre as bodega,
       pf.nombre as capturado_por,
       l.contrato_id, coalesce(c.folio, '#' || c.id) as contrato, l.tipo_cambio,
       l.precio_provisional, c.moneda as moneda_contrato, c.precio as precio_contrato,
       -- Parte de esta llegada que rebasó lo contratado (diferencial), en orden de fecha
       case when l.contrato_id is null then 0 else
         greatest(0, sum(l.kg_neto) over w - c.kg_contratados) - greatest(0, sum(l.kg_neto) over w - l.kg_neto - c.kg_contratados)
       end as kg_excedente_contrato,
       array_remove(array[
         case when nullif(trim(l.factura), '') is null then 'factura' end,
         case when l.precio_provisional then 'precio' end
       ], null) as pendientes,
       pm.nombre as modificado_por, l.modificado_en
from llegadas_mp l
join materias_primas mp on mp.id = l.materia_prima_id
left join proveedores pr on pr.id = l.proveedor_id
left join bodegas b on b.id = l.bodega_id
left join perfiles pf on pf.id = l.capturado_por
left join contratos_mp c on c.id = l.contrato_id
left join perfiles pm on pm.id = l.modificado_por
window w as (partition by l.contrato_id order by l.fecha, l.id);


-- Contratos con el excedente surtido (columna nueva al final).
create or replace view v_contratos with (security_invoker = true) as
select c.id, c.folio, c.fecha, c.proveedor_id, pr.nombre as proveedor, c.materia_prima_id, mp.nombre as materia_prima,
       c.kg_contratados, c.moneda, c.precio, c.fecha_inicio, c.fecha_fin, c.estado, c.notas,
       coalesce(s.kg, 0) as kg_surtidos,
       greatest(c.kg_contratados - coalesce(s.kg, 0), 0) as kg_pendientes,
       round(100 * coalesce(s.kg, 0) / c.kg_contratados, 1) as pct_surtido,
       coalesce(s.n, 0) as llegadas, s.ultima as ultima_llegada,
       case when c.estado <> 'abierto' then c.estado
            when coalesce(s.kg, 0) >= c.kg_contratados then 'surtido'
            when c.fecha_fin < current_date then 'vencido'
            else 'abierto' end as estado_actual,
       c.fecha_fin - current_date as dias_para_vencer,
       pf.nombre as capturado_por,
       greatest(coalesce(s.kg, 0) - c.kg_contratados, 0) as kg_excedente
from contratos_mp c
join proveedores pr on pr.id = c.proveedor_id
join materias_primas mp on mp.id = c.materia_prima_id
left join perfiles pf on pf.id = c.capturado_por
left join lateral (
  select sum(l.kg_neto) as kg, count(*) as n, max(l.fecha) as ultima
  from llegadas_mp l where l.contrato_id = c.id
) s on true;
;

-- >>>>>>>>>> migrations/0016_folios_unicos.sql
-- =====================================================================
-- 0016_folios_unicos.sql — No se repiten folios de contrato ni boletas de báscula
--   Se compara sin espacios de más ni diferencias de mayúsculas/acentos ("prv-101" = "PRV-101").
--   Se valida al guardar (no rompe si ya hubiera repetidos capturados antes).
-- =====================================================================

create or replace function trg_folio_contrato_unico() returns trigger language plpgsql as $$
declare v_otro bigint;
begin
  if nullif(trim(new.folio), '') is null then new.folio := null; return new; end if;
  new.folio := regexp_replace(upper(trim(new.folio)), '\s+', ' ', 'g');
  select id into v_otro from contratos_mp
  where nombre_normalizado(folio) = nombre_normalizado(new.folio) and id <> coalesce(new.id, -1) limit 1;
  if v_otro is not null then
    raise exception 'El folio de contrato % ya existe. No puede repetirse.', new.folio;
  end if;
  return new;
end $$;
create trigger folio_unico before insert or update of folio on contratos_mp
  for each row execute function trg_folio_contrato_unico();

create or replace function trg_boleta_unica() returns trigger language plpgsql as $$
declare v_otra record;
begin
  if nullif(trim(new.boleta), '') is null then new.boleta := null; return new; end if;
  new.boleta := regexp_replace(upper(trim(new.boleta)), '\s+', ' ', 'g');
  select l.id, l.fecha into v_otra from llegadas_mp l
  where nombre_normalizado(l.boleta) = nombre_normalizado(new.boleta) and l.id <> coalesce(new.id, -1) limit 1;
  if v_otra.id is not null then
    raise exception 'La boleta % ya está registrada en la llegada del %. No puede repetirse.', new.boleta, to_char(v_otra.fecha, 'DD/MM/YYYY');
  end if;
  return new;
end $$;
create trigger boleta_unica before insert or update of boleta on llegadas_mp
  for each row execute function trg_boleta_unica();

-- Para avisar en pantalla antes de guardar.
create index on contratos_mp (nombre_normalizado(folio));
create index on llegadas_mp (nombre_normalizado(boleta));
create index on llegadas_mp (nombre_normalizado(factura));

-- >>>>>>>>>> migrations/0017_pesadas_y_notas.sql
-- =====================================================================
-- 0017_pesadas_y_notas.sql — Varios alimentos en una pesada; varios productos en una nota de entrada
--
--   Pesada conjunta: varias órdenes (cada una con su fórmula y kg ordenados) se cargan y pesan juntas.
--     El total de la báscula se reparte en proporción a lo ordenado de cada una:
--     kg reales de la orden = kg ordenados × total pesado ÷ total ordenado.
--   Nota de entrada: una nota con varios productos (encostalados). Cada producto es una llegada propia
--     (aparece individual en el historial), ligada a la nota. Se usan los pesos de la nota; el total de
--     báscula es opcional (para comparar, o para ajustar en proporción si así se pide).
-- =====================================================================

-- ---------- Pesada conjunta de órdenes ----------
create table pesadas_conjuntas (
  id             bigint generated always as identity primary key,
  fecha          date not null default current_date,
  kg_total       numeric(14,2) not null check (kg_total > 0),
  notas          text,
  capturado_por  uuid references auth.users (id),
  capturado_en   timestamptz,
  modificado_en  timestamptz
);
create trigger captura before insert or update on pesadas_conjuntas for each row execute function marcar_captura();
select aplicar_seguridad('pesadas_conjuntas', 'planta');

alter table ordenes_produccion add column pesada_conjunta_id bigint references pesadas_conjuntas (id) on delete set null;

-- Registra (o corrige, con p_pesada_id) una pesada de varias órdenes y reparte el total.
create or replace function registrar_pesada_conjunta(
  p_orden_ids bigint[], p_kg_total numeric, p_pesada_id bigint default null, p_notas text default null
) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_sol numeric;
  v_n int;
  v_asignado numeric := 0;
  r record;
  i int := 0;
  v_kg numeric;
begin
  if coalesce(array_length(p_orden_ids, 1), 0) < 2 then raise exception 'Elige al menos dos órdenes para una pesada conjunta'; end if;
  if coalesce(p_kg_total, 0) <= 0 then raise exception 'El total de la pesada debe ser mayor a cero'; end if;
  select count(*), sum(kg_solicitados) into v_n, v_sol from ordenes_produccion where id = any(p_orden_ids);
  if v_n <> array_length(p_orden_ids, 1) then raise exception 'Alguna orden no existe o no tienes permiso para verla'; end if;

  if p_pesada_id is null then
    insert into pesadas_conjuntas (fecha, kg_total, notas)
    select max(fecha), p_kg_total, nullif(trim(p_notas), '') from ordenes_produccion where id = any(p_orden_ids)
    returning id into v_id;
  else
    update pesadas_conjuntas set kg_total = p_kg_total, notas = coalesce(nullif(trim(p_notas), ''), notas)
    where id = p_pesada_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró la pesada %', p_pesada_id; end if;
    -- Órdenes que salieron de la pesada: quedan pendientes de pesada.
    update ordenes_produccion set pesada_conjunta_id = null, kg_reales = null
    where pesada_conjunta_id = v_id and not (id = any(p_orden_ids));
  end if;

  -- Reparto proporcional; la última orden absorbe el redondeo para que la suma sea exacta.
  for r in select id, kg_solicitados from ordenes_produccion where id = any(p_orden_ids) order by id loop
    i := i + 1;
    v_kg := case when i = v_n then p_kg_total - v_asignado
                 else round(r.kg_solicitados * p_kg_total / v_sol, 2) end;
    v_asignado := v_asignado + v_kg;
    update ordenes_produccion set kg_reales = v_kg, pesada_conjunta_id = v_id where id = r.id;
  end loop;
  return v_id;
end $$;
revoke execute on function registrar_pesada_conjunta(bigint[], numeric, bigint, text) from anon;

-- Pesada individual: si la orden estaba en una pesada conjunta, sale de ella.
create or replace function registrar_pesada(p_orden_id bigint, p_kg_reales numeric) returns void
language plpgsql as $$
begin
  if p_kg_reales is not null and p_kg_reales <= 0 then raise exception 'Los kg reales deben ser mayores a cero'; end if;
  update ordenes_produccion set kg_reales = p_kg_reales, pesada_conjunta_id = null where id = p_orden_id;
  if not found then raise exception 'No se encontró la orden % o no tienes permiso para cambiarla', p_orden_id; end if;
end $$;

-- Órdenes con su pesada conjunta (columnas nuevas al final).
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
       pm.nombre as modificado_por, o.modificado_en,
       o.pesada_conjunta_id, pc.kg_total as pesada_kg_total,
       (select count(*) from ordenes_produccion o2 where o2.pesada_conjunta_id = o.pesada_conjunta_id) as pesada_ordenes,
       (select sum(o2.kg_solicitados) from ordenes_produccion o2 where o2.pesada_conjunta_id = o.pesada_conjunta_id) as pesada_kg_solicitados
from ordenes_produccion o
join formulas f on f.id = o.formula_id
left join granjas g on g.id = o.granja_id
left join perfiles pf on pf.id = o.capturado_por
left join perfiles pm on pm.id = o.modificado_por
left join pesadas_conjuntas pc on pc.id = o.pesada_conjunta_id
left join lateral (
  select round(sum(-m.kg * m.costo_kg), 2) as costo_mp
  from movimientos_mp m where m.origen = 'orden' and m.origen_id = o.id
) c on true;


-- ---------- Nota de entrada con varios productos ----------
create table notas_entrada (
  id             bigint generated always as identity primary key,
  fecha          date not null default current_date,
  proveedor_id   bigint references proveedores (id),
  folio          text,                 -- folio de la nota o boleta
  factura        text,
  kg_bascula     numeric(14,2) check (kg_bascula > 0),   -- total pesado (opcional)
  ajustada       boolean not null default false,          -- true = los kg se ajustaron a la báscula
  notas          text,
  capturado_por  uuid references auth.users (id),
  capturado_en   timestamptz,
  modificado_en  timestamptz
);
create trigger captura before insert or update on notas_entrada for each row execute function marcar_captura();
select aplicar_seguridad('notas_entrada', 'planta');

-- El folio de la nota tampoco se repite (ni contra otras notas ni contra boletas de llegadas).
create or replace function trg_folio_nota_unico() returns trigger language plpgsql as $$
declare v_fecha date;
begin
  if nullif(trim(new.folio), '') is null then new.folio := null; return new; end if;
  new.folio := regexp_replace(upper(trim(new.folio)), '\s+', ' ', 'g');
  select fecha into v_fecha from notas_entrada
  where nombre_normalizado(folio) = nombre_normalizado(new.folio) and id <> coalesce(new.id, -1) limit 1;
  if v_fecha is null then
    select fecha into v_fecha from llegadas_mp where nombre_normalizado(boleta) = nombre_normalizado(new.folio) limit 1;
  end if;
  if v_fecha is not null then
    raise exception 'El folio % ya está registrado (llegada del %). No puede repetirse.', new.folio, to_char(v_fecha, 'DD/MM/YYYY');
  end if;
  return new;
end $$;
create trigger folio_unico before insert or update of folio on notas_entrada
  for each row execute function trg_folio_nota_unico();

alter table llegadas_mp add column nota_id bigint references notas_entrada (id) on delete cascade;
create index on llegadas_mp (nota_id);

-- p_lineas = [{"materia_prima_id": 12, "kg": 500, "precio_kg": 8.5}, …]  (kg según la nota)
-- p_ajustar = true: reparte el total de báscula en proporción a los kg de la nota.
create or replace function crear_nota_entrada(
  p_fecha date, p_proveedor_id bigint, p_folio text, p_factura text, p_lineas jsonb,
  p_kg_bascula numeric default null, p_ajustar boolean default false,
  p_precio_provisional boolean default false, p_notas text default null
) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_suma numeric;
  v_n int;
  v_asignado numeric := 0;
  x jsonb;
  i int := 0;
  v_kg numeric;
begin
  v_n := jsonb_array_length(coalesce(p_lineas, '[]'));
  if v_n < 1 then raise exception 'La nota necesita al menos un producto'; end if;
  select sum((e->>'kg')::numeric) into v_suma from jsonb_array_elements(p_lineas) e;
  if coalesce(v_suma, 0) <= 0 then raise exception 'Captura los kg de cada producto'; end if;
  if p_ajustar and coalesce(p_kg_bascula, 0) <= 0 then raise exception 'Para ajustar a la báscula captura el total pesado'; end if;

  insert into notas_entrada (fecha, proveedor_id, folio, factura, kg_bascula, ajustada, notas)
  values (p_fecha, p_proveedor_id, p_folio, nullif(trim(p_factura), ''), p_kg_bascula, p_ajustar, nullif(trim(p_notas), ''))
  returning id into v_id;

  for x in select * from jsonb_array_elements(p_lineas) loop
    i := i + 1;
    v_kg := (x->>'kg')::numeric;
    if p_ajustar then
      v_kg := case when i = v_n then p_kg_bascula - v_asignado else round(v_kg * p_kg_bascula / v_suma, 2) end;
      v_asignado := v_asignado + v_kg;
    end if;
    insert into llegadas_mp (fecha, materia_prima_id, proveedor_id, kg_neto, precio_kg, factura, notas,
                             precio_provisional, nota_id)
    values (p_fecha, (x->>'materia_prima_id')::bigint, p_proveedor_id, v_kg, (x->>'precio_kg')::numeric,
            nullif(trim(p_factura), ''),
            case when p_ajustar then 'Kg según nota: ' || (x->>'kg') || '; ajustado a báscula' end,
            p_precio_provisional, v_id);
  end loop;
  return v_id;
end $$;
revoke execute on function crear_nota_entrada(date, bigint, text, text, jsonb, numeric, boolean, boolean, text) from anon;

-- Completar la factura de toda la nota (cuando llega después).
create or replace function factura_nota(p_nota_id bigint, p_factura text) returns void
language plpgsql as $$
begin
  update notas_entrada set factura = nullif(trim(p_factura), '') where id = p_nota_id;
  update llegadas_mp set factura = nullif(trim(p_factura), '') where nota_id = p_nota_id;
end $$;
revoke execute on function factura_nota(bigint, text) from anon;

-- Historial de llegadas con su nota (columnas nuevas al final).
create or replace view v_llegadas with (security_invoker = true) as
select l.id, l.fecha, l.kg_bruto, l.kg_tara, l.kg_neto, l.humedad_pct, l.precio_kg, l.total,
       l.factura, l.boleta, l.notas, l.capturado_en,
       l.materia_prima_id, mp.nombre as materia_prima,
       l.proveedor_id, pr.nombre as proveedor,
       l.bodega_id, b.nombre as bodega,
       pf.nombre as capturado_por,
       l.contrato_id, coalesce(c.folio, '#' || c.id) as contrato, l.tipo_cambio,
       l.precio_provisional, c.moneda as moneda_contrato, c.precio as precio_contrato,
       -- Parte de esta llegada que rebasó lo contratado (diferencial), en orden de fecha
       case when l.contrato_id is null then 0 else
         greatest(0, sum(l.kg_neto) over w - c.kg_contratados) - greatest(0, sum(l.kg_neto) over w - l.kg_neto - c.kg_contratados)
       end as kg_excedente_contrato,
       array_remove(array[
         case when nullif(trim(l.factura), '') is null then 'factura' end,
         case when l.precio_provisional then 'precio' end
       ], null) as pendientes,
       pm.nombre as modificado_por, l.modificado_en,
       l.nota_id, ne.folio as nota_folio, ne.kg_bascula as nota_kg_bascula,
       (select count(*) from llegadas_mp l2 where l2.nota_id = l.nota_id) as nota_productos
from llegadas_mp l
join materias_primas mp on mp.id = l.materia_prima_id
left join proveedores pr on pr.id = l.proveedor_id
left join bodegas b on b.id = l.bodega_id
left join perfiles pf on pf.id = l.capturado_por
left join contratos_mp c on c.id = l.contrato_id
left join perfiles pm on pm.id = l.modificado_por
left join notas_entrada ne on ne.id = l.nota_id
window w as (partition by l.contrato_id order by l.fecha, l.id);

-- >>>>>>>>>> migrations/0018_ventas.sql
-- =====================================================================
-- 0018_ventas.sql — Ventas de huevo, cerdo, ganado y borregos
--
--   venta            : encabezado (fecha, cliente, destino, pago, factura, flete, descuento, anticipo).
--   venta_renglones  : granja + calidad + cantidad (cajas, cerdos o cabezas) + kg + precio por kg.
--   Huevo: kg = pesados en báscula; merma = 2 kg por caja (configurable en la venta);
--          kg netos = kg − merma; precio total por kg = precio base México + flete por kg.
--   Total = Σ kg netos × (precio + flete) − descuento. Saldo = total − anticipo (0 si es de contado).
--   Se guarda con guardar_venta() (encabezado y renglones en un solo paso); es editable después.
-- =====================================================================

insert into modulos (codigo, nombre, orden) values ('ventas', 'Ventas', 2), ('compras', 'Compras', 2)
on conflict (codigo) do nothing;

-- Razones sociales con las que se factura (solo como distintivo).
create table empresas_factura (
  id      bigint generated always as identity primary key,
  nombre  text not null unique,
  activa  boolean not null default true
);
insert into empresas_factura (nombre) values ('Pecuaria Real Victoria'), ('Maront'), ('Humberto Martínez');
select aplicar_seguridad('empresas_factura', 'catalogos');

-- Calidades por especie.
create table calidades_venta (
  especie  text not null check (especie in ('huevo', 'cerdo', 'ganado', 'borrego')),
  nombre   text not null,
  orden    int not null default 0,
  activa   boolean not null default true,
  primary key (especie, nombre)
);
insert into calidades_venta (especie, nombre, orden) values
  ('huevo', 'Línea', 1), ('huevo', 'Sucio', 2), ('huevo', 'Semisucio', 3), ('huevo', 'Canica/Chico', 4),
  ('huevo', 'Roto', 5), ('huevo', 'Líquido', 6),
  ('cerdo', 'C1', 1), ('cerdo', 'C1.5', 2), ('cerdo', 'C2', 3), ('cerdo', 'Caídas', 4), ('cerdo', 'Canal', 5),
  ('cerdo', 'Línea', 6), ('cerdo', 'Chiclanes', 7),
  ('ganado', 'Registro', 1), ('ganado', 'Comercial', 2), ('ganado', 'Desecho', 3);
-- Borrego: calidades pendientes; mientras tanto se escriben libres.
select aplicar_seguridad('calidades_venta', 'catalogos');

-- Clientes: también los da de alta quien captura ventas.
alter table clientes add column razon_social text;
alter table clientes add column notas text;
create policy capturar_ventas on clientes for insert to authenticated with check (puede_capturar('ventas'));
create policy editar_ventas on clientes for update to authenticated
  using (puede_capturar('ventas')) with check (puede_capturar('ventas'));

create table ventas (
  id                 bigint generated always as identity primary key,
  especie            text not null check (especie in ('huevo', 'cerdo', 'ganado', 'borrego')),
  fecha              date not null default current_date,
  cliente_id         bigint not null references clientes (id),
  destino            text,
  tipo_pago          text not null default 'factura' check (tipo_pago in ('efectivo', 'factura')),
  empresa_factura_id bigint references empresas_factura (id),
  factura            text,
  forma_pago         text not null default 'contado' check (forma_pago in ('contado', 'credito')),
  anticipo           numeric(14,2) not null default 0 check (anticipo >= 0),
  flete_kg           numeric(10,4) not null default 0 check (flete_kg >= 0),      -- huevo
  merma_kg_caja      numeric(6,3) not null default 0 check (merma_kg_caja >= 0), -- huevo: 2 kg por caja
  muertos            int not null default 0 check (muertos >= 0),                -- cerdo
  descuento          numeric(14,2) not null default 0 check (descuento >= 0),
  motivo_descuento   text,
  notas              text,
  capturado_por      uuid references auth.users (id),
  capturado_en       timestamptz,
  modificado_por     uuid references auth.users (id),
  modificado_en      timestamptz
);
create index on ventas (especie, fecha);
create index on ventas (cliente_id);
create trigger captura before insert or update on ventas for each row execute function marcar_captura();
create or replace function trg_modifico_venta() returns trigger language plpgsql as $$
begin new.modificado_por := auth.uid(); return new; end $$;
create trigger modifico before update on ventas for each row execute function trg_modifico_venta();
select aplicar_seguridad('ventas', 'ventas');

create table venta_renglones (
  id         bigint generated always as identity primary key,
  venta_id   bigint not null references ventas (id) on delete cascade,
  granja_id  bigint references granjas (id),
  calidad    text,
  cantidad   numeric(12,2) not null default 0 check (cantidad >= 0),   -- cajas, cerdos o cabezas
  kg         numeric(14,2) not null check (kg > 0),                     -- kg pesados (brutos)
  precio_kg  numeric(12,4) not null check (precio_kg >= 0)              -- huevo: precio base México
);
create index on venta_renglones (venta_id);
select aplicar_seguridad('venta_renglones', 'ventas');
create policy borrar_ventas on venta_renglones for delete to authenticated using (puede_capturar('ventas'));

-- Guarda encabezado + renglones (nuevo o, con p_id, corrección).
create or replace function guardar_venta(p_venta jsonb, p_renglones jsonb, p_id bigint default null) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_cliente bigint := (p_venta->>'cliente_id')::bigint;
begin
  if v_cliente is null then raise exception 'Elige el cliente'; end if;
  if jsonb_array_length(coalesce(p_renglones, '[]')) = 0 then raise exception 'La venta necesita al menos un renglón'; end if;
  if p_venta->>'tipo_pago' = 'factura' and nullif(p_venta->>'empresa_factura_id', '') is null then
    raise exception 'Elige la razón social con la que se factura';
  end if;

  if p_id is null then
    insert into ventas (especie, fecha, cliente_id, destino, tipo_pago, empresa_factura_id, factura, forma_pago, anticipo,
                        flete_kg, merma_kg_caja, muertos, descuento, motivo_descuento, notas)
    values (p_venta->>'especie', (p_venta->>'fecha')::date, v_cliente, nullif(trim(p_venta->>'destino'), ''),
            coalesce(p_venta->>'tipo_pago', 'factura'), nullif(p_venta->>'empresa_factura_id', '')::bigint,
            nullif(trim(p_venta->>'factura'), ''), coalesce(p_venta->>'forma_pago', 'contado'),
            coalesce((p_venta->>'anticipo')::numeric, 0), coalesce((p_venta->>'flete_kg')::numeric, 0),
            coalesce((p_venta->>'merma_kg_caja')::numeric, 0), coalesce((p_venta->>'muertos')::int, 0),
            coalesce((p_venta->>'descuento')::numeric, 0), nullif(trim(p_venta->>'motivo_descuento'), ''),
            nullif(trim(p_venta->>'notas'), ''))
    returning id into v_id;
  else
    update ventas set fecha = (p_venta->>'fecha')::date, cliente_id = v_cliente,
        destino = nullif(trim(p_venta->>'destino'), ''), tipo_pago = coalesce(p_venta->>'tipo_pago', 'factura'),
        empresa_factura_id = nullif(p_venta->>'empresa_factura_id', '')::bigint, factura = nullif(trim(p_venta->>'factura'), ''),
        forma_pago = coalesce(p_venta->>'forma_pago', 'contado'), anticipo = coalesce((p_venta->>'anticipo')::numeric, 0),
        flete_kg = coalesce((p_venta->>'flete_kg')::numeric, 0), merma_kg_caja = coalesce((p_venta->>'merma_kg_caja')::numeric, 0),
        muertos = coalesce((p_venta->>'muertos')::int, 0), descuento = coalesce((p_venta->>'descuento')::numeric, 0),
        motivo_descuento = nullif(trim(p_venta->>'motivo_descuento'), ''), notas = nullif(trim(p_venta->>'notas'), '')
      where id = p_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró la venta % o no tienes permiso para cambiarla', p_id; end if;
    delete from venta_renglones where venta_id = v_id;
  end if;

  insert into venta_renglones (venta_id, granja_id, calidad, cantidad, kg, precio_kg)
  select v_id, nullif(x->>'granja_id', '')::bigint, nullif(trim(x->>'calidad'), ''),
         coalesce((x->>'cantidad')::numeric, 0), (x->>'kg')::numeric, (x->>'precio_kg')::numeric
  from jsonb_array_elements(p_renglones) x;
  return v_id;
end $$;
revoke execute on function guardar_venta(jsonb, jsonb, bigint) from anon;

-- Renglones con sus cálculos.
create or replace view v_venta_renglones with (security_invoker = true) as
select r.id, r.venta_id, r.granja_id, g.nombre as granja, r.calidad, r.cantidad, r.kg as kg_brutos,
       round(r.cantidad * v.merma_kg_caja, 2) as merma_kg,
       r.kg - round(r.cantidad * v.merma_kg_caja, 2) as kg_netos,
       case when r.cantidad > 0 then round(r.kg / r.cantidad, 2) end as peso_promedio,
       r.precio_kg, v.flete_kg, r.precio_kg + v.flete_kg as precio_total_kg,
       round((r.kg - r.cantidad * v.merma_kg_caja) * (r.precio_kg + v.flete_kg), 2) as importe
from venta_renglones r
join ventas v on v.id = r.venta_id
left join granjas g on g.id = r.granja_id;

-- Ventas con totales, saldo y quién capturó.
create or replace view v_ventas with (security_invoker = true) as
select v.id, v.especie, v.fecha, v.cliente_id, c.nombre as cliente, c.rfc, v.destino,
       v.tipo_pago, v.empresa_factura_id, e.nombre as empresa_factura, v.factura, v.forma_pago, v.anticipo,
       v.flete_kg, v.merma_kg_caja, v.muertos, v.descuento, v.motivo_descuento, v.notas,
       coalesce(t.cantidad, 0) as cantidad, coalesce(t.kg_brutos, 0) as kg_brutos, coalesce(t.merma_kg, 0) as merma_kg,
       coalesce(t.kg_netos, 0) as kg_netos,
       case when t.cantidad > 0 then round(t.kg_brutos / t.cantidad, 2) end as peso_promedio,
       coalesce(t.importe, 0) as subtotal,
       coalesce(t.importe, 0) - v.descuento as total,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento) / t.kg_netos, 4) end as precio_promedio_kg,
       case when v.forma_pago = 'contado' then 0 else greatest(coalesce(t.importe, 0) - v.descuento - v.anticipo, 0) end as saldo,
       t.calidades, t.granjas,
       pf.nombre as capturado_por, v.capturado_en, pm.nombre as modificado_por, v.modificado_en
from ventas v
join clientes c on c.id = v.cliente_id
left join empresas_factura e on e.id = v.empresa_factura_id
left join perfiles pf on pf.id = v.capturado_por
left join perfiles pm on pm.id = v.modificado_por
left join lateral (
  select sum(r.cantidad) as cantidad, sum(r.kg_brutos) as kg_brutos, sum(r.merma_kg) as merma_kg, sum(r.kg_netos) as kg_netos,
         sum(r.importe) as importe,
         string_agg(distinct r.calidad, ', ') as calidades, string_agg(distinct r.granja, ', ') as granjas
  from v_venta_renglones r where r.venta_id = v.id
) t on true;

alter publication supabase_realtime add table ventas;

-- >>>>>>>>>> migrations/0019_berries_generales_cobranza.sql
-- =====================================================================
-- 0019_berries_generales_cobranza.sql — Ventas de berries, ventas generales y cobranza
--
--   Berries: presentación (12×18 oz, 6 oz, 18 mm, rejilla 8 kg, granel…), calidad libre con sugerencias,
--            precio por kg o por caja, pesos o dólares, folio interno y externo, merma por renglón.
--   Generales: productos extraordinarios (abono, gallina de desecho a rastro…) de un catálogo que se va armando.
--   Cobranza: pagos de clientes aplicados a una o varias ventas; saldo por venta y por cliente.
-- =====================================================================

-- ---------- Especies nuevas ----------
alter table ventas drop constraint ventas_especie_check;
alter table ventas add constraint ventas_especie_check
  check (especie in ('huevo', 'cerdo', 'ganado', 'borrego', 'berries', 'general'));
alter table calidades_venta drop constraint calidades_venta_especie_check;
alter table calidades_venta add constraint calidades_venta_especie_check
  check (especie in ('huevo', 'cerdo', 'ganado', 'borrego', 'berries', 'general'));
-- Sugerencias de calidad de berries (tomadas de VTA BERRIES 2026); la calidad se puede escribir libre.
insert into calidades_venta (especie, nombre, orden) values
  ('berries', 'Jumbo', 1), ('berries', 'Pinta', 2), ('berries', 'Código 1', 3), ('berries', 'Código 2', 4), ('berries', 'Proceso', 5)
on conflict do nothing;

alter table ventas add column folio text;
alter table ventas add column folio_externo text;
alter table ventas add column moneda text not null default 'MXN' check (moneda in ('MXN', 'USD'));
alter table ventas add column tipo_cambio numeric(10,4) check (tipo_cambio > 0);

-- ---------- Catálogos ----------
create table productos_venta (
  id               bigint generated always as identity primary key,
  nombre           text not null unique,
  unidad           text not null default 'kg',       -- kg, pieza, tonelada, viaje, costal…
  area             text,                              -- aves, cerdos, ganado, borregos, berries, planta, otro
  precio_sugerido  numeric(12,4),
  activo           boolean not null default true,
  creado_por       uuid references auth.users (id),
  creado_en        timestamptz default now()
);
insert into productos_venta (nombre, unidad, area) values
  ('GALLINA DE DESECHO (RASTRO)', 'pieza', 'aves'),
  ('ABONO', 'tonelada', 'otro');
select aplicar_seguridad('productos_venta', 'catalogos');
create policy capturar_ventas on productos_venta for insert to authenticated with check (puede_capturar('ventas'));

create table presentaciones_venta (
  especie      text not null,
  nombre       text not null,
  kg_por_caja  numeric(10,3),
  orden        int not null default 0,
  primary key (especie, nombre)
);
-- Tomadas de VTA BERRIES 2026 (kg netos por caja); se pueden escribir otras.
insert into presentaciones_venta (especie, nombre, kg_por_caja, orden) values
  ('berries', '12 x 18 oz', 6.12, 1), ('berries', '6 oz', 2.04, 2), ('berries', '6 oz en 12-16 mm', 2.04, 3),
  ('berries', '18 mm', 3.36, 4), ('berries', '12 mm', 3.74, 5), ('berries', '12 x 11 oz', 3.4, 6),
  ('berries', '18 oz', null, 7), ('berries', 'Rejilla 8 kg', 8, 8), ('berries', 'Rejilla 4 kg', 4, 9),
  ('berries', 'Granel', null, 10);
select aplicar_seguridad('presentaciones_venta', 'catalogos');

-- ---------- Renglones más flexibles ----------
alter table venta_renglones alter column kg drop not null;
alter table venta_renglones drop constraint venta_renglones_kg_check;
alter table venta_renglones add constraint venta_renglones_kg_check check (kg is null or kg >= 0);
alter table venta_renglones add column presentacion text;
alter table venta_renglones add column producto_id bigint references productos_venta (id);
alter table venta_renglones add column precio_por text not null default 'kg' check (precio_por in ('kg', 'unidad'));
alter table venta_renglones add column merma_kg numeric(12,3) check (merma_kg >= 0);   -- merma capturada (berries)

-- Las vistas cambian tipos de columnas: se vuelven a crear (v_ventas depende de v_venta_renglones).
drop view v_ventas;
drop view v_venta_renglones;

-- Importe: por kg = kg netos × (precio + flete); por unidad = cantidad × precio.
create or replace view v_venta_renglones with (security_invoker = true) as
select r.id, r.venta_id, r.granja_id, g.nombre as granja, r.calidad, r.cantidad, coalesce(r.kg, 0) as kg_brutos,
       round(coalesce(r.merma_kg, r.cantidad * v.merma_kg_caja), 2) as merma_kg,
       coalesce(r.kg, 0) - round(coalesce(r.merma_kg, r.cantidad * v.merma_kg_caja), 2) as kg_netos,
       case when r.cantidad > 0 and r.kg > 0 then round(r.kg / r.cantidad, 2) end as peso_promedio,
       r.precio_kg, v.flete_kg,
       case when r.precio_por = 'unidad' then r.precio_kg else r.precio_kg + v.flete_kg end as precio_total_kg,
       case when r.precio_por = 'unidad' then round(r.cantidad * r.precio_kg, 2)
            else round((coalesce(r.kg, 0) - coalesce(r.merma_kg, r.cantidad * v.merma_kg_caja)) * (r.precio_kg + v.flete_kg), 2)
       end as importe,
       r.presentacion, r.producto_id, p.nombre as producto, p.unidad, r.precio_por
from venta_renglones r
join ventas v on v.id = r.venta_id
left join granjas g on g.id = r.granja_id
left join productos_venta p on p.id = r.producto_id;

-- ---------- Cobranza ----------
create table pagos_cliente (
  id             bigint generated always as identity primary key,
  cliente_id     bigint not null references clientes (id),
  fecha          date not null default current_date,
  monto          numeric(14,2) not null check (monto > 0),
  moneda         text not null default 'MXN' check (moneda in ('MXN', 'USD')),
  tipo_cambio    numeric(10,4) check (tipo_cambio > 0),
  forma          text not null default 'transferencia' check (forma in ('transferencia', 'efectivo', 'cheque', 'otro')),
  banco          text,
  referencia     text,          -- vale, folio de transferencia…
  factura        text,
  notas          text,
  capturado_por  uuid references auth.users (id),
  capturado_en   timestamptz,
  modificado_en  timestamptz
);
create index on pagos_cliente (cliente_id, fecha);
create trigger captura before insert or update on pagos_cliente for each row execute function marcar_captura();
select aplicar_seguridad('pagos_cliente', 'ventas');

create table pago_aplicaciones (
  pago_id   bigint not null references pagos_cliente (id) on delete cascade,
  venta_id  bigint not null references ventas (id) on delete cascade,
  monto     numeric(14,2) not null check (monto > 0),
  primary key (pago_id, venta_id)
);
create index on pago_aplicaciones (venta_id);
select aplicar_seguridad('pago_aplicaciones', 'ventas');
create policy borrar_ventas on pago_aplicaciones for delete to authenticated using (puede_capturar('ventas'));

-- Ventas con totales, pagos y saldo (columnas nuevas al final).
create or replace view v_ventas with (security_invoker = true) as
select v.id, v.especie, v.fecha, v.cliente_id, c.nombre as cliente, c.rfc, v.destino,
       v.tipo_pago, v.empresa_factura_id, e.nombre as empresa_factura, v.factura, v.forma_pago, v.anticipo,
       v.flete_kg, v.merma_kg_caja, v.muertos, v.descuento, v.motivo_descuento, v.notas,
       coalesce(t.cantidad, 0) as cantidad, coalesce(t.kg_brutos, 0) as kg_brutos, coalesce(t.merma_kg, 0) as merma_kg,
       coalesce(t.kg_netos, 0) as kg_netos,
       case when t.cantidad > 0 and t.kg_brutos > 0 then round(t.kg_brutos / t.cantidad, 2) end as peso_promedio,
       coalesce(t.importe, 0) as subtotal,
       coalesce(t.importe, 0) - v.descuento as total,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento) / t.kg_netos, 4) end as precio_promedio_kg,
       case when v.forma_pago = 'contado' then 0
            else greatest(coalesce(t.importe, 0) - v.descuento - v.anticipo - coalesce(pg.pagado, 0), 0) end as saldo,
       t.calidades, t.granjas,
       pf.nombre as capturado_por, v.capturado_en, pm.nombre as modificado_por, v.modificado_en,
       v.folio, v.folio_externo, v.moneda, v.tipo_cambio,
       coalesce(pg.pagado, 0) as pagado, t.productos, t.presentaciones
from ventas v
join clientes c on c.id = v.cliente_id
left join empresas_factura e on e.id = v.empresa_factura_id
left join perfiles pf on pf.id = v.capturado_por
left join perfiles pm on pm.id = v.modificado_por
left join lateral (
  select sum(r.cantidad) as cantidad, sum(r.kg_brutos) as kg_brutos, sum(r.merma_kg) as merma_kg, sum(r.kg_netos) as kg_netos,
         sum(r.importe) as importe,
         string_agg(distinct r.calidad, ', ') as calidades, string_agg(distinct r.granja, ', ') as granjas,
         string_agg(distinct r.producto, ', ') as productos, string_agg(distinct r.presentacion, ', ') as presentaciones
  from v_venta_renglones r where r.venta_id = v.id
) t on true
left join lateral (select sum(a.monto) as pagado from pago_aplicaciones a where a.venta_id = v.id) pg on true;

-- Guarda encabezado + renglones (nuevo o, con p_id, corrección). Reemplaza la versión de 0018.
create or replace function guardar_venta(p_venta jsonb, p_renglones jsonb, p_id bigint default null) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_cliente bigint := (p_venta->>'cliente_id')::bigint;
begin
  if v_cliente is null then raise exception 'Elige el cliente'; end if;
  if jsonb_array_length(coalesce(p_renglones, '[]')) = 0 then raise exception 'La venta necesita al menos un renglón'; end if;
  if p_venta->>'tipo_pago' = 'factura' and nullif(p_venta->>'empresa_factura_id', '') is null then
    raise exception 'Elige la razón social con la que se factura';
  end if;
  if exists (select 1 from jsonb_array_elements(p_renglones) x
             where coalesce(x->>'precio_por', 'kg') = 'kg' and coalesce((x->>'kg')::numeric, 0) <= 0) then
    raise exception 'Captura los kg de cada renglón que se cobra por kg';
  end if;

  if p_id is null then
    insert into ventas (especie, fecha, cliente_id, destino, tipo_pago, empresa_factura_id, factura, forma_pago, anticipo,
                        flete_kg, merma_kg_caja, muertos, descuento, motivo_descuento, notas, folio, folio_externo, moneda, tipo_cambio)
    values (p_venta->>'especie', (p_venta->>'fecha')::date, v_cliente, nullif(trim(p_venta->>'destino'), ''),
            coalesce(p_venta->>'tipo_pago', 'factura'), nullif(p_venta->>'empresa_factura_id', '')::bigint,
            nullif(trim(p_venta->>'factura'), ''), coalesce(p_venta->>'forma_pago', 'contado'),
            coalesce((p_venta->>'anticipo')::numeric, 0), coalesce((p_venta->>'flete_kg')::numeric, 0),
            coalesce((p_venta->>'merma_kg_caja')::numeric, 0), coalesce((p_venta->>'muertos')::int, 0),
            coalesce((p_venta->>'descuento')::numeric, 0), nullif(trim(p_venta->>'motivo_descuento'), ''),
            nullif(trim(p_venta->>'notas'), ''), nullif(trim(p_venta->>'folio'), ''), nullif(trim(p_venta->>'folio_externo'), ''),
            coalesce(nullif(p_venta->>'moneda', ''), 'MXN'), nullif(p_venta->>'tipo_cambio', '')::numeric)
    returning id into v_id;
  else
    update ventas set fecha = (p_venta->>'fecha')::date, cliente_id = v_cliente,
        destino = nullif(trim(p_venta->>'destino'), ''), tipo_pago = coalesce(p_venta->>'tipo_pago', 'factura'),
        empresa_factura_id = nullif(p_venta->>'empresa_factura_id', '')::bigint, factura = nullif(trim(p_venta->>'factura'), ''),
        forma_pago = coalesce(p_venta->>'forma_pago', 'contado'), anticipo = coalesce((p_venta->>'anticipo')::numeric, 0),
        flete_kg = coalesce((p_venta->>'flete_kg')::numeric, 0), merma_kg_caja = coalesce((p_venta->>'merma_kg_caja')::numeric, 0),
        muertos = coalesce((p_venta->>'muertos')::int, 0), descuento = coalesce((p_venta->>'descuento')::numeric, 0),
        motivo_descuento = nullif(trim(p_venta->>'motivo_descuento'), ''), notas = nullif(trim(p_venta->>'notas'), ''),
        folio = nullif(trim(p_venta->>'folio'), ''), folio_externo = nullif(trim(p_venta->>'folio_externo'), ''),
        moneda = coalesce(nullif(p_venta->>'moneda', ''), 'MXN'), tipo_cambio = nullif(p_venta->>'tipo_cambio', '')::numeric
      where id = p_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró la venta % o no tienes permiso para cambiarla', p_id; end if;
    delete from venta_renglones where venta_id = v_id;
  end if;

  insert into venta_renglones (venta_id, granja_id, calidad, cantidad, kg, precio_kg, presentacion, producto_id, precio_por, merma_kg)
  select v_id, nullif(x->>'granja_id', '')::bigint, nullif(trim(x->>'calidad'), ''),
         coalesce((x->>'cantidad')::numeric, 0), nullif(x->>'kg', '')::numeric, (x->>'precio_kg')::numeric,
         nullif(trim(x->>'presentacion'), ''), nullif(x->>'producto_id', '')::bigint,
         coalesce(nullif(x->>'precio_por', ''), 'kg'), nullif(x->>'merma_kg', '')::numeric
  from jsonb_array_elements(p_renglones) x;
  return v_id;
end $$;

-- Registra (o corrige, con p_id) un pago y lo aplica a ventas del mismo cliente y moneda.
-- p_aplicaciones = [{"venta_id": 12, "monto": 5000}, …]  (lo no aplicado queda a favor del cliente)
create or replace function registrar_pago(p_pago jsonb, p_aplicaciones jsonb default '[]', p_id bigint default null) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_cliente bigint := (p_pago->>'cliente_id')::bigint;
  v_moneda text := coalesce(nullif(p_pago->>'moneda', ''), 'MXN');
  v_monto numeric := (p_pago->>'monto')::numeric;
  x jsonb;
  v record;
begin
  if v_cliente is null then raise exception 'Elige el cliente'; end if;
  if coalesce(v_monto, 0) <= 0 then raise exception 'El monto del pago debe ser mayor a cero'; end if;
  if (select coalesce(sum((a->>'monto')::numeric), 0) from jsonb_array_elements(coalesce(p_aplicaciones, '[]')) a) > v_monto + 0.005 then
    raise exception 'Lo aplicado a las ventas es mayor que el pago';
  end if;

  if p_id is null then
    insert into pagos_cliente (cliente_id, fecha, monto, moneda, tipo_cambio, forma, banco, referencia, factura, notas)
    values (v_cliente, (p_pago->>'fecha')::date, v_monto, v_moneda, nullif(p_pago->>'tipo_cambio', '')::numeric,
            coalesce(nullif(p_pago->>'forma', ''), 'transferencia'), nullif(trim(p_pago->>'banco'), ''),
            nullif(trim(p_pago->>'referencia'), ''), nullif(trim(p_pago->>'factura'), ''), nullif(trim(p_pago->>'notas'), ''))
    returning id into v_id;
  else
    update pagos_cliente set cliente_id = v_cliente, fecha = (p_pago->>'fecha')::date, monto = v_monto, moneda = v_moneda,
        tipo_cambio = nullif(p_pago->>'tipo_cambio', '')::numeric, forma = coalesce(nullif(p_pago->>'forma', ''), 'transferencia'),
        banco = nullif(trim(p_pago->>'banco'), ''), referencia = nullif(trim(p_pago->>'referencia'), ''),
        factura = nullif(trim(p_pago->>'factura'), ''), notas = nullif(trim(p_pago->>'notas'), '')
      where id = p_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró el pago % o no tienes permiso para cambiarlo', p_id; end if;
    delete from pago_aplicaciones where pago_id = v_id;
  end if;

  for x in select * from jsonb_array_elements(coalesce(p_aplicaciones, '[]')) loop
    select vv.id, vv.cliente_id, vv.moneda, vv.saldo, vv.folio, vv.fecha into v from v_ventas vv where vv.id = (x->>'venta_id')::bigint;
    if v.id is null then raise exception 'No se encontró la venta %', x->>'venta_id'; end if;
    if v.cliente_id <> v_cliente then raise exception 'La venta del % es de otro cliente', to_char(v.fecha, 'DD/MM/YYYY'); end if;
    if v.moneda <> v_moneda then raise exception 'La venta del % es en %, el pago en %', to_char(v.fecha, 'DD/MM/YYYY'), v.moneda, v_moneda; end if;
    if (x->>'monto')::numeric > v.saldo + 0.005 then
      raise exception 'A la venta del % solo le quedan % de saldo', to_char(v.fecha, 'DD/MM/YYYY'), v.saldo;
    end if;
    insert into pago_aplicaciones (pago_id, venta_id, monto) values (v_id, v.id, (x->>'monto')::numeric);
  end loop;
  return v_id;
end $$;
revoke execute on function registrar_pago(jsonb, jsonb, bigint) from anon;

create or replace view v_pagos with (security_invoker = true) as
select p.id, p.cliente_id, c.nombre as cliente, p.fecha, p.monto, p.moneda, p.tipo_cambio, p.forma, p.banco, p.referencia,
       p.factura, p.notas, coalesce(a.aplicado, 0) as aplicado, p.monto - coalesce(a.aplicado, 0) as sin_aplicar,
       a.ventas, pf.nombre as capturado_por, p.capturado_en
from pagos_cliente p
join clientes c on c.id = p.cliente_id
left join perfiles pf on pf.id = p.capturado_por
left join lateral (
  select sum(pa.monto) as aplicado,
         string_agg(coalesce(v.folio, to_char(v.fecha, 'DD/MM')) || ' (' || to_char(pa.monto, 'FM999,999,990.00') || ')', ', ' order by v.fecha) as ventas
  from pago_aplicaciones pa join ventas v on v.id = pa.venta_id where pa.pago_id = p.id
) a on true;

-- Saldo por cliente y moneda: lo que deben las ventas a crédito menos pagos sin aplicar.
create or replace view v_saldos_clientes with (security_invoker = true) as
with ventas_c as (
  select cliente_id, moneda, count(*) filter (where saldo > 0) as ventas_con_saldo, sum(saldo) as saldo_ventas,
         sum(total) as vendido, min(fecha) filter (where saldo > 0) as venta_mas_antigua
  from v_ventas group by cliente_id, moneda
), pagos_c as (
  select cliente_id, moneda, sum(sin_aplicar) as a_favor, sum(monto) as pagado, max(fecha) as ultimo_pago
  from v_pagos group by cliente_id, moneda
)
select c.id as cliente_id, c.nombre as cliente, c.rfc, coalesce(v.moneda, p.moneda) as moneda,
       coalesce(v.vendido, 0) as vendido, coalesce(p.pagado, 0) as pagado,
       coalesce(v.ventas_con_saldo, 0) as ventas_con_saldo, coalesce(v.saldo_ventas, 0) as saldo_ventas,
       coalesce(p.a_favor, 0) as a_favor, coalesce(v.saldo_ventas, 0) - coalesce(p.a_favor, 0) as saldo,
       v.venta_mas_antigua, p.ultimo_pago
from ventas_c v
full join pagos_c p on p.cliente_id = v.cliente_id and p.moneda = v.moneda
join clientes c on c.id = coalesce(v.cliente_id, p.cliente_id);

alter publication supabase_realtime add table pagos_cliente;

-- >>>>>>>>>> migrations/0020_flete_por_caja.sql
-- =====================================================================
-- 0020_flete_por_caja.sql — El flete del huevo se cobra por caja (varía según la ciudad destino)
--
--   Precio de venta = precio base México (CDMX) $/kg × kg netos + flete $/caja × cajas.
--   ventas.flete_caja reemplaza a flete_kg en la captura; flete_kg se conserva solo para ventas viejas
--   y las ventas ya capturadas con flete por kg se pasan a flete por caja (mismo flete total, redondeado).
-- =====================================================================

alter table ventas add column flete_caja numeric(10,4) not null default 0 check (flete_caja >= 0);

-- Ventas capturadas con flete por kg → flete por caja equivalente.
update ventas v set flete_caja = round(x.flete / x.cajas, 4), flete_kg = 0
from (select r.venta_id, sum((coalesce(r.kg, 0) - coalesce(r.merma_kg, r.cantidad * v2.merma_kg_caja)) * v2.flete_kg) as flete, sum(r.cantidad) as cajas
      from venta_renglones r join ventas v2 on v2.id = r.venta_id
      where v2.flete_kg > 0 and r.precio_por = 'kg' group by r.venta_id) x
where v.id = x.venta_id and x.cajas > 0;

drop view v_saldos_clientes;
drop view v_ventas;
drop view v_venta_renglones;

-- Importe: por kg = kg netos × (precio + flete_kg) + cajas × flete_caja; por unidad = cantidad × precio + cantidad × flete_caja.
-- precio_total_kg = precio base + flete repartido por kg neto.
create view v_venta_renglones with (security_invoker = true) as
with b as (
  select r.*, v.merma_kg_caja, v.flete_kg, v.flete_caja,
         round(coalesce(r.merma_kg, r.cantidad * v.merma_kg_caja), 2) as merma_calc,
         round(r.cantidad * v.flete_caja, 2) as flete_importe
  from venta_renglones r join ventas v on v.id = r.venta_id
)
select b.id, b.venta_id, b.granja_id, g.nombre as granja, b.calidad, b.cantidad, coalesce(b.kg, 0) as kg_brutos,
       b.merma_calc as merma_kg,
       coalesce(b.kg, 0) - b.merma_calc as kg_netos,
       case when b.cantidad > 0 and b.kg > 0 then round(b.kg / b.cantidad, 2) end as peso_promedio,
       b.precio_kg, b.flete_kg,
       case when b.precio_por = 'unidad' then b.precio_kg + b.flete_caja
            when coalesce(b.kg, 0) - b.merma_calc > 0 then round(b.precio_kg + b.flete_kg + b.flete_importe / (coalesce(b.kg, 0) - b.merma_calc), 4)
            else b.precio_kg + b.flete_kg end as precio_total_kg,
       case when b.precio_por = 'unidad' then round(b.cantidad * b.precio_kg, 2) + b.flete_importe
            else round((coalesce(b.kg, 0) - b.merma_calc) * (b.precio_kg + b.flete_kg), 2) + b.flete_importe
       end as importe,
       b.presentacion, b.producto_id, p.nombre as producto, p.unidad, b.precio_por,
       b.flete_caja, b.flete_importe
from b
left join granjas g on g.id = b.granja_id
left join productos_venta p on p.id = b.producto_id;

-- Ventas con totales, pagos y saldo (igual que 0019 + flete por caja al final).
create view v_ventas with (security_invoker = true) as
select v.id, v.especie, v.fecha, v.cliente_id, c.nombre as cliente, c.rfc, v.destino,
       v.tipo_pago, v.empresa_factura_id, e.nombre as empresa_factura, v.factura, v.forma_pago, v.anticipo,
       v.flete_kg, v.merma_kg_caja, v.muertos, v.descuento, v.motivo_descuento, v.notas,
       coalesce(t.cantidad, 0) as cantidad, coalesce(t.kg_brutos, 0) as kg_brutos, coalesce(t.merma_kg, 0) as merma_kg,
       coalesce(t.kg_netos, 0) as kg_netos,
       case when t.cantidad > 0 and t.kg_brutos > 0 then round(t.kg_brutos / t.cantidad, 2) end as peso_promedio,
       coalesce(t.importe, 0) as subtotal,
       coalesce(t.importe, 0) - v.descuento as total,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento) / t.kg_netos, 4) end as precio_promedio_kg,
       case when v.forma_pago = 'contado' then 0
            else greatest(coalesce(t.importe, 0) - v.descuento - v.anticipo - coalesce(pg.pagado, 0), 0) end as saldo,
       t.calidades, t.granjas,
       pf.nombre as capturado_por, v.capturado_en, pm.nombre as modificado_por, v.modificado_en,
       v.folio, v.folio_externo, v.moneda, v.tipo_cambio,
       coalesce(pg.pagado, 0) as pagado, t.productos, t.presentaciones,
       v.flete_caja, coalesce(t.flete, 0) as flete_total,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - coalesce(t.flete, 0) - v.descuento) / t.kg_netos, 4) end as precio_base_promedio_kg
from ventas v
join clientes c on c.id = v.cliente_id
left join empresas_factura e on e.id = v.empresa_factura_id
left join perfiles pf on pf.id = v.capturado_por
left join perfiles pm on pm.id = v.modificado_por
left join lateral (
  select sum(r.cantidad) as cantidad, sum(r.kg_brutos) as kg_brutos, sum(r.merma_kg) as merma_kg, sum(r.kg_netos) as kg_netos,
         sum(r.importe) as importe, sum(r.flete_importe) as flete,
         string_agg(distinct r.calidad, ', ') as calidades, string_agg(distinct r.granja, ', ') as granjas,
         string_agg(distinct r.producto, ', ') as productos, string_agg(distinct r.presentacion, ', ') as presentaciones
  from v_venta_renglones r where r.venta_id = v.id
) t on true
left join lateral (select sum(a.monto) as pagado from pago_aplicaciones a where a.venta_id = v.id) pg on true;


-- Saldo por cliente y moneda: lo que deben las ventas a crédito menos pagos sin aplicar.
create view v_saldos_clientes with (security_invoker = true) as
with ventas_c as (
  select cliente_id, moneda, count(*) filter (where saldo > 0) as ventas_con_saldo, sum(saldo) as saldo_ventas,
         sum(total) as vendido, min(fecha) filter (where saldo > 0) as venta_mas_antigua
  from v_ventas group by cliente_id, moneda
), pagos_c as (
  select cliente_id, moneda, sum(sin_aplicar) as a_favor, sum(monto) as pagado, max(fecha) as ultimo_pago
  from v_pagos group by cliente_id, moneda
)
select c.id as cliente_id, c.nombre as cliente, c.rfc, coalesce(v.moneda, p.moneda) as moneda,
       coalesce(v.vendido, 0) as vendido, coalesce(p.pagado, 0) as pagado,
       coalesce(v.ventas_con_saldo, 0) as ventas_con_saldo, coalesce(v.saldo_ventas, 0) as saldo_ventas,
       coalesce(p.a_favor, 0) as a_favor, coalesce(v.saldo_ventas, 0) - coalesce(p.a_favor, 0) as saldo,
       v.venta_mas_antigua, p.ultimo_pago
from ventas_c v
full join pagos_c p on p.cliente_id = v.cliente_id and p.moneda = v.moneda
join clientes c on c.id = coalesce(v.cliente_id, p.cliente_id);


-- Guarda encabezado + renglones. Reemplaza la de 0019 (agrega flete_caja).
create or replace function guardar_venta(p_venta jsonb, p_renglones jsonb, p_id bigint default null) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_cliente bigint := (p_venta->>'cliente_id')::bigint;
begin
  if v_cliente is null then raise exception 'Elige el cliente'; end if;
  if jsonb_array_length(coalesce(p_renglones, '[]')) = 0 then raise exception 'La venta necesita al menos un renglón'; end if;
  if p_venta->>'tipo_pago' = 'factura' and nullif(p_venta->>'empresa_factura_id', '') is null then
    raise exception 'Elige la razón social con la que se factura';
  end if;
  if exists (select 1 from jsonb_array_elements(p_renglones) x
             where coalesce(x->>'precio_por', 'kg') = 'kg' and coalesce((x->>'kg')::numeric, 0) <= 0) then
    raise exception 'Captura los kg de cada renglón que se cobra por kg';
  end if;

  if p_id is null then
    insert into ventas (especie, fecha, cliente_id, destino, tipo_pago, empresa_factura_id, factura, forma_pago, anticipo,
                        flete_kg, merma_kg_caja, muertos, descuento, motivo_descuento, notas, folio, folio_externo, moneda, tipo_cambio, flete_caja)
    values (p_venta->>'especie', (p_venta->>'fecha')::date, v_cliente, nullif(trim(p_venta->>'destino'), ''),
            coalesce(p_venta->>'tipo_pago', 'factura'), nullif(p_venta->>'empresa_factura_id', '')::bigint,
            nullif(trim(p_venta->>'factura'), ''), coalesce(p_venta->>'forma_pago', 'contado'),
            coalesce((p_venta->>'anticipo')::numeric, 0), coalesce((p_venta->>'flete_kg')::numeric, 0),
            coalesce((p_venta->>'merma_kg_caja')::numeric, 0), coalesce((p_venta->>'muertos')::int, 0),
            coalesce((p_venta->>'descuento')::numeric, 0), nullif(trim(p_venta->>'motivo_descuento'), ''),
            nullif(trim(p_venta->>'notas'), ''), nullif(trim(p_venta->>'folio'), ''), nullif(trim(p_venta->>'folio_externo'), ''),
            coalesce(nullif(p_venta->>'moneda', ''), 'MXN'), nullif(p_venta->>'tipo_cambio', '')::numeric,
            coalesce(nullif(p_venta->>'flete_caja', '')::numeric, 0))
    returning id into v_id;
  else
    update ventas set fecha = (p_venta->>'fecha')::date, cliente_id = v_cliente,
        destino = nullif(trim(p_venta->>'destino'), ''), tipo_pago = coalesce(p_venta->>'tipo_pago', 'factura'),
        empresa_factura_id = nullif(p_venta->>'empresa_factura_id', '')::bigint, factura = nullif(trim(p_venta->>'factura'), ''),
        forma_pago = coalesce(p_venta->>'forma_pago', 'contado'), anticipo = coalesce((p_venta->>'anticipo')::numeric, 0),
        flete_kg = coalesce((p_venta->>'flete_kg')::numeric, 0), merma_kg_caja = coalesce((p_venta->>'merma_kg_caja')::numeric, 0),
        muertos = coalesce((p_venta->>'muertos')::int, 0), descuento = coalesce((p_venta->>'descuento')::numeric, 0),
        motivo_descuento = nullif(trim(p_venta->>'motivo_descuento'), ''), notas = nullif(trim(p_venta->>'notas'), ''),
        folio = nullif(trim(p_venta->>'folio'), ''), folio_externo = nullif(trim(p_venta->>'folio_externo'), ''),
        moneda = coalesce(nullif(p_venta->>'moneda', ''), 'MXN'), tipo_cambio = nullif(p_venta->>'tipo_cambio', '')::numeric,
        flete_caja = coalesce(nullif(p_venta->>'flete_caja', '')::numeric, 0)
      where id = p_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró la venta % o no tienes permiso para cambiarla', p_id; end if;
    delete from venta_renglones where venta_id = v_id;
  end if;

  insert into venta_renglones (venta_id, granja_id, calidad, cantidad, kg, precio_kg, presentacion, producto_id, precio_por, merma_kg)
  select v_id, nullif(x->>'granja_id', '')::bigint, nullif(trim(x->>'calidad'), ''),
         coalesce((x->>'cantidad')::numeric, 0), nullif(x->>'kg', '')::numeric, (x->>'precio_kg')::numeric,
         nullif(trim(x->>'presentacion'), ''), nullif(x->>'producto_id', '')::bigint,
         coalesce(nullif(x->>'precio_por', ''), 'kg'), nullif(x->>'merma_kg', '')::numeric
  from jsonb_array_elements(p_renglones) x;
  return v_id;
end $$;


-- >>>>>>>>>> migrations/0021_flete_descuenta.sql
-- =====================================================================
-- 0021_flete_descuenta.sql — Corrige 0020: el flete NO se suma, se descuenta
--
--   El precio base México (CDMX) ya incluye el flete. Total de la venta (factura y cobranza) = kg netos × precio − descuento.
--   El flete (cajas × flete $/caja, según destino) lo paga la empresa: neto recibido = total − flete;
--   precio neto $/kg = neto ÷ kg netos.
-- =====================================================================

drop view v_saldos_clientes;
drop view v_ventas;
drop view v_venta_renglones;

-- Importe = kg netos × precio (o cantidad × precio si es por unidad); el flete va aparte en flete_importe.
create view v_venta_renglones with (security_invoker = true) as
with b as (
  select r.*, v.merma_kg_caja, v.flete_kg, v.flete_caja,
         round(coalesce(r.merma_kg, r.cantidad * v.merma_kg_caja), 2) as merma_calc,
         round(r.cantidad * v.flete_caja, 2) as flete_importe
  from venta_renglones r join ventas v on v.id = r.venta_id
)
select b.id, b.venta_id, b.granja_id, g.nombre as granja, b.calidad, b.cantidad, coalesce(b.kg, 0) as kg_brutos,
       b.merma_calc as merma_kg,
       coalesce(b.kg, 0) - b.merma_calc as kg_netos,
       case when b.cantidad > 0 and b.kg > 0 then round(b.kg / b.cantidad, 2) end as peso_promedio,
       b.precio_kg, b.flete_kg,
       case when b.precio_por = 'unidad' then b.precio_kg else b.precio_kg + b.flete_kg end as precio_total_kg,
       case when b.precio_por = 'unidad' then round(b.cantidad * b.precio_kg, 2)
            else round((coalesce(b.kg, 0) - b.merma_calc) * (b.precio_kg + b.flete_kg), 2)
       end as importe,
       b.presentacion, b.producto_id, p.nombre as producto, p.unidad, b.precio_por,
       b.flete_caja, b.flete_importe,
       case when coalesce(b.kg, 0) - b.merma_calc > 0 and b.precio_por = 'kg'
            then round(b.precio_kg + b.flete_kg - b.flete_importe / (coalesce(b.kg, 0) - b.merma_calc), 4) end as precio_neto_kg
from b
left join granjas g on g.id = b.granja_id
left join productos_venta p on p.id = b.producto_id;

-- Ventas: total = factura (precio base ya incluye flete); neto = total − flete que paga la empresa.
create view v_ventas with (security_invoker = true) as
select v.id, v.especie, v.fecha, v.cliente_id, c.nombre as cliente, c.rfc, v.destino,
       v.tipo_pago, v.empresa_factura_id, e.nombre as empresa_factura, v.factura, v.forma_pago, v.anticipo,
       v.flete_kg, v.merma_kg_caja, v.muertos, v.descuento, v.motivo_descuento, v.notas,
       coalesce(t.cantidad, 0) as cantidad, coalesce(t.kg_brutos, 0) as kg_brutos, coalesce(t.merma_kg, 0) as merma_kg,
       coalesce(t.kg_netos, 0) as kg_netos,
       case when t.cantidad > 0 and t.kg_brutos > 0 then round(t.kg_brutos / t.cantidad, 2) end as peso_promedio,
       coalesce(t.importe, 0) as subtotal,
       coalesce(t.importe, 0) - v.descuento as total,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento) / t.kg_netos, 4) end as precio_promedio_kg,
       case when v.forma_pago = 'contado' then 0
            else greatest(coalesce(t.importe, 0) - v.descuento - v.anticipo - coalesce(pg.pagado, 0), 0) end as saldo,
       t.calidades, t.granjas,
       pf.nombre as capturado_por, v.capturado_en, pm.nombre as modificado_por, v.modificado_en,
       v.folio, v.folio_externo, v.moneda, v.tipo_cambio,
       coalesce(pg.pagado, 0) as pagado, t.productos, t.presentaciones,
       v.flete_caja, coalesce(t.flete, 0) as flete_total,
       coalesce(t.importe, 0) - v.descuento - coalesce(t.flete, 0) as neto,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento - coalesce(t.flete, 0)) / t.kg_netos, 4) end as precio_neto_kg
from ventas v
join clientes c on c.id = v.cliente_id
left join empresas_factura e on e.id = v.empresa_factura_id
left join perfiles pf on pf.id = v.capturado_por
left join perfiles pm on pm.id = v.modificado_por
left join lateral (
  select sum(r.cantidad) as cantidad, sum(r.kg_brutos) as kg_brutos, sum(r.merma_kg) as merma_kg, sum(r.kg_netos) as kg_netos,
         sum(r.importe) as importe, sum(r.flete_importe) as flete,
         string_agg(distinct r.calidad, ', ') as calidades, string_agg(distinct r.granja, ', ') as granjas,
         string_agg(distinct r.producto, ', ') as productos, string_agg(distinct r.presentacion, ', ') as presentaciones
  from v_venta_renglones r where r.venta_id = v.id
) t on true
left join lateral (select sum(a.monto) as pagado from pago_aplicaciones a where a.venta_id = v.id) pg on true;


-- Saldo por cliente y moneda: lo que deben las ventas a crédito menos pagos sin aplicar.
create view v_saldos_clientes with (security_invoker = true) as
with ventas_c as (
  select cliente_id, moneda, count(*) filter (where saldo > 0) as ventas_con_saldo, sum(saldo) as saldo_ventas,
         sum(total) as vendido, min(fecha) filter (where saldo > 0) as venta_mas_antigua
  from v_ventas group by cliente_id, moneda
), pagos_c as (
  select cliente_id, moneda, sum(sin_aplicar) as a_favor, sum(monto) as pagado, max(fecha) as ultimo_pago
  from v_pagos group by cliente_id, moneda
)
select c.id as cliente_id, c.nombre as cliente, c.rfc, coalesce(v.moneda, p.moneda) as moneda,
       coalesce(v.vendido, 0) as vendido, coalesce(p.pagado, 0) as pagado,
       coalesce(v.ventas_con_saldo, 0) as ventas_con_saldo, coalesce(v.saldo_ventas, 0) as saldo_ventas,
       coalesce(p.a_favor, 0) as a_favor, coalesce(v.saldo_ventas, 0) - coalesce(p.a_favor, 0) as saldo,
       v.venta_mas_antigua, p.ultimo_pago
from ventas_c v
full join pagos_c p on p.cliente_id = v.cliente_id and p.moneda = v.moneda
join clientes c on c.id = coalesce(v.cliente_id, p.cliente_id);



-- >>>>>>>>>> migrations/0022_destino_huevo.sql
-- =====================================================================
-- 0022_destino_huevo.sql — Huevo: sin flete; destino (colonia, ciudad, estado) y aumento al destino
--
--   El flete ya no se captura ni se descuenta (la empresa ya lo considera en su precio): flete_caja queda en 0.
--   aumento_centavos_kg = cuántos centavos por kg aumenta el precio en ese destino. Es solo un dato de referencia:
--   no cambia el precio, el total ni el saldo.
-- =====================================================================

alter table ventas add column destino_colonia text;
alter table ventas add column destino_ciudad text;
alter table ventas add column destino_estado text;
alter table ventas add column aumento_centavos_kg numeric(10,2) check (aumento_centavos_kg >= 0);

update ventas set flete_caja = 0 where flete_caja <> 0;

drop view v_saldos_clientes;
drop view v_ventas;

-- Ventas (igual que 0021 + destino desglosado y aumento al destino al final).
create view v_ventas with (security_invoker = true) as
select v.id, v.especie, v.fecha, v.cliente_id, c.nombre as cliente, c.rfc, v.destino,
       v.tipo_pago, v.empresa_factura_id, e.nombre as empresa_factura, v.factura, v.forma_pago, v.anticipo,
       v.flete_kg, v.merma_kg_caja, v.muertos, v.descuento, v.motivo_descuento, v.notas,
       coalesce(t.cantidad, 0) as cantidad, coalesce(t.kg_brutos, 0) as kg_brutos, coalesce(t.merma_kg, 0) as merma_kg,
       coalesce(t.kg_netos, 0) as kg_netos,
       case when t.cantidad > 0 and t.kg_brutos > 0 then round(t.kg_brutos / t.cantidad, 2) end as peso_promedio,
       coalesce(t.importe, 0) as subtotal,
       coalesce(t.importe, 0) - v.descuento as total,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento) / t.kg_netos, 4) end as precio_promedio_kg,
       case when v.forma_pago = 'contado' then 0
            else greatest(coalesce(t.importe, 0) - v.descuento - v.anticipo - coalesce(pg.pagado, 0), 0) end as saldo,
       t.calidades, t.granjas,
       pf.nombre as capturado_por, v.capturado_en, pm.nombre as modificado_por, v.modificado_en,
       v.folio, v.folio_externo, v.moneda, v.tipo_cambio,
       coalesce(pg.pagado, 0) as pagado, t.productos, t.presentaciones,
       v.flete_caja, coalesce(t.flete, 0) as flete_total,
       coalesce(t.importe, 0) - v.descuento - coalesce(t.flete, 0) as neto,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento - coalesce(t.flete, 0)) / t.kg_netos, 4) end as precio_neto_kg,
       v.destino_colonia, v.destino_ciudad, v.destino_estado, v.aumento_centavos_kg
from ventas v
join clientes c on c.id = v.cliente_id
left join empresas_factura e on e.id = v.empresa_factura_id
left join perfiles pf on pf.id = v.capturado_por
left join perfiles pm on pm.id = v.modificado_por
left join lateral (
  select sum(r.cantidad) as cantidad, sum(r.kg_brutos) as kg_brutos, sum(r.merma_kg) as merma_kg, sum(r.kg_netos) as kg_netos,
         sum(r.importe) as importe, sum(r.flete_importe) as flete,
         string_agg(distinct r.calidad, ', ') as calidades, string_agg(distinct r.granja, ', ') as granjas,
         string_agg(distinct r.producto, ', ') as productos, string_agg(distinct r.presentacion, ', ') as presentaciones
  from v_venta_renglones r where r.venta_id = v.id
) t on true
left join lateral (select sum(a.monto) as pagado from pago_aplicaciones a where a.venta_id = v.id) pg on true;



-- Saldo por cliente y moneda: lo que deben las ventas a crédito menos pagos sin aplicar.
create view v_saldos_clientes with (security_invoker = true) as
with ventas_c as (
  select cliente_id, moneda, count(*) filter (where saldo > 0) as ventas_con_saldo, sum(saldo) as saldo_ventas,
         sum(total) as vendido, min(fecha) filter (where saldo > 0) as venta_mas_antigua
  from v_ventas group by cliente_id, moneda
), pagos_c as (
  select cliente_id, moneda, sum(sin_aplicar) as a_favor, sum(monto) as pagado, max(fecha) as ultimo_pago
  from v_pagos group by cliente_id, moneda
)
select c.id as cliente_id, c.nombre as cliente, c.rfc, coalesce(v.moneda, p.moneda) as moneda,
       coalesce(v.vendido, 0) as vendido, coalesce(p.pagado, 0) as pagado,
       coalesce(v.ventas_con_saldo, 0) as ventas_con_saldo, coalesce(v.saldo_ventas, 0) as saldo_ventas,
       coalesce(p.a_favor, 0) as a_favor, coalesce(v.saldo_ventas, 0) - coalesce(p.a_favor, 0) as saldo,
       v.venta_mas_antigua, p.ultimo_pago
from ventas_c v
full join pagos_c p on p.cliente_id = v.cliente_id and p.moneda = v.moneda
join clientes c on c.id = coalesce(v.cliente_id, p.cliente_id);



-- Guarda encabezado + renglones. Reemplaza la de 0020 (agrega destino desglosado y aumento al destino).
create or replace function guardar_venta(p_venta jsonb, p_renglones jsonb, p_id bigint default null) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_cliente bigint := (p_venta->>'cliente_id')::bigint;
begin
  if v_cliente is null then raise exception 'Elige el cliente'; end if;
  if jsonb_array_length(coalesce(p_renglones, '[]')) = 0 then raise exception 'La venta necesita al menos un renglón'; end if;
  if p_venta->>'tipo_pago' = 'factura' and nullif(p_venta->>'empresa_factura_id', '') is null then
    raise exception 'Elige la razón social con la que se factura';
  end if;
  if exists (select 1 from jsonb_array_elements(p_renglones) x
             where coalesce(x->>'precio_por', 'kg') = 'kg' and coalesce((x->>'kg')::numeric, 0) <= 0) then
    raise exception 'Captura los kg de cada renglón que se cobra por kg';
  end if;

  if p_id is null then
    insert into ventas (especie, fecha, cliente_id, destino, tipo_pago, empresa_factura_id, factura, forma_pago, anticipo,
                        flete_kg, merma_kg_caja, muertos, descuento, motivo_descuento, notas, folio, folio_externo, moneda, tipo_cambio, flete_caja,
                        destino_colonia, destino_ciudad, destino_estado, aumento_centavos_kg)
    values (p_venta->>'especie', (p_venta->>'fecha')::date, v_cliente, nullif(trim(p_venta->>'destino'), ''),
            coalesce(p_venta->>'tipo_pago', 'factura'), nullif(p_venta->>'empresa_factura_id', '')::bigint,
            nullif(trim(p_venta->>'factura'), ''), coalesce(p_venta->>'forma_pago', 'contado'),
            coalesce((p_venta->>'anticipo')::numeric, 0), coalesce((p_venta->>'flete_kg')::numeric, 0),
            coalesce((p_venta->>'merma_kg_caja')::numeric, 0), coalesce((p_venta->>'muertos')::int, 0),
            coalesce((p_venta->>'descuento')::numeric, 0), nullif(trim(p_venta->>'motivo_descuento'), ''),
            nullif(trim(p_venta->>'notas'), ''), nullif(trim(p_venta->>'folio'), ''), nullif(trim(p_venta->>'folio_externo'), ''),
            coalesce(nullif(p_venta->>'moneda', ''), 'MXN'), nullif(p_venta->>'tipo_cambio', '')::numeric,
            coalesce(nullif(p_venta->>'flete_caja', '')::numeric, 0),
            nullif(trim(p_venta->>'destino_colonia'), ''), nullif(trim(p_venta->>'destino_ciudad'), ''),
            nullif(trim(p_venta->>'destino_estado'), ''), nullif(p_venta->>'aumento_centavos_kg', '')::numeric)
    returning id into v_id;
  else
    update ventas set fecha = (p_venta->>'fecha')::date, cliente_id = v_cliente,
        destino = nullif(trim(p_venta->>'destino'), ''), tipo_pago = coalesce(p_venta->>'tipo_pago', 'factura'),
        empresa_factura_id = nullif(p_venta->>'empresa_factura_id', '')::bigint, factura = nullif(trim(p_venta->>'factura'), ''),
        forma_pago = coalesce(p_venta->>'forma_pago', 'contado'), anticipo = coalesce((p_venta->>'anticipo')::numeric, 0),
        flete_kg = coalesce((p_venta->>'flete_kg')::numeric, 0), merma_kg_caja = coalesce((p_venta->>'merma_kg_caja')::numeric, 0),
        muertos = coalesce((p_venta->>'muertos')::int, 0), descuento = coalesce((p_venta->>'descuento')::numeric, 0),
        motivo_descuento = nullif(trim(p_venta->>'motivo_descuento'), ''), notas = nullif(trim(p_venta->>'notas'), ''),
        folio = nullif(trim(p_venta->>'folio'), ''), folio_externo = nullif(trim(p_venta->>'folio_externo'), ''),
        moneda = coalesce(nullif(p_venta->>'moneda', ''), 'MXN'), tipo_cambio = nullif(p_venta->>'tipo_cambio', '')::numeric,
        flete_caja = coalesce(nullif(p_venta->>'flete_caja', '')::numeric, 0),
        destino_colonia = nullif(trim(p_venta->>'destino_colonia'), ''), destino_ciudad = nullif(trim(p_venta->>'destino_ciudad'), ''),
        destino_estado = nullif(trim(p_venta->>'destino_estado'), ''), aumento_centavos_kg = nullif(p_venta->>'aumento_centavos_kg', '')::numeric
      where id = p_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró la venta % o no tienes permiso para cambiarla', p_id; end if;
    delete from venta_renglones where venta_id = v_id;
  end if;

  insert into venta_renglones (venta_id, granja_id, calidad, cantidad, kg, precio_kg, presentacion, producto_id, precio_por, merma_kg)
  select v_id, nullif(x->>'granja_id', '')::bigint, nullif(trim(x->>'calidad'), ''),
         coalesce((x->>'cantidad')::numeric, 0), nullif(x->>'kg', '')::numeric, (x->>'precio_kg')::numeric,
         nullif(trim(x->>'presentacion'), ''), nullif(x->>'producto_id', '')::bigint,
         coalesce(nullif(x->>'precio_por', ''), 'kg'), nullif(x->>'merma_kg', '')::numeric
  from jsonb_array_elements(p_renglones) x;
  return v_id;
end $$;


-- >>>>>>>>>> migrations/0023_sorgo_maiz_pagos.sql
-- =====================================================================
-- 0023_sorgo_maiz_pagos.sql — Sorgo y maíz como almacenes separados; corrección de pagos de clientes
--
--   Sorgo: zona roja 4,800 t + 10 t de tolvas. Maíz: zona amarilla 1,350 t + 10 t de tolvas.
--   Pagos: quien captura ventas puede eliminar un pago registrado por error (antes solo el administrador).
--   Repetible: se puede volver a correr.
-- =====================================================================

update grupos_almacen set nombre = 'Sorgo', capacidad_planta_kg = 4800000, capacidad_tolvas_kg = 10000,
       notas = 'Zona roja 4,800 t + 10 t en tolvas de la planta.'
where nombre = 'Sorgo y maíz';

update grupos_almacen set orden = orden + 1 where orden >= 2 and nombre <> 'Maíz'
  and not exists (select 1 from grupos_almacen where nombre = 'Maíz');

insert into grupos_almacen (nombre, capacidad_planta_kg, capacidad_tolvas_kg, orden, notas)
values ('Maíz', 1350000, 10000, 2, 'Zona amarilla 1,350 t + 10 t en tolvas de la planta.')
on conflict (nombre) do nothing;

-- Las materias primas de maíz que estaban en el grupo compartido pasan al grupo Maíz.
update materias_primas mp set grupo_almacen_id = (select id from grupos_almacen where nombre = 'Maíz')
where mp.grupo_almacen_id = (select id from grupos_almacen where nombre = 'Sorgo')
  and nombre_normalizado(mp.nombre) like '%MAIZ%';

drop policy if exists borrar_ventas on pagos_cliente;
create policy borrar_ventas on pagos_cliente for delete to authenticated using (puede_capturar('ventas'));

-- >>>>>>>>>> migrations/0024_pesada_unica_facturas.sql
-- =====================================================================
-- 0024_pesada_unica_facturas.sql — Huevo con una sola pesada; varias facturas por venta
--
--   kg_bascula: peso bruto de toda la venta (cajas de varias granjas en una pesada). Se reparte entre renglones
--   en proporción a las cajas; kg netos = brutos − cajas × merma por caja.
--   venta_facturas: una venta puede llevar varias facturas (número, razón social, monto, fecha).
-- =====================================================================

alter table ventas add column kg_bascula numeric(12,2) check (kg_bascula > 0);

create table venta_facturas (
  id                  bigint generated always as identity primary key,
  venta_id            bigint not null references ventas (id) on delete cascade,
  numero              text not null,
  empresa_factura_id  bigint references empresas_factura (id),
  monto               numeric(14,2) check (monto >= 0),
  fecha               date
);
create index on venta_facturas (venta_id);
select aplicar_seguridad('venta_facturas', 'ventas');
create policy borrar_ventas on venta_facturas for delete to authenticated using (puede_capturar('ventas'));

-- Las facturas ya capturadas pasan a la lista.
insert into venta_facturas (venta_id, numero, empresa_factura_id)
select id, factura, empresa_factura_id from ventas where nullif(trim(factura), '') is not null;

drop view v_saldos_clientes;
drop view v_ventas;

-- Ventas (igual que 0022 + pesada única y facturas al final).
create view v_ventas with (security_invoker = true) as
select v.id, v.especie, v.fecha, v.cliente_id, c.nombre as cliente, c.rfc, v.destino,
       v.tipo_pago, v.empresa_factura_id, e.nombre as empresa_factura, v.factura, v.forma_pago, v.anticipo,
       v.flete_kg, v.merma_kg_caja, v.muertos, v.descuento, v.motivo_descuento, v.notas,
       coalesce(t.cantidad, 0) as cantidad, coalesce(t.kg_brutos, 0) as kg_brutos, coalesce(t.merma_kg, 0) as merma_kg,
       coalesce(t.kg_netos, 0) as kg_netos,
       case when t.cantidad > 0 and t.kg_brutos > 0 then round(t.kg_brutos / t.cantidad, 2) end as peso_promedio,
       coalesce(t.importe, 0) as subtotal,
       coalesce(t.importe, 0) - v.descuento as total,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento) / t.kg_netos, 4) end as precio_promedio_kg,
       case when v.forma_pago = 'contado' then 0
            else greatest(coalesce(t.importe, 0) - v.descuento - v.anticipo - coalesce(pg.pagado, 0), 0) end as saldo,
       t.calidades, t.granjas,
       pf.nombre as capturado_por, v.capturado_en, pm.nombre as modificado_por, v.modificado_en,
       v.folio, v.folio_externo, v.moneda, v.tipo_cambio,
       coalesce(pg.pagado, 0) as pagado, t.productos, t.presentaciones,
       v.flete_caja, coalesce(t.flete, 0) as flete_total,
       coalesce(t.importe, 0) - v.descuento - coalesce(t.flete, 0) as neto,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento - coalesce(t.flete, 0)) / t.kg_netos, 4) end as precio_neto_kg,
       v.destino_colonia, v.destino_ciudad, v.destino_estado, v.aumento_centavos_kg,
       v.kg_bascula, coalesce(fc.n, 0) as num_facturas, fc.facturas, fc.facturado
from ventas v
join clientes c on c.id = v.cliente_id
left join empresas_factura e on e.id = v.empresa_factura_id
left join perfiles pf on pf.id = v.capturado_por
left join perfiles pm on pm.id = v.modificado_por
left join lateral (
  select sum(r.cantidad) as cantidad, sum(r.kg_brutos) as kg_brutos, sum(r.merma_kg) as merma_kg, sum(r.kg_netos) as kg_netos,
         sum(r.importe) as importe, sum(r.flete_importe) as flete,
         string_agg(distinct r.calidad, ', ') as calidades, string_agg(distinct r.granja, ', ') as granjas,
         string_agg(distinct r.producto, ', ') as productos, string_agg(distinct r.presentacion, ', ') as presentaciones
  from v_venta_renglones r where r.venta_id = v.id
) t on true
left join lateral (select sum(a.monto) as pagado from pago_aplicaciones a where a.venta_id = v.id) pg on true
left join lateral (
  select count(*) as n, sum(f.monto) as facturado,
         string_agg(f.numero || coalesce(' · ' || ef.nombre, ''), ', ' order by f.id) as facturas
  from venta_facturas f left join empresas_factura ef on ef.id = f.empresa_factura_id where f.venta_id = v.id
) fc on true;




-- Saldo por cliente y moneda: lo que deben las ventas a crédito menos pagos sin aplicar.
create view v_saldos_clientes with (security_invoker = true) as
with ventas_c as (
  select cliente_id, moneda, count(*) filter (where saldo > 0) as ventas_con_saldo, sum(saldo) as saldo_ventas,
         sum(total) as vendido, min(fecha) filter (where saldo > 0) as venta_mas_antigua
  from v_ventas group by cliente_id, moneda
), pagos_c as (
  select cliente_id, moneda, sum(sin_aplicar) as a_favor, sum(monto) as pagado, max(fecha) as ultimo_pago
  from v_pagos group by cliente_id, moneda
)
select c.id as cliente_id, c.nombre as cliente, c.rfc, coalesce(v.moneda, p.moneda) as moneda,
       coalesce(v.vendido, 0) as vendido, coalesce(p.pagado, 0) as pagado,
       coalesce(v.ventas_con_saldo, 0) as ventas_con_saldo, coalesce(v.saldo_ventas, 0) as saldo_ventas,
       coalesce(p.a_favor, 0) as a_favor, coalesce(v.saldo_ventas, 0) - coalesce(p.a_favor, 0) as saldo,
       v.venta_mas_antigua, p.ultimo_pago
from ventas_c v
full join pagos_c p on p.cliente_id = v.cliente_id and p.moneda = v.moneda
join clientes c on c.id = coalesce(v.cliente_id, p.cliente_id);




-- Guarda encabezado + renglones + facturas. Reemplaza la de 0022 (agrega pesada única y facturas).
create or replace function guardar_venta(p_venta jsonb, p_renglones jsonb, p_id bigint default null) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_cliente bigint := (p_venta->>'cliente_id')::bigint;
  v_bascula numeric := nullif(p_venta->>'kg_bascula', '')::numeric;
  v_cajas numeric;
begin
  -- Pesada única (huevo): los kg de báscula se reparten entre los renglones en proporción a las cajas;
  -- el último renglón se lleva el redondeo para que la suma sea exacta.
  if v_bascula > 0 then
    select sum(coalesce((x->>'cantidad')::numeric, 0)) into v_cajas from jsonb_array_elements(p_renglones) x;
    if coalesce(v_cajas, 0) <= 0 then raise exception 'Captura las cajas de cada renglón para repartir la pesada'; end if;
    select jsonb_agg(case when n = total_n then x || jsonb_build_object('kg', v_bascula - acumulado)
                          else x || jsonb_build_object('kg', kg) end order by n)
      into p_renglones
    from (select x, n, count(*) over () as total_n, kg,
                 coalesce(sum(kg) over (order by n rows between unbounded preceding and 1 preceding), 0) as acumulado
          from (select x, n, round(v_bascula * coalesce((x->>'cantidad')::numeric, 0) / v_cajas, 2) as kg
                from jsonb_array_elements(p_renglones) with ordinality as e (x, n)) a) b;
  end if;
  if v_cliente is null then raise exception 'Elige el cliente'; end if;
  if jsonb_array_length(coalesce(p_renglones, '[]')) = 0 then raise exception 'La venta necesita al menos un renglón'; end if;
  if p_venta->>'tipo_pago' = 'factura' and nullif(p_venta->>'empresa_factura_id', '') is null then
    raise exception 'Elige la razón social con la que se factura';
  end if;
  if exists (select 1 from jsonb_array_elements(p_renglones) x
             where coalesce(x->>'precio_por', 'kg') = 'kg' and coalesce((x->>'kg')::numeric, 0) <= 0) then
    raise exception 'Captura los kg de cada renglón que se cobra por kg';
  end if;

  if p_id is null then
    insert into ventas (especie, fecha, cliente_id, destino, tipo_pago, empresa_factura_id, factura, forma_pago, anticipo,
                        flete_kg, merma_kg_caja, muertos, descuento, motivo_descuento, notas, folio, folio_externo, moneda, tipo_cambio, flete_caja,
                        destino_colonia, destino_ciudad, destino_estado, aumento_centavos_kg, kg_bascula)
    values (p_venta->>'especie', (p_venta->>'fecha')::date, v_cliente, nullif(trim(p_venta->>'destino'), ''),
            coalesce(p_venta->>'tipo_pago', 'factura'), nullif(p_venta->>'empresa_factura_id', '')::bigint,
            nullif(trim(p_venta->>'factura'), ''), coalesce(p_venta->>'forma_pago', 'contado'),
            coalesce((p_venta->>'anticipo')::numeric, 0), coalesce((p_venta->>'flete_kg')::numeric, 0),
            coalesce((p_venta->>'merma_kg_caja')::numeric, 0), coalesce((p_venta->>'muertos')::int, 0),
            coalesce((p_venta->>'descuento')::numeric, 0), nullif(trim(p_venta->>'motivo_descuento'), ''),
            nullif(trim(p_venta->>'notas'), ''), nullif(trim(p_venta->>'folio'), ''), nullif(trim(p_venta->>'folio_externo'), ''),
            coalesce(nullif(p_venta->>'moneda', ''), 'MXN'), nullif(p_venta->>'tipo_cambio', '')::numeric,
            coalesce(nullif(p_venta->>'flete_caja', '')::numeric, 0),
            nullif(trim(p_venta->>'destino_colonia'), ''), nullif(trim(p_venta->>'destino_ciudad'), ''),
            nullif(trim(p_venta->>'destino_estado'), ''), nullif(p_venta->>'aumento_centavos_kg', '')::numeric,
            v_bascula)
    returning id into v_id;
  else
    update ventas set fecha = (p_venta->>'fecha')::date, cliente_id = v_cliente,
        destino = nullif(trim(p_venta->>'destino'), ''), tipo_pago = coalesce(p_venta->>'tipo_pago', 'factura'),
        empresa_factura_id = nullif(p_venta->>'empresa_factura_id', '')::bigint, factura = nullif(trim(p_venta->>'factura'), ''),
        forma_pago = coalesce(p_venta->>'forma_pago', 'contado'), anticipo = coalesce((p_venta->>'anticipo')::numeric, 0),
        flete_kg = coalesce((p_venta->>'flete_kg')::numeric, 0), merma_kg_caja = coalesce((p_venta->>'merma_kg_caja')::numeric, 0),
        muertos = coalesce((p_venta->>'muertos')::int, 0), descuento = coalesce((p_venta->>'descuento')::numeric, 0),
        motivo_descuento = nullif(trim(p_venta->>'motivo_descuento'), ''), notas = nullif(trim(p_venta->>'notas'), ''),
        folio = nullif(trim(p_venta->>'folio'), ''), folio_externo = nullif(trim(p_venta->>'folio_externo'), ''),
        moneda = coalesce(nullif(p_venta->>'moneda', ''), 'MXN'), tipo_cambio = nullif(p_venta->>'tipo_cambio', '')::numeric,
        flete_caja = coalesce(nullif(p_venta->>'flete_caja', '')::numeric, 0),
        destino_colonia = nullif(trim(p_venta->>'destino_colonia'), ''), destino_ciudad = nullif(trim(p_venta->>'destino_ciudad'), ''),
        destino_estado = nullif(trim(p_venta->>'destino_estado'), ''), aumento_centavos_kg = nullif(p_venta->>'aumento_centavos_kg', '')::numeric,
        kg_bascula = v_bascula
      where id = p_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró la venta % o no tienes permiso para cambiarla', p_id; end if;
    delete from venta_renglones where venta_id = v_id;
  end if;

  insert into venta_renglones (venta_id, granja_id, calidad, cantidad, kg, precio_kg, presentacion, producto_id, precio_por, merma_kg)
  select v_id, nullif(x->>'granja_id', '')::bigint, nullif(trim(x->>'calidad'), ''),
         coalesce((x->>'cantidad')::numeric, 0), nullif(x->>'kg', '')::numeric, (x->>'precio_kg')::numeric,
         nullif(trim(x->>'presentacion'), ''), nullif(x->>'producto_id', '')::bigint,
         coalesce(nullif(x->>'precio_por', ''), 'kg'), nullif(x->>'merma_kg', '')::numeric
  from jsonb_array_elements(p_renglones) x;

  -- Facturas: si se manda la lista, reemplaza las de la venta; ventas.factura guarda los números juntos.
  if p_venta ? 'facturas' then
    delete from venta_facturas where venta_id = v_id;
    insert into venta_facturas (venta_id, numero, empresa_factura_id, monto, fecha)
    select v_id, trim(f->>'numero'),
           coalesce(nullif(f->>'empresa_factura_id', '')::bigint, nullif(p_venta->>'empresa_factura_id', '')::bigint),
           nullif(f->>'monto', '')::numeric, nullif(f->>'fecha', '')::date
    from jsonb_array_elements(p_venta->'facturas') f
    where nullif(trim(f->>'numero'), '') is not null;
    update ventas set factura = (select string_agg(numero, ', ' order by id) from venta_facturas where venta_id = v_id) where id = v_id;
  end if;
  return v_id;
end $$;


-- >>>>>>>>>> migrations/0025_cuentas_bancarias.sql
-- =====================================================================
-- 0025_cuentas_bancarias.sql — A qué cuenta se depositó o transfirió cada cobro
--
--   cuentas_bancarias: catálogo de cuentas de la empresa (banco, terminación, razón social, moneda) más la caja de
--   efectivo. Se registra la cuenta en la venta (cobro de contado o anticipo) y en cada pago de cliente.
--   v_depositos junta todos los cobros por cuenta: base para la futura sección de Bancos.
-- =====================================================================

create table cuentas_bancarias (
  id                  bigint generated always as identity primary key,
  nombre              text not null unique,           -- cómo se le conoce: "BBVA Pecuaria 1234", "Caja efectivo"
  tipo                text not null default 'banco' check (tipo in ('banco', 'caja')),
  banco               text,
  numero              text,                            -- terminación o CLABE
  empresa_factura_id  bigint references empresas_factura (id),
  moneda              text not null default 'MXN' check (moneda in ('MXN', 'USD')),
  activa              boolean not null default true,
  creado_por          uuid references auth.users (id),
  creado_en           timestamptz default now()
);
select aplicar_seguridad('cuentas_bancarias', 'catalogos');
create policy capturar_ventas on cuentas_bancarias for insert to authenticated with check (puede_capturar('ventas'));
insert into cuentas_bancarias (nombre, tipo) values ('CAJA (EFECTIVO)', 'caja') on conflict (nombre) do nothing;

alter table ventas add column cuenta_id bigint references cuentas_bancarias (id);
alter table pagos_cliente add column cuenta_id bigint references cuentas_bancarias (id);

drop view v_saldos_clientes;
drop view v_pagos;
drop view v_ventas;

-- Ventas (igual que 0024 + cuenta de depósito al final).
create view v_ventas with (security_invoker = true) as
select v.id, v.especie, v.fecha, v.cliente_id, c.nombre as cliente, c.rfc, v.destino,
       v.tipo_pago, v.empresa_factura_id, e.nombre as empresa_factura, v.factura, v.forma_pago, v.anticipo,
       v.flete_kg, v.merma_kg_caja, v.muertos, v.descuento, v.motivo_descuento, v.notas,
       coalesce(t.cantidad, 0) as cantidad, coalesce(t.kg_brutos, 0) as kg_brutos, coalesce(t.merma_kg, 0) as merma_kg,
       coalesce(t.kg_netos, 0) as kg_netos,
       case when t.cantidad > 0 and t.kg_brutos > 0 then round(t.kg_brutos / t.cantidad, 2) end as peso_promedio,
       coalesce(t.importe, 0) as subtotal,
       coalesce(t.importe, 0) - v.descuento as total,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento) / t.kg_netos, 4) end as precio_promedio_kg,
       case when v.forma_pago = 'contado' then 0
            else greatest(coalesce(t.importe, 0) - v.descuento - v.anticipo - coalesce(pg.pagado, 0), 0) end as saldo,
       t.calidades, t.granjas,
       pf.nombre as capturado_por, v.capturado_en, pm.nombre as modificado_por, v.modificado_en,
       v.folio, v.folio_externo, v.moneda, v.tipo_cambio,
       coalesce(pg.pagado, 0) as pagado, t.productos, t.presentaciones,
       v.flete_caja, coalesce(t.flete, 0) as flete_total,
       coalesce(t.importe, 0) - v.descuento - coalesce(t.flete, 0) as neto,
       case when t.kg_netos > 0 then round((coalesce(t.importe, 0) - v.descuento - coalesce(t.flete, 0)) / t.kg_netos, 4) end as precio_neto_kg,
       v.destino_colonia, v.destino_ciudad, v.destino_estado, v.aumento_centavos_kg,
       v.kg_bascula, coalesce(fc.n, 0) as num_facturas, fc.facturas, fc.facturado,
       v.cuenta_id, cb.nombre as cuenta
from ventas v
join clientes c on c.id = v.cliente_id
left join empresas_factura e on e.id = v.empresa_factura_id
left join cuentas_bancarias cb on cb.id = v.cuenta_id
left join perfiles pf on pf.id = v.capturado_por
left join perfiles pm on pm.id = v.modificado_por
left join lateral (
  select sum(r.cantidad) as cantidad, sum(r.kg_brutos) as kg_brutos, sum(r.merma_kg) as merma_kg, sum(r.kg_netos) as kg_netos,
         sum(r.importe) as importe, sum(r.flete_importe) as flete,
         string_agg(distinct r.calidad, ', ') as calidades, string_agg(distinct r.granja, ', ') as granjas,
         string_agg(distinct r.producto, ', ') as productos, string_agg(distinct r.presentacion, ', ') as presentaciones
  from v_venta_renglones r where r.venta_id = v.id
) t on true
left join lateral (select sum(a.monto) as pagado from pago_aplicaciones a where a.venta_id = v.id) pg on true
left join lateral (
  select count(*) as n, sum(f.monto) as facturado,
         string_agg(f.numero || coalesce(' · ' || ef.nombre, ''), ', ' order by f.id) as facturas
  from venta_facturas f left join empresas_factura ef on ef.id = f.empresa_factura_id where f.venta_id = v.id
) fc on true;





create view v_pagos with (security_invoker = true) as
select p.id, p.cliente_id, c.nombre as cliente, p.fecha, p.monto, p.moneda, p.tipo_cambio, p.forma, p.banco, p.referencia,
       p.factura, p.notas, coalesce(a.aplicado, 0) as aplicado, p.monto - coalesce(a.aplicado, 0) as sin_aplicar,
       a.ventas, pf.nombre as capturado_por, p.capturado_en,
       p.cuenta_id, cb.nombre as cuenta
from pagos_cliente p
join clientes c on c.id = p.cliente_id
left join cuentas_bancarias cb on cb.id = p.cuenta_id
left join perfiles pf on pf.id = p.capturado_por
left join lateral (
  select sum(pa.monto) as aplicado,
         string_agg(coalesce(v.folio, to_char(v.fecha, 'DD/MM')) || ' (' || to_char(pa.monto, 'FM999,999,990.00') || ')', ', ' order by v.fecha) as ventas
  from pago_aplicaciones pa join ventas v on v.id = pa.venta_id where pa.pago_id = p.id
) a on true;


-- Saldo por cliente y moneda: lo que deben las ventas a crédito menos pagos sin aplicar.
create view v_saldos_clientes with (security_invoker = true) as
with ventas_c as (
  select cliente_id, moneda, count(*) filter (where saldo > 0) as ventas_con_saldo, sum(saldo) as saldo_ventas,
         sum(total) as vendido, min(fecha) filter (where saldo > 0) as venta_mas_antigua
  from v_ventas group by cliente_id, moneda
), pagos_c as (
  select cliente_id, moneda, sum(sin_aplicar) as a_favor, sum(monto) as pagado, max(fecha) as ultimo_pago
  from v_pagos group by cliente_id, moneda
)
select c.id as cliente_id, c.nombre as cliente, c.rfc, coalesce(v.moneda, p.moneda) as moneda,
       coalesce(v.vendido, 0) as vendido, coalesce(p.pagado, 0) as pagado,
       coalesce(v.ventas_con_saldo, 0) as ventas_con_saldo, coalesce(v.saldo_ventas, 0) as saldo_ventas,
       coalesce(p.a_favor, 0) as a_favor, coalesce(v.saldo_ventas, 0) - coalesce(p.a_favor, 0) as saldo,
       v.venta_mas_antigua, p.ultimo_pago
from ventas_c v
full join pagos_c p on p.cliente_id = v.cliente_id and p.moneda = v.moneda
join clientes c on c.id = coalesce(v.cliente_id, p.cliente_id);





-- Cobros por cuenta: ventas de contado (total), anticipos de ventas a crédito y pagos de clientes.
create view v_depositos with (security_invoker = true) as
select 'venta' as origen, v.id as origen_id, v.fecha, v.cliente_id, v.cliente, v.especie, v.folio,
       v.total as monto, v.moneda, v.cuenta_id, v.cuenta, 'Venta de contado' as concepto
from v_ventas v where v.forma_pago = 'contado' and v.total > 0
union all
select 'anticipo', v.id, v.fecha, v.cliente_id, v.cliente, v.especie, v.folio,
       v.anticipo, v.moneda, v.cuenta_id, v.cuenta, 'Anticipo de venta a crédito'
from v_ventas v where v.forma_pago = 'credito' and v.anticipo > 0
union all
select 'pago', p.id, p.fecha, p.cliente_id, p.cliente, null, p.referencia,
       p.monto, p.moneda, p.cuenta_id, p.cuenta, 'Pago de cliente'
from v_pagos p;

-- Guarda encabezado + renglones + facturas. Reemplaza la de 0024 (agrega cuenta de depósito).
create or replace function guardar_venta(p_venta jsonb, p_renglones jsonb, p_id bigint default null) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_cliente bigint := (p_venta->>'cliente_id')::bigint;
  v_bascula numeric := nullif(p_venta->>'kg_bascula', '')::numeric;
  v_cajas numeric;
begin
  -- Pesada única (huevo): los kg de báscula se reparten entre los renglones en proporción a las cajas;
  -- el último renglón se lleva el redondeo para que la suma sea exacta.
  if v_bascula > 0 then
    select sum(coalesce((x->>'cantidad')::numeric, 0)) into v_cajas from jsonb_array_elements(p_renglones) x;
    if coalesce(v_cajas, 0) <= 0 then raise exception 'Captura las cajas de cada renglón para repartir la pesada'; end if;
    select jsonb_agg(case when n = total_n then x || jsonb_build_object('kg', v_bascula - acumulado)
                          else x || jsonb_build_object('kg', kg) end order by n)
      into p_renglones
    from (select x, n, count(*) over () as total_n, kg,
                 coalesce(sum(kg) over (order by n rows between unbounded preceding and 1 preceding), 0) as acumulado
          from (select x, n, round(v_bascula * coalesce((x->>'cantidad')::numeric, 0) / v_cajas, 2) as kg
                from jsonb_array_elements(p_renglones) with ordinality as e (x, n)) a) b;
  end if;
  if v_cliente is null then raise exception 'Elige el cliente'; end if;
  if jsonb_array_length(coalesce(p_renglones, '[]')) = 0 then raise exception 'La venta necesita al menos un renglón'; end if;
  if p_venta->>'tipo_pago' = 'factura' and nullif(p_venta->>'empresa_factura_id', '') is null then
    raise exception 'Elige la razón social con la que se factura';
  end if;
  if exists (select 1 from jsonb_array_elements(p_renglones) x
             where coalesce(x->>'precio_por', 'kg') = 'kg' and coalesce((x->>'kg')::numeric, 0) <= 0) then
    raise exception 'Captura los kg de cada renglón que se cobra por kg';
  end if;

  if p_id is null then
    insert into ventas (especie, fecha, cliente_id, destino, tipo_pago, empresa_factura_id, factura, forma_pago, anticipo,
                        flete_kg, merma_kg_caja, muertos, descuento, motivo_descuento, notas, folio, folio_externo, moneda, tipo_cambio, flete_caja,
                        destino_colonia, destino_ciudad, destino_estado, aumento_centavos_kg, kg_bascula, cuenta_id)
    values (p_venta->>'especie', (p_venta->>'fecha')::date, v_cliente, nullif(trim(p_venta->>'destino'), ''),
            coalesce(p_venta->>'tipo_pago', 'factura'), nullif(p_venta->>'empresa_factura_id', '')::bigint,
            nullif(trim(p_venta->>'factura'), ''), coalesce(p_venta->>'forma_pago', 'contado'),
            coalesce((p_venta->>'anticipo')::numeric, 0), coalesce((p_venta->>'flete_kg')::numeric, 0),
            coalesce((p_venta->>'merma_kg_caja')::numeric, 0), coalesce((p_venta->>'muertos')::int, 0),
            coalesce((p_venta->>'descuento')::numeric, 0), nullif(trim(p_venta->>'motivo_descuento'), ''),
            nullif(trim(p_venta->>'notas'), ''), nullif(trim(p_venta->>'folio'), ''), nullif(trim(p_venta->>'folio_externo'), ''),
            coalesce(nullif(p_venta->>'moneda', ''), 'MXN'), nullif(p_venta->>'tipo_cambio', '')::numeric,
            coalesce(nullif(p_venta->>'flete_caja', '')::numeric, 0),
            nullif(trim(p_venta->>'destino_colonia'), ''), nullif(trim(p_venta->>'destino_ciudad'), ''),
            nullif(trim(p_venta->>'destino_estado'), ''), nullif(p_venta->>'aumento_centavos_kg', '')::numeric,
            v_bascula, nullif(p_venta->>'cuenta_id', '')::bigint)
    returning id into v_id;
  else
    update ventas set fecha = (p_venta->>'fecha')::date, cliente_id = v_cliente,
        destino = nullif(trim(p_venta->>'destino'), ''), tipo_pago = coalesce(p_venta->>'tipo_pago', 'factura'),
        empresa_factura_id = nullif(p_venta->>'empresa_factura_id', '')::bigint, factura = nullif(trim(p_venta->>'factura'), ''),
        forma_pago = coalesce(p_venta->>'forma_pago', 'contado'), anticipo = coalesce((p_venta->>'anticipo')::numeric, 0),
        flete_kg = coalesce((p_venta->>'flete_kg')::numeric, 0), merma_kg_caja = coalesce((p_venta->>'merma_kg_caja')::numeric, 0),
        muertos = coalesce((p_venta->>'muertos')::int, 0), descuento = coalesce((p_venta->>'descuento')::numeric, 0),
        motivo_descuento = nullif(trim(p_venta->>'motivo_descuento'), ''), notas = nullif(trim(p_venta->>'notas'), ''),
        folio = nullif(trim(p_venta->>'folio'), ''), folio_externo = nullif(trim(p_venta->>'folio_externo'), ''),
        moneda = coalesce(nullif(p_venta->>'moneda', ''), 'MXN'), tipo_cambio = nullif(p_venta->>'tipo_cambio', '')::numeric,
        flete_caja = coalesce(nullif(p_venta->>'flete_caja', '')::numeric, 0),
        destino_colonia = nullif(trim(p_venta->>'destino_colonia'), ''), destino_ciudad = nullif(trim(p_venta->>'destino_ciudad'), ''),
        destino_estado = nullif(trim(p_venta->>'destino_estado'), ''), aumento_centavos_kg = nullif(p_venta->>'aumento_centavos_kg', '')::numeric,
        kg_bascula = v_bascula, cuenta_id = nullif(p_venta->>'cuenta_id', '')::bigint
      where id = p_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró la venta % o no tienes permiso para cambiarla', p_id; end if;
    delete from venta_renglones where venta_id = v_id;
  end if;

  insert into venta_renglones (venta_id, granja_id, calidad, cantidad, kg, precio_kg, presentacion, producto_id, precio_por, merma_kg)
  select v_id, nullif(x->>'granja_id', '')::bigint, nullif(trim(x->>'calidad'), ''),
         coalesce((x->>'cantidad')::numeric, 0), nullif(x->>'kg', '')::numeric, (x->>'precio_kg')::numeric,
         nullif(trim(x->>'presentacion'), ''), nullif(x->>'producto_id', '')::bigint,
         coalesce(nullif(x->>'precio_por', ''), 'kg'), nullif(x->>'merma_kg', '')::numeric
  from jsonb_array_elements(p_renglones) x;

  -- Facturas: si se manda la lista, reemplaza las de la venta; ventas.factura guarda los números juntos.
  if p_venta ? 'facturas' then
    delete from venta_facturas where venta_id = v_id;
    insert into venta_facturas (venta_id, numero, empresa_factura_id, monto, fecha)
    select v_id, trim(f->>'numero'),
           coalesce(nullif(f->>'empresa_factura_id', '')::bigint, nullif(p_venta->>'empresa_factura_id', '')::bigint),
           nullif(f->>'monto', '')::numeric, nullif(f->>'fecha', '')::date
    from jsonb_array_elements(p_venta->'facturas') f
    where nullif(trim(f->>'numero'), '') is not null;
    update ventas set factura = (select string_agg(numero, ', ' order by id) from venta_facturas where venta_id = v_id) where id = v_id;
  end if;
  return v_id;
end $$;


-- Registra (o corrige) un pago. Reemplaza la de 0019 (agrega cuenta de depósito).
create or replace function registrar_pago(p_pago jsonb, p_aplicaciones jsonb default '[]', p_id bigint default null) returns bigint
language plpgsql as $$
declare
  v_id bigint;
  v_cliente bigint := (p_pago->>'cliente_id')::bigint;
  v_moneda text := coalesce(nullif(p_pago->>'moneda', ''), 'MXN');
  v_monto numeric := (p_pago->>'monto')::numeric;
  x jsonb;
  v record;
begin
  if v_cliente is null then raise exception 'Elige el cliente'; end if;
  if coalesce(v_monto, 0) <= 0 then raise exception 'El monto del pago debe ser mayor a cero'; end if;
  if (select coalesce(sum((a->>'monto')::numeric), 0) from jsonb_array_elements(coalesce(p_aplicaciones, '[]')) a) > v_monto + 0.005 then
    raise exception 'Lo aplicado a las ventas es mayor que el pago';
  end if;

  if p_id is null then
    insert into pagos_cliente (cliente_id, fecha, monto, moneda, tipo_cambio, forma, banco, referencia, factura, notas, cuenta_id)
    values (v_cliente, (p_pago->>'fecha')::date, v_monto, v_moneda, nullif(p_pago->>'tipo_cambio', '')::numeric,
            coalesce(nullif(p_pago->>'forma', ''), 'transferencia'), nullif(trim(p_pago->>'banco'), ''),
            nullif(trim(p_pago->>'referencia'), ''), nullif(trim(p_pago->>'factura'), ''), nullif(trim(p_pago->>'notas'), ''),
            nullif(p_pago->>'cuenta_id', '')::bigint)
    returning id into v_id;
  else
    update pagos_cliente set cliente_id = v_cliente, fecha = (p_pago->>'fecha')::date, monto = v_monto, moneda = v_moneda,
        tipo_cambio = nullif(p_pago->>'tipo_cambio', '')::numeric, forma = coalesce(nullif(p_pago->>'forma', ''), 'transferencia'),
        banco = nullif(trim(p_pago->>'banco'), ''), referencia = nullif(trim(p_pago->>'referencia'), ''),
        factura = nullif(trim(p_pago->>'factura'), ''), notas = nullif(trim(p_pago->>'notas'), ''),
        cuenta_id = nullif(p_pago->>'cuenta_id', '')::bigint
      where id = p_id returning id into v_id;
    if v_id is null then raise exception 'No se encontró el pago % o no tienes permiso para cambiarlo', p_id; end if;
    delete from pago_aplicaciones where pago_id = v_id;
  end if;

  for x in select * from jsonb_array_elements(coalesce(p_aplicaciones, '[]')) loop
    select vv.id, vv.cliente_id, vv.moneda, vv.saldo, vv.folio, vv.fecha into v from v_ventas vv where vv.id = (x->>'venta_id')::bigint;
    if v.id is null then raise exception 'No se encontró la venta %', x->>'venta_id'; end if;
    if v.cliente_id <> v_cliente then raise exception 'La venta del % es de otro cliente', to_char(v.fecha, 'DD/MM/YYYY'); end if;
    if v.moneda <> v_moneda then raise exception 'La venta del % es en %, el pago en %', to_char(v.fecha, 'DD/MM/YYYY'), v.moneda, v_moneda; end if;
    if (x->>'monto')::numeric > v.saldo + 0.005 then
      raise exception 'A la venta del % solo le quedan % de saldo', to_char(v.fecha, 'DD/MM/YYYY'), v.saldo;
    end if;
    insert into pago_aplicaciones (pago_id, venta_id, monto) values (v_id, v.id, (x->>'monto')::numeric);
  end loop;
  return v_id;
end $$;

-- >>>>>>>>>> migrations/0026_permisos_ver.sql
-- =====================================================================
-- 0026_permisos_ver.sql — Permisos para VER y para CAPTURAR, por módulo y por tipo de venta
--
--   Antes: todo usuario activo veía todo; los módulos marcados eran los que podía capturar.
--   Ahora cada permiso tiene nivel 'ver' o 'capturar' (capturar incluye ver) y nadie ve un módulo que el
--   administrador no le haya dado. El administrador y el director ven todo; el administrador captura todo.
--   Permisos: avisos (Inicio), planta, granjas, ventas_huevo, ventas_cerdo, ventas_ganado, ventas_borrego,
--   ventas_berries, ventas_general, cobranza. Los catálogos generales (granjas, clientes, razones sociales,
--   cuentas) los siguen leyendo todos porque los formularios los usan.
--   Quien tenía el permiso 'ventas' recibe todos los tipos de venta y cobranza; todos los usuarios que ya
--   existían conservan ver planta, granjas y avisos (como hasta hoy). Repetible.
-- =====================================================================

alter table modulos add column if not exists activo boolean not null default true;
alter table modulos add column if not exists grupo text;

insert into modulos (codigo, nombre, orden, grupo) values
  ('avisos',         'Avisos en Inicio',      0, 'General'),
  ('granjas',        'Granjas y casetas',     1, 'General'),
  ('ventas_huevo',   'Ventas de huevo',      20, 'Ventas'),
  ('ventas_cerdo',   'Ventas de cerdo',      21, 'Ventas'),
  ('ventas_ganado',  'Ventas de ganado',     22, 'Ventas'),
  ('ventas_borrego', 'Ventas de borregos',   23, 'Ventas'),
  ('ventas_berries', 'Ventas de berries',    24, 'Ventas'),
  ('ventas_general', 'Ventas generales',     25, 'Ventas'),
  ('cobranza',       'Cobranza y saldos',    26, 'Ventas')
on conflict (codigo) do update set nombre = excluded.nombre, orden = excluded.orden, grupo = excluded.grupo;
update modulos set grupo = 'Planta', orden = 10 where codigo = 'planta';
update modulos set grupo = 'Catálogos', orden = 90, nombre = 'Catálogos (fórmulas, materias primas, casetas)' where codigo = 'catalogos';
-- 'ventas' se reemplaza por los permisos por tipo; finanzas y compras aún no tienen pantalla.
update modulos set activo = false where codigo in ('ventas', 'finanzas', 'compras');
update modulos set grupo = 'Próximamente', orden = 50 + orden where codigo in ('cerdos', 'aves', 'almacen', 'ganado', 'borregos', 'berries', 'gastos', 'nomina', 'reportes') and grupo is null;

alter table perfil_modulos add column if not exists nivel text not null default 'capturar' check (nivel in ('ver', 'capturar'));

-- Usuarios existentes: 'ventas' → todos los tipos de venta + cobranza; todos conservan ver planta, granjas y avisos.
insert into perfil_modulos (perfil_id, modulo, nivel)
select pm.perfil_id, m.codigo, 'capturar' from perfil_modulos pm
cross join (values ('ventas_huevo'), ('ventas_cerdo'), ('ventas_ganado'), ('ventas_borrego'), ('ventas_berries'), ('ventas_general'), ('cobranza')) m (codigo)
where pm.modulo = 'ventas'
on conflict (perfil_id, modulo) do nothing;
delete from perfil_modulos where modulo = 'ventas';
insert into perfil_modulos (perfil_id, modulo, nivel)
select p.id, m.codigo, 'ver' from perfiles p cross join (values ('planta'), ('granjas'), ('avisos')) m (codigo)
where p.rol not in ('administrador', 'director')
  and not exists (select 1 from perfil_modulos x where x.modulo = 'avisos')   -- solo la primera vez
on conflict (perfil_id, modulo) do nothing;

-- ---------- Funciones de permiso ----------
create or replace function puede_ver(p_modulo text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and activo and rol in ('administrador', 'director'))
      or exists (select 1 from perfil_modulos pm join perfiles p on p.id = pm.perfil_id
                 where pm.perfil_id = auth.uid() and p.activo and pm.modulo = p_modulo);
$$;

create or replace function puede_capturar(p_modulo text) returns boolean
language sql stable security definer set search_path = public as $$
  select es_admin() or exists (
    select 1 from perfil_modulos pm join perfiles p on p.id = pm.perfil_id
    where pm.perfil_id = auth.uid() and p.activo and pm.modulo = p_modulo and pm.nivel = 'capturar');
$$;

-- Alguna venta o cobranza (para clientes, productos y cuentas que se dan de alta desde Ventas).
create or replace function puede_capturar_ventas() returns boolean
language sql stable security definer set search_path = public as $$
  select es_admin() or exists (
    select 1 from perfil_modulos pm join perfiles p on p.id = pm.perfil_id
    where pm.perfil_id = auth.uid() and p.activo and pm.nivel = 'capturar' and (pm.modulo like 'ventas\_%' or pm.modulo = 'cobranza'));
$$;
revoke execute on function puede_ver(text) from anon;
revoke execute on function puede_capturar_ventas() from anon;

-- ---------- Planta: solo con permiso de planta ----------
do $$
declare t text;
begin
  foreach t in array array['llegadas_mp', 'pedidos_alimento', 'pedido_detalle', 'ordenes_produccion', 'orden_medicacion',
    'salidas_alimento', 'salida_detalle', 'ajustes_mp', 'conteos_mp', 'movimientos_mp', 'saldos_mp', 'inventario_inicial',
    'orden_ingredientes', 'orden_extras', 'contratos_mp', 'pesadas_conjuntas', 'notas_entrada',
    'materias_primas', 'formulas', 'formula_ingredientes', 'formula_alias', 'bodegas', 'camiones', 'grupos_almacen'] loop
    execute format('drop policy if exists leer on %I', t);
    execute format('create policy leer on %I for select to authenticated using (puede_ver(''planta''))', t);
  end loop;
end $$;

-- ---------- Ventas: cada tipo con su permiso; cobranza ve todas las ventas para aplicar pagos ----------
drop policy if exists leer on ventas;
drop policy if exists capturar on ventas;
drop policy if exists editar on ventas;
create policy leer on ventas for select to authenticated using (puede_ver('ventas_' || especie) or puede_ver('cobranza'));
create policy capturar on ventas for insert to authenticated with check (puede_capturar('ventas_' || especie));
create policy editar on ventas for update to authenticated
  using (puede_capturar('ventas_' || especie)) with check (puede_capturar('ventas_' || especie));

do $$
declare t text;
begin
  foreach t in array array['venta_renglones', 'venta_facturas'] loop
    execute format('drop policy if exists leer on %I', t);
    execute format('drop policy if exists capturar on %I', t);
    execute format('drop policy if exists editar on %I', t);
    execute format('drop policy if exists borrar_ventas on %I', t);
    -- la subconsulta a ventas ya pasa por su propia regla de lectura
    execute format('create policy leer on %I for select to authenticated using (exists (select 1 from ventas v where v.id = venta_id))', t);
    execute format('create policy capturar on %I for insert to authenticated with check (exists (select 1 from ventas v where v.id = venta_id and puede_capturar(''ventas_'' || v.especie)))', t);
    execute format('create policy editar on %I for update to authenticated using (exists (select 1 from ventas v where v.id = venta_id and puede_capturar(''ventas_'' || v.especie)))', t);
    execute format('create policy borrar_ventas on %I for delete to authenticated using (exists (select 1 from ventas v where v.id = venta_id and puede_capturar(''ventas_'' || v.especie)))', t);
  end loop;
  foreach t in array array['pagos_cliente', 'pago_aplicaciones'] loop
    execute format('drop policy if exists leer on %I', t);
    execute format('drop policy if exists capturar on %I', t);
    execute format('drop policy if exists editar on %I', t);
    execute format('drop policy if exists borrar_ventas on %I', t);
    execute format('create policy leer on %I for select to authenticated using (puede_ver(''cobranza''))', t);
    execute format('create policy capturar on %I for insert to authenticated with check (puede_capturar(''cobranza''))', t);
    execute format('create policy editar on %I for update to authenticated using (puede_capturar(''cobranza'')) with check (puede_capturar(''cobranza''))', t);
    execute format('create policy borrar_ventas on %I for delete to authenticated using (puede_capturar(''cobranza''))', t);
  end loop;
end $$;

-- Quien ve una venta ve también lo que se le ha pagado (para que su saldo salga bien sin permiso de cobranza).
drop policy leer on pago_aplicaciones;
create policy leer on pago_aplicaciones for select to authenticated
  using (puede_ver('cobranza') or exists (select 1 from ventas v where v.id = venta_id));

drop policy if exists capturar_ventas on clientes;
drop policy if exists editar_ventas on clientes;
create policy capturar_ventas on clientes for insert to authenticated with check (puede_capturar_ventas());
create policy editar_ventas on clientes for update to authenticated using (puede_capturar_ventas()) with check (puede_capturar_ventas());
drop policy if exists capturar_ventas on productos_venta;
create policy capturar_ventas on productos_venta for insert to authenticated with check (puede_capturar_ventas());
drop policy if exists capturar_ventas on cuentas_bancarias;
create policy capturar_ventas on cuentas_bancarias for insert to authenticated with check (puede_capturar_ventas());

-- ---------- Usuarios: alta con permisos de ver y de capturar ----------
drop function if exists guardar_perfil(text, text, rol_usuario, text[], boolean);
create or replace function guardar_perfil(p_email text, p_nombre text, p_rol rol_usuario, p_ver text[], p_capturar text[], p_activo boolean default true)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not es_admin() then raise exception 'Solo el administrador puede dar de alta usuarios'; end if;
  select id into v_id from auth.users where lower(email) = lower(trim(p_email));
  if v_id is null then
    raise exception 'No existe el correo %. Primero créalo en Supabase → Authentication → Users', p_email;
  end if;
  if v_id = auth.uid() and (p_rol <> 'administrador' or not p_activo) then
    raise exception 'No puedes quitarte a ti mismo el rol de administrador';
  end if;
  insert into perfiles (id, nombre, rol, activo) values (v_id, trim(p_nombre), p_rol, p_activo)
  on conflict (id) do update set nombre = excluded.nombre, rol = excluded.rol, activo = excluded.activo;
  delete from perfil_modulos where perfil_id = v_id;
  insert into perfil_modulos (perfil_id, modulo, nivel)
  select v_id, m, case when m = any (coalesce(p_capturar, '{}')) then 'capturar' else 'ver' end
  from (select unnest(coalesce(p_ver, '{}')) union select unnest(coalesce(p_capturar, '{}'))) x (m)
  where m in (select codigo from modulos where activo);
  return v_id;
end $$;

drop function if exists listar_usuarios();
create or replace function listar_usuarios()
returns table (id uuid, email text, nombre text, rol rol_usuario, activo boolean, modulos text[], captura text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not es_admin() then raise exception 'Solo el administrador puede ver los usuarios'; end if;
  return query
    select p.id, u.email::text, p.nombre, p.rol, p.activo,
           coalesce(array_agg(pm.modulo order by pm.modulo) filter (where pm.modulo is not null), '{}'),
           coalesce(array_agg(pm.modulo order by pm.modulo) filter (where pm.nivel = 'capturar'), '{}')
    from perfiles p
    join auth.users u on u.id = p.id
    left join perfil_modulos pm on pm.perfil_id = p.id
    group by p.id, u.email
    order by p.nombre;
end $$;

-- Mis permisos (para armar el menú): modulos = lo que puedo ver; captura = lo que puedo capturar.
drop function if exists mi_perfil();
create or replace function mi_perfil()
returns table (id uuid, nombre text, rol rol_usuario, activo boolean, modulos text[], captura text[])
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, p.rol, p.activo,
         case when p.rol in ('administrador', 'director') then array(select codigo from modulos where activo order by orden)
              else coalesce(array_agg(pm.modulo) filter (where pm.modulo is not null), '{}') end,
         case when p.rol = 'administrador' then array(select codigo from modulos where activo order by orden)
              else coalesce(array_agg(pm.modulo) filter (where pm.nivel = 'capturar'), '{}') end
  from perfiles p
  left join perfil_modulos pm on pm.perfil_id = p.id
  where p.id = auth.uid()
  group by p.id;
$$;
revoke execute on function guardar_perfil(text, text, rol_usuario, text[], text[], boolean) from anon;
revoke execute on function listar_usuarios() from anon;
revoke execute on function mi_perfil() from anon;
