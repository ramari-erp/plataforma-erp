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
