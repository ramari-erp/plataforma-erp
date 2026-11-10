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
