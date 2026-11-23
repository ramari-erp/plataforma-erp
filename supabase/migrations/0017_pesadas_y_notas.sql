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
