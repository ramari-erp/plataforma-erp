const hoy = new Date(); const p = (x) => String(x).padStart(2, '0');
const f = (d) => { const x = new Date(hoy); x.setDate(x.getDate() + d); return `${x.getFullYear()}-${p(x.getMonth()+1)}-${p(x.getDate())}`; };
let productosF = [{ id: 1, nombre: 'ABONO', unidad: 'tonelada', area: 'otro', precio_sugerido: 450 }, { id: 2, nombre: 'GALLINA DE DESECHO (RASTRO)', unidad: 'pieza', area: 'aves', precio_sugerido: null }];
let cuentasF = [{ id: 1, nombre: 'CAJA (EFECTIVO)', tipo: 'caja', moneda: 'MXN', activa: true }, { id: 2, nombre: 'BBVA PECUARIA 1234', tipo: 'banco', moneda: 'MXN', activa: true }];
let sesion = null; let inicial = []; let conteos = []; let ventasF = [{ id: 1, especie: 'huevo', fecha: f(0), cliente_id: 1, cliente: 'HUEVERA DEL NORTE', rfc: 'HNO010101AB1', destino: 'Monterrey', tipo_pago: 'factura', empresa_factura_id: 1, empresa_factura: 'Pecuaria Real Victoria', factura: null, forma_pago: 'credito', anticipo: 100000, flete_kg: 0, flete_caja: 0, destino_colonia: 'Centro', destino_ciudad: 'Monterrey', destino_estado: 'Nuevo León', aumento_centavos_kg: 40, kg_bascula: 7850, num_facturas: 2, facturas: 'A-100 · Pecuaria Real Victoria, B-50 · Maront', facturado: 204495, factura: 'A-100, B-50', merma_kg_caja: 2, muertos: 0, descuento: 500, motivo_descuento: '5 cajas rotas', cantidad: 350, kg_brutos: 7850, merma_kg: 700, kg_netos: 7150, peso_promedio: 22.43, subtotal: 204995, total: 204495, precio_promedio_kg: 28.6, saldo: 104495, calidades: 'Línea, Sucio', granjas: 'Durazno, Paraíso', capturado_por: 'Ventas', capturado_en: new Date().toISOString() },
  { id: 2, especie: 'borrego', fecha: f(-3), cliente_id: 2, cliente: 'OBRADOR LÓPEZ', tipo_pago: 'efectivo', forma_pago: 'contado', anticipo: 0, flete_kg: 0, merma_kg_caja: 0, muertos: 0, descuento: 0, cantidad: 20, kg_brutos: 900, merma_kg: 0, kg_netos: 900, peso_promedio: 45, total: 45000, precio_promedio_kg: 50, saldo: 0, calidades: 'Cordero', granjas: 'La Red', capturado_por: 'Ventas', capturado_en: new Date().toISOString() },
  { id: 10, especie: 'berries', fecha: f(-40), cliente_id: 3, cliente: 'SUREXPORT', tipo_pago: 'factura', empresa_factura: 'Pecuaria Real Victoria', empresa_factura_id: 1, forma_pago: 'credito', anticipo: 0, flete_kg: 0, merma_kg_caja: 0, muertos: 0, descuento: 0, cantidad: 120, kg_brutos: 734.4, merma_kg: 4.4, kg_netos: 730, peso_promedio: 6.12, total: 5110, precio_promedio_kg: 7, saldo: 3110, pagado: 2000, calidades: 'Jumbo', presentaciones: '12 x 18 oz', granjas: 'Bellavista', folio: 'B-101', folio_externo: 'SX-88', moneda: 'USD', tipo_cambio: 18.5, capturado_por: 'Ventas', capturado_en: new Date().toISOString() },
  { id: 11, especie: 'berries', fecha: f(-5), cliente_id: 3, cliente: 'SUREXPORT', tipo_pago: 'factura', empresa_factura_id: 1, forma_pago: 'credito', anticipo: 0, flete_kg: 0, merma_kg_caja: 0, muertos: 0, descuento: 0, cantidad: 0, kg_brutos: 1000, merma_kg: 0, kg_netos: 1000, total: 3000, precio_promedio_kg: 3, saldo: 2000, pagado: 1000, calidades: 'Proceso', presentaciones: 'Granel', folio: 'B-103', moneda: 'USD', capturado_por: 'Ventas', capturado_en: new Date().toISOString() },
  { id: 12, especie: 'general', fecha: f(-1), cliente_id: 2, cliente: 'OBRADOR LÓPEZ', tipo_pago: 'efectivo', forma_pago: 'credito', anticipo: 0, flete_kg: 0, merma_kg_caja: 0, muertos: 0, descuento: 0, cantidad: 1500, kg_brutos: 0, merma_kg: 0, kg_netos: 0, total: 52500, saldo: 52500, pagado: 0, productos: 'GALLINA DE DESECHO (RASTRO)', granjas: 'Durazno', moneda: 'MXN', capturado_por: 'Ventas', capturado_en: new Date().toISOString() }];
let ordenes = [
  { id: 11, fecha: f(0), formula_id: 5, formula: 'NX DESARROLLO', area: 'cerdos', granja: 'La Red', kg_solicitados: 5000, kg_reales: null, kg_producidos: 5000, pendiente_pesada: true, costo_mp: 30000, costo_kg: 6, extras: 0, capturado_por: 'Rafael', capturado_en: new Date().toISOString() },
  { id: 12, fecha: f(0), formula_id: 6, formula: 'NX GESTACIÓN', area: 'cerdos', granja: 'La Red', kg_solicitados: 10000, kg_reales: null, kg_producidos: 10000, pendiente_pesada: true, costo_mp: 60000, costo_kg: 6, extras: 0, capturado_por: 'Rafael', capturado_en: new Date().toISOString() },
  { id: 13, fecha: f(0), formula_id: 7, formula: 'NX LACTANCIA', area: 'cerdos', granja: 'Palenque', kg_solicitados: 3000, kg_reales: null, kg_producidos: 3000, pendiente_pesada: true, costo_mp: 20000, costo_kg: 6.6, extras: 0, capturado_por: 'Rafael', capturado_en: new Date().toISOString() } ];
let catMp = [
  { id: 99, nombre: 'GLUTEN DE MAÍZ', categoria: 'ingrediente', presentacion: 'saco 40 kg', grupo_almacen_id: null, grupo_almacen: null, stock_minimo_kg: null, requiere_contrato: false, activa: true, revisada: false, creada_por: 'Capturista planta', creada_en: new Date().toISOString(), existencia_kg: 0 },
  { id: 1, nombre: 'SORGO', categoria: 'grano', presentacion: null, grupo_almacen_id: 1, grupo_almacen: 'Sorgo y maíz', stock_minimo_kg: 100000, requiere_contrato: true, activa: true, revisada: true, existencia_kg: 2950000 } ];
let contratos = [
  { id: 3, folio: 'MM-9', fecha: f(-90), proveedor_id: 2, proveedor: 'MULTIMERCADO', materia_prima_id: 1, materia_prima: 'SORGO', kg_contratados: 200000, moneda: 'MXN', precio: 4.9, fecha_fin: f(-30), estado: 'abierto', estado_actual: 'surtido', kg_surtidos: 200000, kg_pendientes: 0, kg_excedente: 0, pct_surtido: 100, llegadas: 7, dias_para_vencer: -30 },
  { id: 1, folio: 'PRV-101', fecha: f(-20), proveedor_id: 1, proveedor: 'LANDUS', materia_prima_id: 1, materia_prima: 'SORGO', kg_contratados: 500000, moneda: 'MXN', precio: 5.12, fecha_fin: f(5), estado: 'abierto', estado_actual: 'abierto', kg_surtidos: 60210, kg_pendientes: 439790, pct_surtido: 12, llegadas: 2, dias_para_vencer: 5 },
  { id: 2, folio: 'LND-7', fecha: f(-40), proveedor_id: 1, proveedor: 'LANDUS', materia_prima_id: 2, materia_prima: 'PASTA DE SOYA', kg_contratados: 300000, moneda: 'USD', precio: 0.2786, fecha_fin: f(-1), estado: 'abierto', estado_actual: 'vencido', kg_surtidos: 25000, kg_pendientes: 20000, pct_surtido: 93.3, llegadas: 1, dias_para_vencer: -1 } ];
const llegadas = [
  { id: 2, fecha: f(0), materia_prima_id: 1, materia_prima: 'SORGO', proveedor: 'LANDUS', kg_neto: 30210, humedad_pct: 13.5, precio_kg: 5.12, total: 154675.2, factura: 'A-123', boleta: '8812', contrato_id: 1, contrato: 'PRV-101', kg_excedente_contrato: 0, pendientes: [], proveedor_id: 1, capturado_por: 'Capturista planta', capturado_en: new Date().toISOString() },
  { id: 1, fecha: f(-2), materia_prima_id: 2, materia_prima: 'PASTA DE SOYA', proveedor: null, kg_neto: 20000, humedad_pct: null, precio_kg: 6.66, tipo_cambio: 18.5, total: 133200, factura: null, boleta: null, contrato_id: 2, contrato: 'LND-7', kg_excedente_contrato: 5000, precio_provisional: true, pendientes: ['factura', 'precio'], capturado_por: 'Admin', capturado_en: new Date().toISOString() },
];
let provs = [{ id: 1, nombre: 'LANDUS' }];
const usuarios = [{ id: 'a', email: 'admin@ramarierp.com', nombre: 'Rafael', rol: 'administrador', activo: true, modulos: [] }];
export const api = {
  async sesion() { return sesion; },
  async entrar(e, pw) { if (pw !== 'bien') throw new Error('Correo o contraseña incorrectos.'); sesion = { user: { email: e } }; },
  async salir() { sesion = null; }, alCambiarSesion() {},
  async miPerfil() { return window.__perfilPrueba || { id: 'a', nombre: 'Rafael', rol: 'administrador', activo: true, modulos: ['catalogos','planta'], captura: ['catalogos','planta'] }; },
  async modulos() { return [{ codigo: 'avisos', nombre: 'Avisos en Inicio', grupo: 'General' }, { codigo: 'granjas', nombre: 'Granjas y casetas', grupo: 'General' }, { codigo: 'planta', nombre: 'Planta de alimentos', grupo: 'Planta' }, { codigo: 'ventas_huevo', nombre: 'Ventas de huevo', grupo: 'Ventas' }, { codigo: 'ventas_cerdo', nombre: 'Ventas de cerdo', grupo: 'Ventas' }, { codigo: 'cobranza', nombre: 'Cobranza y saldos', grupo: 'Ventas' }]; },
  async materias() { return [{ id: 1, nombre: 'SORGO' }, { id: 2, nombre: 'PASTA DE SOYA' }, { id: 3, nombre: 'NÚCLEO FINALIZADOR NX' }, { id: 5, nombre: 'Toxad Plus' }, { id: 7, nombre: 'SAL' }]; },
  async proveedores() { return provs.slice(); },
  async crearProveedor(nombre) { const x = { id: provs.length + 1, nombre }; provs.push(x); return x; },
  async capacidad() { return [
    { id: 1, nombre: 'Sorgo y maíz', orden: 1, capacidad_total_kg: 6170000, existencia_kg: 2950000, ocupacion_pct: 47.8, espacio_libre_kg: 3220000, materias: 'MAIZ, SORGO', notas: 'Zona roja 4,800 t (sorgo o maíz) + zona amarilla 1,350 t (solo maíz).' },
    { id: 2, nombre: 'Soya', orden: 2, capacidad_total_kg: 1060000, existencia_kg: 980000, ocupacion_pct: 92.5, espacio_libre_kg: 80000, materias: 'PASTA DE SOYA', notas: null },
    { id: 3, nombre: 'Ortofosfato', orden: 6, capacidad_total_kg: 40000, existencia_kg: -30, ocupacion_pct: -0.1, espacio_libre_kg: 40030, materias: 'ORTOFOSFATO', notas: null } ]; },
  async existencias() { return [
    { id: 1, precio_referencia: 5.1, nombre: 'SORGO', categoria: 'grano', existencia_kg: 2950000, costo_promedio: 5.1, valor_inventario: 15045000 },
    { id: 2, precio_referencia: 6.34, nombre: 'PASTA DE SOYA', categoria: 'pasta', existencia_kg: 980000, costo_promedio: 6.34, valor_inventario: 6213200 },
    { id: 4, precio_referencia: 25.16, nombre: 'ORTOFOSFATO', categoria: 'mineral', existencia_kg: -30, costo_promedio: 0, valor_inventario: 0 },
    { id: 5, nombre: 'Toxad Plus', categoria: 'medicamento', existencia_kg: 40, costo_promedio: 20, valor_inventario: 800 },
    { id: 6, nombre: 'Tylosin 22%', categoria: 'medicamento', existencia_kg: 2, costo_promedio: 220.04, valor_inventario: 440 },
    { id: 7, nombre: 'SAL', categoria: 'mineral', existencia_kg: 3000, costo_promedio: 0.44, valor_inventario: 1320 },
    { id: 3, precio_referencia: 52.89, nombre: 'NÚCLEO FINALIZADOR NX', categoria: 'nucleo', existencia_kg: 850, costo_promedio: 52.89, valor_inventario: 44956.5, bajo_minimo: true, stock_minimo_kg: 1000 } ]; },
  async llegadas({ materia, pendientes } = {}) { return llegadas.filter((l) => (!materia || String(l.materia_prima_id) === String(materia)) && (!pendientes || (l.pendientes || []).length)); },
  async actualizarLlegada(id, d) { window.__editada = [id, d]; },
  async eliminarLlegada(id) { window.__eliminadaLl = id; },
  async crearLlegada(d) { window.__guardada = d; llegadas.unshift({ id: 9, ...d, materia_prima: 'SORGO', proveedor: 'NUEVO PROV', total: d.kg_neto * d.precio_kg, capturado_por: 'Rafael', capturado_en: new Date().toISOString() }); return { id: 9 }; },
  async usuarios() { return usuarios; }, async guardarUsuario(u) { window.__usuario = u; return 'x'; },
  async inventarioInicial() { return inicial; },
  async guardarInventarioInicial(fecha, items) { window.__arranque = { fecha, items }; inicial = items.map((i) => ({ ...i, fecha })); return items.length; },
  async registrarConteo(fecha, items) { window.__conteo = items; conteos = items.map((i) => ({ fecha, materia_prima: 'M' + i.materia_prima_id, kg_sistema: 1000, kg_fisicos: i.kg_fisicos, diferencia: i.kg_fisicos - 1000, capturado_por: 'Rafael' })); return conteos.map((c) => ({ materia: c.materia_prima, kg_sistema: 1000, kg_fisicos: c.kg_fisicos, diferencia: c.diferencia })); },
  async conteos() { return conteos; },
  async formulas() { return [{ id: 5, nombre: 'NX FINALIZADOR', especie: 'cerdos' }, { id: 9, nombre: 'FASE 1', especie: 'aves' }]; },
  async formulaIngredientes(id) { if (id === 77) return []; return [{ materia_prima_id: 1, kg_por_tonelada: 745 }, { materia_prima_id: 2, kg_por_tonelada: 225 }, { materia_prima_id: 3, kg_por_tonelada: 25 }, { materia_prima_id: 7, kg_por_tonelada: 5 }]; },
  async guardarOrden(o) { window.__orden = o; if (o.ordenId) { const x = ordenes.find((y) => y.id === o.ordenId); Object.assign(x, { kg_solicitados: o.kg, kg_reales: o.kgReales, pendiente_pesada: !o.kgReales, notas: o.notas, modificado_por: 'Rafael', modificado_en: new Date().toISOString() }); return x.id; }
    ordenes.unshift({ id: 1, fecha: o.fecha, formula_id: o.formulaId, formula: 'NX FINALIZADOR', granja_id: o.granjaId, granja: o.granjaId === 5 ? 'Rodadero' : null, area: o.area, kg_solicitados: o.kg, kg_reales: o.kgReales, kg_producidos: o.kgReales || o.kg, kg_diferencia: o.kgReales ? o.kgReales - o.kg : null, pct_diferencia: o.kgReales ? 100 * (o.kgReales - o.kg) / o.kg : null, pendiente_pesada: !o.kgReales, costo_mp: 189130.3, costo_kg: 6.3043, formula_modificada: true, extras: 2, capturado_por: 'Rafael', capturado_en: new Date().toISOString(), notas: o.notas }); return 1; },
  async ingredientesOrden() { return [{ materia_prima_id: 1, kg_por_tonelada: 760 }, { materia_prima_id: 2, kg_por_tonelada: 210 }, { materia_prima_id: 3, kg_por_tonelada: 25 }, { materia_prima_id: 7, kg_por_tonelada: 5 }]; },
  async registrarPesada(id, kg) { window.__pesada = [id, kg]; const x = ordenes.find((y) => y.id === id); Object.assign(x, { kg_reales: kg, kg_producidos: kg, kg_diferencia: kg - x.kg_solicitados, pct_diferencia: 100 * (kg - x.kg_solicitados) / x.kg_solicitados, pendiente_pesada: false, modificado_por: 'Encargado', modificado_en: new Date().toISOString() }); },
  async ordenes({ pendientesPesada, pesadaConjunta } = {}) { if (pendientesPesada) return [{ id: 77 }, { id: 78 }]; if (pesadaConjunta) return ordenes.filter((o) => String(o.pesada_conjunta_id) === String(pesadaConjunta)); return ordenes; },
  async registrarPesadaConjunta(ids, total, pid) { window.__conjunta = [ids, total, pid]; const g = ordenes.filter((o) => ids.includes(o.id)); const sol = g.reduce((s, o) => s + o.kg_solicitados, 0); g.forEach((o) => Object.assign(o, { kg_reales: Math.round(o.kg_solicitados * total / sol * 100) / 100, pendiente_pesada: false, pesada_conjunta_id: 1, pesada_kg_total: total, pesada_ordenes: g.length, kg_diferencia: o.kg_solicitados * total / sol - o.kg_solicitados, pct_diferencia: 100 * (total - sol) / sol })); return 1; },
  async crearNotaEntrada(n) { window.__nota = n; return 1; },
  async facturaNota(id, f) { window.__facturaNota = [id, f]; },
  async consumosOrden() { return [{ materia_prima: 'SORGO', kg: 22800, costo_kg: 5.1, importe: 116280 }, { materia_prima: 'Toxad Plus', kg: 30, costo_kg: 20, importe: 600, es_extra: true }]; },
  async extrasOrden() { return [{ materia_prima_id: 5, cantidad: 1, unidad: 'kg_por_tonelada', nota: 'Brote respiratorio' }, { materia_prima_id: 6, cantidad: 5, unidad: 'kg_total', nota: 'Caseta 3' }]; },
  async eliminarOrden(id) { window.__eliminada = id; ordenes = []; },
  async buscarFolioContrato(f) { return contratos.filter((c) => (c.folio || '').toUpperCase() === f.trim().toUpperCase()); },
  async buscarLlegadaPor(campo, v) { return llegadas.filter((l) => (l[campo] || '').toUpperCase() === v.trim().toUpperCase()); },
  async contratos({ soloVigentes, materia } = {}) { return contratos.filter((c) => (!soloVigentes || c.estado === 'abierto') && (!materia || String(c.materia_prima_id) === String(materia))); },
  async crearContrato(d) { window.__contrato = d; contratos.push({ id: 9, ...d, proveedor: 'LANDUS', materia_prima: 'SORGO', kg_surtidos: 0, kg_pendientes: d.kg_contratados, pct_surtido: 0, llegadas: 0, estado: 'abierto', estado_actual: 'abierto', dias_para_vencer: 30 }); return { id: 9 }; },
  async cambiarEstadoContrato(id, estado) { window.__estado = [id, estado]; const c = contratos.find((x) => x.id === id); c.estado = estado; c.estado_actual = estado; },
  async cobertura() { return [
    { nombre: 'MAIZ', existencia_kg: 25000, kg_contratados_pendientes: 0, contratos_abiertos: 0, consumo_kg_dia: 0, dias_existencia: null, dias_cobertura: null },
    { nombre: 'PASTA DE SOYA', existencia_kg: 980000, kg_contratados_pendientes: 0, contratos_abiertos: 0, consumo_kg_dia: 9000, dias_existencia: 108, dias_cobertura: 108 },
    { nombre: 'SORGO', existencia_kg: 52760, kg_contratados_pendientes: 439790, contratos_abiertos: 2, consumo_kg_dia: 24000, dias_existencia: 2, dias_cobertura: 20 } ]; },
  async granjas() { return [{ id: 3, nombre: 'Durazno', activa: true }, { id: 8, nombre: 'Ramari', activa: true }, { id: 7, nombre: 'Paraíso', activa: true }, { id: 1, nombre: 'La Red', activa: true }, { id: 5, nombre: 'Rodadero', activa: true }, { id: 9, nombre: 'Josefino', activa: false }]; },
  async granjaAreas() { return [{ granja_id: 3, area: 'aves' }, { granja_id: 8, area: 'borregos' }, { granja_id: 1, area: 'cerdos' }, { granja_id: 1, area: 'aves' }, { granja_id: 1, area: 'ganado' }, { granja_id: 5, area: 'cerdos' }, { granja_id: 5, area: 'ganado' }, { granja_id: 7, area: 'aves' }]; },
  async gruposAlmacen() { return [{ id: 1, nombre: 'Sorgo y maíz' }, { id: 2, nombre: 'Soya' }]; },
  async crearMateriaPrima(d) { window.__nuevaMp = d; return { id: 99, nombre: d.nombre.toUpperCase() }; },
  async materiasCatalogo() { return catMp; },
  async actualizarMateria(id, campos) { window.__actualizada = [id, campos]; },
  async crearFormula(d) { window.__nuevaF = d; return { id: d.copiarDe ? 76 : 77, nombre: d.nombre.toUpperCase(), especie: d.especie }; },
  async formulasCatalogo() { return [
    { id: 77, nombre: 'PRUEBA AVES', especie: 'aves', etapa: null, activa: true, revisada: false, creada_por: 'Capturista planta', creada_en: new Date().toISOString(), copiada_de: null, ingredientes: 2, kg_por_tonelada: 1000, ordenes: 1, ultima_orden: f(0) },
    { id: 5, nombre: 'NX FINALIZADOR', especie: 'cerdos', etapa: 'Finalizador', activa: true, revisada: true, ingredientes: 6, kg_por_tonelada: 1000, ordenes: 12, ultima_orden: f(-1) } ]; },
  async ingredientesFormula() { return [{ materia_prima: 'SORGO', kg_por_tonelada: 745, costo_promedio: 5.1 }, { materia_prima: 'PASTA DE SOYA', kg_por_tonelada: 255, costo_promedio: 6.34 }]; },
  async actualizarFormula(id, c) { window.__actF = [id, c]; },
  async clientes() { return [{ id: 1, nombre: 'HUEVERA DEL NORTE', rfc: 'HNO010101AB1' }, { id: 2, nombre: 'OBRADOR LÓPEZ', rfc: null }, { id: 3, nombre: 'SUREXPORT', rfc: null }]; },
  async crearCliente(d) { window.__cliente = d; return { id: 9, nombre: d.nombre, rfc: d.rfc || null }; },
  async empresasFactura() { return [{ id: 1, nombre: 'Pecuaria Real Victoria' }, { id: 2, nombre: 'Maront' }, { id: 3, nombre: 'Humberto Martínez' }]; },
  async calidadesVenta(e) { return ({ huevo: ['Línea', 'Sucio', 'Semisucio', 'Canica/Chico', 'Roto', 'Líquido'], cerdo: ['C1', 'C1.5', 'C2', 'Caídas', 'Canal', 'Línea', 'Chiclanes'], ganado: ['Registro', 'Comercial', 'Desecho'] }[e] || []).map((nombre) => ({ nombre })); },
  async ventas({ especie, cliente, moneda, conSaldo } = {}) { return ventasF.filter((v) => (!especie || v.especie === especie) && (!cliente || String(v.cliente_id) === String(cliente)) && (!moneda || (v.moneda || 'MXN') === moneda) && (!conSaldo || v.saldo > 0)); },
  async presentacionesVenta() { return [{ nombre: '12 x 18 oz', kg_por_caja: 6.12 }, { nombre: '6 oz', kg_por_caja: 2.04 }, { nombre: 'Granel', kg_por_caja: null }]; },
  async productosVenta() { return productosF; },
  async crearProductoVenta(d) { window.__producto = d; const p = { id: 9, ...d, precio_sugerido: null }; return p; },
  async saldosClientes() { return [{ cliente_id: 3, cliente: 'SUREXPORT', rfc: null, moneda: 'USD', vendido: 8110, pagado: 6000, ventas_con_saldo: 2, saldo_ventas: 5110, a_favor: 0, saldo: 5110, venta_mas_antigua: f(-40), ultimo_pago: f(-2) },
    { cliente_id: 1, cliente: 'HUEVERA DEL NORTE', rfc: 'HNO010101AB1', moneda: 'MXN', vendido: 204495, pagado: 0, ventas_con_saldo: 1, saldo_ventas: 104495, a_favor: 5000, saldo: 99495, venta_mas_antigua: f(0), ultimo_pago: null }]; },
  async pagos() { return [{ id: 1, cliente_id: 3, cliente: 'SUREXPORT', fecha: f(-2), monto: 6000, moneda: 'USD', tipo_cambio: 18.5, forma: 'transferencia', banco: 'BBVA', referencia: 'TRF 5521', aplicado: 6000, sin_aplicar: 0, ventas: 'B-099 (6,000.00)', capturado_por: 'Ventas', capturado_en: new Date().toISOString() }]; },
  async aplicacionesPago() { return [{ venta_id: 10, monto: 2000 }]; },
  async registrarPago(p, a, id) { window.__pago = { p, a, id }; return 1; },
  async eliminarPago(id) { window.__pagoEliminado = id; },
  async cuentasBancarias() { return cuentasF; },
  async crearCuentaBancaria(d) { window.__cuenta = d; const c = { id: 9, ...d, activa: true }; return c; },
  async depositos() { return [{ origen: 'venta', fecha: f(0), cliente: 'OBRADOR LÓPEZ', especie: 'huevo', folio: 'H-1', monto: 28000, moneda: 'MXN', cuenta_id: 1, cuenta: 'CAJA (EFECTIVO)', concepto: 'Venta de contado' },
    { origen: 'pago', fecha: f(-2), cliente: 'SUREXPORT', especie: null, folio: 'TRF 5521', monto: 6000, moneda: 'USD', cuenta_id: null, cuenta: null, concepto: 'Pago de cliente' }]; },
  async facturasVenta(id) { return String(id) === '1' ? [{ numero: 'A-100', empresa_factura_id: 1, monto: 100000 }, { numero: 'B-50', empresa_factura_id: 2, monto: 104495 }] : []; },
  async renglonesVenta(id) { if (String(id) === '10') return [{ granja_id: null, presentacion: '12 x 18 oz', calidad: 'Jumbo', cantidad: 120, kg_brutos: 734.4, merma_kg: 4.4, kg_netos: 730, peso_promedio: 6.12, precio_kg: 7, flete_kg: 0, precio_total_kg: 7, importe: 5110, precio_por: 'kg' }];
    if (String(id) === '12') return [{ granja_id: 3, granja: 'Durazno', producto_id: 2, producto: 'GALLINA DE DESECHO (RASTRO)', unidad: 'pieza', cantidad: 1500, kg_brutos: 0, merma_kg: 0, kg_netos: 0, precio_kg: 35, flete_kg: 0, precio_total_kg: 35, importe: 52500, precio_por: 'unidad' }];
    return [{ granja_id: 3, granja: 'Durazno', calidad: 'Línea', cantidad: 300, kg_brutos: 6750, merma_kg: 600, kg_netos: 6150, peso_promedio: 22.5, precio_kg: 28.5, flete_kg: 0.8, precio_total_kg: 29.3, importe: 180195 }]; },
  async guardarVenta(v, r, id) { window.__venta = { v, r, id }; return 1; },
  async eliminarVenta(id) { window.__ventaEliminada = id; },
  enVivo() { return () => {}; },
};
