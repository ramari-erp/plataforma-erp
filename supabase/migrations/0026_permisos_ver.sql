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
