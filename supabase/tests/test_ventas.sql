-- Prueba 0018: ventas de huevo y cerdo
\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-000000000005', 'ventas@ramarierp.com'), ('00000000-0000-0000-0000-000000000001', 'planta@ramarierp.com');
insert into perfiles values ('00000000-0000-0000-0000-000000000005', 'Capturista ventas', 'capturista', true), ('00000000-0000-0000-0000-000000000001', 'Planta', 'capturista', true);
insert into perfil_modulos values ('00000000-0000-0000-0000-000000000005', 'ventas'), ('00000000-0000-0000-0000-000000000001', 'planta');
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000005';
insert into clientes (nombre, rfc) values ('HUEVERA DEL NORTE', 'HNO010101AB1'), ('OBRADOR LÓPEZ', 'LOPJ800101XX1');
-- Huevo: 2 calidades de 2 granjas; 300 cajas Línea Durazno 6,750 kg a $28.50 base + $0.80 flete; 50 cajas Sucio Paraíso 1,100 kg a $24
select guardar_venta(jsonb_build_object('especie', 'huevo', 'fecha', '2026-11-24', 'cliente_id', 1, 'destino', 'Monterrey',
    'tipo_pago', 'factura', 'empresa_factura_id', 1, 'forma_pago', 'credito', 'anticipo', 100000, 'flete_kg', 0.80,
    'merma_kg_caja', 2, 'descuento', 500, 'motivo_descuento', '5 cajas con huevo roto'),
  jsonb_build_array(
    jsonb_build_object('granja_id', (select id from granjas where nombre = 'Durazno'), 'calidad', 'Línea', 'cantidad', 300, 'kg', 6750, 'precio_kg', 28.50),
    jsonb_build_object('granja_id', (select id from granjas where nombre = 'Paraíso'), 'calidad', 'Sucio', 'cantidad', 50, 'kg', 1100, 'precio_kg', 24))) as venta_huevo;
select granja, calidad, cantidad, kg_brutos, merma_kg, kg_netos, peso_promedio, precio_total_kg, importe from v_venta_renglones order by id;
select cliente, rfc, empresa_factura, cantidad, kg_brutos, merma_kg, kg_netos, subtotal, descuento, total, anticipo, saldo, precio_promedio_kg, calidades, granjas from v_ventas;
-- Cerdo: 2 calidades, 2 muertos, descuento
select guardar_venta(jsonb_build_object('especie', 'cerdo', 'fecha', '2026-11-24', 'cliente_id', 2, 'tipo_pago', 'efectivo',
    'forma_pago', 'contado', 'muertos', 2, 'descuento', 3600, 'motivo_descuento', '2 muertos'),
  jsonb_build_array(
    jsonb_build_object('granja_id', (select id from granjas where nombre = 'San Pablo'), 'calidad', 'C1', 'cantidad', 120, 'kg', 13200, 'precio_kg', 36.50),
    jsonb_build_object('granja_id', (select id from granjas where nombre = 'San Pablo'), 'calidad', 'C2', 'cantidad', 10, 'kg', 980, 'precio_kg', 32))) as venta_cerdo;
select especie, cliente, cantidad, kg_netos, peso_promedio, muertos, subtotal, descuento, total, saldo from v_ventas where especie = 'cerdo';
-- Editar la venta de cerdo (cambia precio C1 a 37)
select guardar_venta(jsonb_build_object('especie', 'cerdo', 'fecha', '2026-11-24', 'cliente_id', 2, 'tipo_pago', 'efectivo', 'forma_pago', 'contado', 'muertos', 2, 'descuento', 3600),
  jsonb_build_array(jsonb_build_object('granja_id', (select id from granjas where nombre = 'San Pablo'), 'calidad', 'C1', 'cantidad', 120, 'kg', 13200, 'precio_kg', 37),
                    jsonb_build_object('granja_id', (select id from granjas where nombre = 'San Pablo'), 'calidad', 'C2', 'cantidad', 10, 'kg', 980, 'precio_kg', 32)), 2);
select total, modificado_por from v_ventas where id = 2;
\set ON_ERROR_STOP 0
select guardar_venta('{"especie": "huevo", "fecha": "2026-11-24", "cliente_id": 1, "tipo_pago": "factura"}', '[{"kg": 10, "precio_kg": 1}]');  -- sin razón social
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select guardar_venta('{"especie": "huevo", "fecha": "2026-11-24", "cliente_id": 1, "tipo_pago": "efectivo"}', '[{"kg": 10, "precio_kg": 1}]');  -- sin permiso
reset role;
