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
