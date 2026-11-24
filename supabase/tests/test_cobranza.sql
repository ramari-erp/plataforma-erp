-- Prueba 0019: berries, ventas generales y cobranza (correr sobre una base recién cargada)
\set ON_ERROR_STOP 1
insert into auth.users values ('00000000-0000-0000-0000-000000000005', 'ventas@ramarierp.com');
insert into perfiles values ('00000000-0000-0000-0000-000000000005', 'Capturista ventas', 'capturista', true);
insert into perfil_modulos values ('00000000-0000-0000-0000-000000000005', 'ventas');
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000005';
insert into clientes (nombre) values ('SUREXPORT'), ('BERRY LOVERS'), ('RASTRO SAN JUAN');

-- Berries por kg en dólares: 120 cajas 12×18 oz Jumbo, 734.4 kg, merma 4.4 kg, 7 USD/kg → 730 × 7 = 5,110
select guardar_venta('{"especie": "berries", "fecha": "2026-11-02", "cliente_id": 1, "tipo_pago": "factura", "empresa_factura_id": 1,
  "forma_pago": "credito", "moneda": "USD", "tipo_cambio": 18.5, "folio": "B-101", "folio_externo": "SX-88"}',
  '[{"presentacion": "12 x 18 oz", "calidad": "Jumbo", "cantidad": 120, "kg": 734.4, "merma_kg": 4.4, "precio_kg": 7}]') as b1;
-- Berries por caja: 200 cajas 6 oz a 26.52 USD = 5,304
select guardar_venta('{"especie": "berries", "fecha": "2026-11-09", "cliente_id": 2, "tipo_pago": "factura", "empresa_factura_id": 1,
  "forma_pago": "credito", "moneda": "USD", "folio": "B-102"}',
  '[{"presentacion": "6 oz", "calidad": "Código 1", "cantidad": 200, "kg": 408, "precio_kg": 26.52, "precio_por": "unidad"}]') as b2;
-- Segunda venta a Surexport: 3,000 USD
select guardar_venta('{"especie": "berries", "fecha": "2026-11-16", "cliente_id": 1, "tipo_pago": "factura", "empresa_factura_id": 1,
  "forma_pago": "credito", "moneda": "USD", "folio": "B-103"}',
  '[{"presentacion": "Granel", "calidad": "Proceso", "cantidad": 0, "kg": 1000, "precio_kg": 3}]') as b3;
-- General: gallina a rastro por pieza, sin kg (1,500 × $35 = 52,500), a crédito en pesos
select guardar_venta(jsonb_build_object('especie', 'general', 'fecha', '2026-11-10', 'cliente_id', 3, 'tipo_pago', 'efectivo', 'forma_pago', 'credito'),
  jsonb_build_array(jsonb_build_object('producto_id', (select id from productos_venta where nombre like 'GALLINA%'),
    'granja_id', (select id from granjas where nombre = 'Durazno'), 'cantidad', 1500, 'precio_kg', 35, 'precio_por', 'unidad'))) as g1;
-- Producto nuevo creado por capturista de ventas
insert into productos_venta (nombre, unidad, area) values ('COSTALES VACÍOS', 'pieza', 'planta');

select especie, folio, cliente, moneda, kg_netos, subtotal, total, saldo, presentaciones, productos from v_ventas order by id;
select presentacion, producto, precio_por, cantidad, kg_netos, importe from v_venta_renglones order by id;

-- Pago de Surexport 6,000 USD: 5,110 a B-101 y 890 a B-103 (FIFO); queda todo aplicado
select registrar_pago('{"cliente_id": 1, "fecha": "2026-11-20", "monto": 6000, "moneda": "USD", "banco": "BBVA", "referencia": "TRF 5521"}',
  '[{"venta_id": 1, "monto": 5110}, {"venta_id": 3, "monto": 890}]') as p1;
-- Pago parcial del rastro 20,000 MXN, aplicado 15,000; 5,000 queda a favor
select registrar_pago('{"cliente_id": 3, "fecha": "2026-11-21", "monto": 20000, "forma": "efectivo"}', '[{"venta_id": 4, "monto": 15000}]') as p2;
select folio, cliente, total, pagado, saldo from v_ventas order by id;
select cliente, monto, moneda, aplicado, sin_aplicar, ventas from v_pagos order by id;
select cliente, moneda, vendido, pagado, ventas_con_saldo, saldo_ventas, a_favor, saldo from v_saldos_clientes order by cliente;
-- Corregir el pago del rastro: aplicar los 20,000
select registrar_pago('{"cliente_id": 3, "fecha": "2026-11-21", "monto": 20000, "forma": "efectivo"}', '[{"venta_id": 4, "monto": 20000}]', 2);
select cliente, saldo_ventas, a_favor, saldo from v_saldos_clientes where cliente like 'RASTRO%';

\set ON_ERROR_STOP 0
select registrar_pago('{"cliente_id": 1, "fecha": "2026-11-22", "monto": 100}', '[{"venta_id": 3, "monto": 100}]');           -- moneda distinta
select registrar_pago('{"cliente_id": 1, "fecha": "2026-11-22", "monto": 5000, "moneda": "USD"}', '[{"venta_id": 3, "monto": 5000}]'); -- más que el saldo
select registrar_pago('{"cliente_id": 1, "fecha": "2026-11-22", "monto": 100, "moneda": "USD"}', '[{"venta_id": 2, "monto": 100}]'); -- otro cliente
select registrar_pago('{"cliente_id": 1, "fecha": "2026-11-22", "monto": 100, "moneda": "USD"}', '[{"venta_id": 3, "monto": 200}]'); -- aplica más que el pago
select guardar_venta('{"especie": "berries", "fecha": "2026-11-22", "cliente_id": 1, "tipo_pago": "efectivo"}', '[{"cantidad": 5, "precio_kg": 7}]'); -- por kg sin kg
reset role;
