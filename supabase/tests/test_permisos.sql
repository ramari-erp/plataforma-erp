-- Prueba 0026: permisos de ver y capturar (correr sobre una base recién cargada + test_cobranza)
\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-000000000021', 'huevo@x'), ('00000000-0000-0000-0000-000000000022', 'admin@x');
insert into perfiles values ('00000000-0000-0000-0000-000000000022', 'Admin', 'administrador', true);
-- Usuario viejo con el permiso 'ventas' de antes: al volver a correr 0026 recibe todos los tipos + cobranza
insert into auth.users values ('00000000-0000-0000-0000-000000000023', 'viejo@x');
insert into perfiles values ('00000000-0000-0000-0000-000000000023', 'Usuario viejo', 'capturista', true);
insert into perfil_modulos (perfil_id, modulo) values ('00000000-0000-0000-0000-000000000023', 'ventas');
delete from perfil_modulos where modulo = 'avisos';
\i supabase/migrations/0026_permisos_ver.sql
select modulo, nivel from perfil_modulos where perfil_id = '00000000-0000-0000-0000-000000000023' order by modulo;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000022';
select guardar_perfil('huevo@x', 'Capturista huevo', 'capturista', array['ventas_huevo'], array['ventas_huevo']);
select nombre, modulos, captura from listar_usuarios() order by nombre;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000021';
select * from mi_perfil();
select especie, count(*) from ventas group by especie order by 1;              -- solo huevo
select count(*) as materias_visibles from materias_primas;                      -- 0
select count(*) as llegadas_visibles from llegadas_mp;                          -- 0
select count(*) as pagos_visibles from pagos_cliente;                           -- 0
select cliente, total, pagado, saldo from v_ventas order by id;                  -- pagado visible en sus ventas
select guardar_venta('{"especie": "huevo", "fecha": "2026-11-26", "cliente_id": 1, "tipo_pago": "efectivo", "forma_pago": "contado", "merma_kg_caja": 2, "kg_bascula": 220}',
  '[{"calidad": "Línea", "cantidad": 10, "precio_kg": 28}]') as venta_huevo_ok;
insert into clientes (nombre) values ('CLIENTE DE HUEVO NUEVO');
\set ON_ERROR_STOP 0
select guardar_venta('{"especie": "cerdo", "fecha": "2026-11-26", "cliente_id": 1, "tipo_pago": "efectivo", "forma_pago": "contado"}',
  '[{"calidad": "C1", "cantidad": 10, "kg": 1000, "precio_kg": 40}]');   -- sin permiso de cerdo
select registrar_pago('{"cliente_id": 1, "fecha": "2026-11-26", "monto": 100}', '[]');   -- sin permiso de cobranza
reset role;
