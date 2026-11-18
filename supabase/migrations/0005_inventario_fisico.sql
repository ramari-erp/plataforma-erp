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
