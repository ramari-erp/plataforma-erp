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
