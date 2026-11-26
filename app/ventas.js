// Ventas: huevo, cerdo, ganado, borregos, berries y generales (abono, gallina a rastro, productos extraordinarios).
// Cada venta = encabezado + renglones. Cobranza (pagos y saldos de clientes) en cobranza.js.
import { api } from './api.js';
import { esc, fmt, hoy, aviso, cargando, errorEn } from './ui.js';
import { sesion } from './sesion.js';
import { normalizar } from './materias.js';
import { pantallaCobranza, irACobrar } from './cobranza.js';

// calidad: 'catalogo' = lista cerrada; 'libre' = texto con sugerencias; null = sin calidad.
const TIPOS = {
  huevo:   { nombre: 'Huevo',     unidad: 'Cajas',    area: 'aves',     calidad: 'catalogo', obligaCalidad: true, destino: true, merma: 2, pesadaUnica: true },
  cerdo:   { nombre: 'Cerdo',     unidad: 'Cerdos',   area: 'cerdos',   calidad: 'catalogo', obligaCalidad: true, muertos: true },
  ganado:  { nombre: 'Ganado',    unidad: 'Cabezas',  area: 'ganado',   calidad: 'catalogo', obligaCalidad: true },
  borrego: { nombre: 'Borregos',  unidad: 'Cabezas',  area: 'borregos', calidad: 'libre', obligaCalidad: true },
  berries: { nombre: 'Berries',   unidad: 'Cajas',    area: 'berries',  calidad: 'libre', presentacion: true, mermaRenglon: true,
             precioPor: [['kg', 'Por kg'], ['unidad', 'Por caja']], moneda: true, folioExterno: true, credito: true },
  general: { nombre: 'Generales', unidad: 'Cantidad', area: null,       calidad: null, producto: true,
             precioPor: [['unidad', 'Por unidad'], ['kg', 'Por kg']], moneda: true },
};
const ESTADOS = ['Aguascalientes', 'Baja California', 'Baja California Sur', 'Campeche', 'Chiapas', 'Chihuahua', 'Ciudad de México', 'Coahuila',
  'Colima', 'Durango', 'Estado de México', 'Guanajuato', 'Guerrero', 'Hidalgo', 'Jalisco', 'Michoacán', 'Morelos', 'Nayarit', 'Nuevo León', 'Oaxaca',
  'Puebla', 'Querétaro', 'Quintana Roo', 'San Luis Potosí', 'Sinaloa', 'Sonora', 'Tabasco', 'Tamaulipas', 'Tlaxcala', 'Veracruz', 'Yucatán', 'Zacatecas'];
const UNIDADES_PRODUCTO = ['pieza', 'kg', 'tonelada', 'costal', 'caja', 'viaje', 'servicio', 'lote'];
const AREAS = ['aves', 'cerdos', 'ganado', 'borregos', 'berries', 'planta', 'otro'];
const numero = (v) => (v === '' || v == null ? null : Number(v));
const n2 = new Intl.NumberFormat('es-MX', { maximumFractionDigits: 2 });
export const dinero = (v, moneda) => (moneda === 'USD' ? `US$${n2.format(Number(v) || 0)}` : fmt.dinero(v));

export function pantallaVentas(cont, seccion = 'huevo') {
  if (seccion !== 'cobranza' && !TIPOS[seccion]) seccion = 'huevo';
  const pestanas = `<nav class="pestanas" aria-label="Tipo de venta">
      ${Object.entries(TIPOS).map(([k, v]) => `<a href="#/ventas/${k}" class="${k === seccion ? 'activo' : ''}">${v.nombre}</a>`).join('')}
      <a href="#/ventas/cobranza" class="${seccion === 'cobranza' ? 'activo' : ''}">Cobranza y saldos</a>
    </nav>`;
  if (seccion === 'cobranza') return pantallaCobranza(cont, pestanas);
  const especie = seccion;
  const t = TIPOS[especie];
  let vivo = true;
  const puede = sesion.puedeCapturar('ventas');
  cont.innerHTML = `
    <h1>Ventas</h1>
    ${pestanas}
    ${especie === 'general' ? '<p class="nota">Abono, gallina de desecho a rastro y cualquier otro producto que se venda. Si el producto no está en la lista, agrégalo desde el renglón.</p>' : ''}
    ${puede ? '<div id="zona-venta"></div>' : '<div class="caja caja-info">Puedes consultar las ventas. Para capturarlas pide permiso de Ventas al administrador.</div>'}
    <h2>Historial de ventas ${especie === 'general' ? 'generales' : `de ${t.nombre.toLowerCase()}`}</h2>
    <form class="filtros" id="filtros-ventas">
      <label>Desde<input type="date" name="desde"></label>
      <label>Hasta<input type="date" name="hasta"></label>
      <label>Cliente<select name="cliente"><option value="">Todos</option></select></label>
      <label class="casilla"><input type="checkbox" name="saldo"> Solo con saldo pendiente</label>
    </form>
    <div id="historial-ventas"></div>`;
  const filtros = cont.querySelector('#filtros-ventas');
  filtros.desde.value = hoy(-30);
  filtros.hasta.value = hoy();
  const hist = cont.querySelector('#historial-ventas');
  let editor = null;
  const pintar = () => historial(hist, especie, filtros, () => vivo, (v) => editor?.editar(v));

  (async () => {
    try {
      const [clientes, empresas, calidades, granjas, granjaAreas, previas, presentaciones, productos] = await Promise.all([
        api.clientes(), api.empresasFactura(), api.calidadesVenta(especie), api.granjas(), api.granjaAreas(),
        api.ventas({ especie, desde: hoy(-365) }),
        t.presentacion ? api.presentacionesVenta(especie) : [], t.producto ? api.productosVenta() : [],
      ]);
      if (!vivo) return;
      filtros.cliente.insertAdjacentHTML('beforeend', clientes.map((c) => `<option value="${c.id}">${esc(c.nombre)}</option>`).join(''));
      if (puede) {
        const ids = new Set(granjaAreas.filter((x) => x.area === t.area).map((x) => x.granja_id));
        const granjasArea = granjas.filter((g) => ids.has(g.id) && g.activa);
        // Calidades y presentaciones libres: sugerencias del catálogo más las ya usadas.
        const separar = (k) => previas.flatMap((v) => (v[k] || '').split(', ').filter(Boolean));
        const sugCalidad = [...new Set([...calidades.map((c) => c.nombre), ...separar('calidades')])];
        const nombresPres = new Set(presentaciones.map((p) => p.nombre));
        const sugPres = [...presentaciones, ...[...new Set(separar('presentaciones'))].filter((p) => !nombresPres.has(p)).map((nombre) => ({ nombre }))];
        // Destinos ya usados (previas viene de la más reciente a la más vieja): ciudad + estado → último aumento.
        const destinos = new Map();
        for (const v of previas) {
          if (!v.destino_ciudad) continue;
          const k = normalizar(`${v.destino_ciudad}|${v.destino_estado || ''}`);
          if (!destinos.has(k)) destinos.set(k, { ciudad: v.destino_ciudad, estado: v.destino_estado, aumento: v.aumento_centavos_kg, colonias: new Set() });
          if (v.destino_colonia) destinos.get(k).colonias.add(v.destino_colonia);
        }
        editor = formulario(cont.querySelector('#zona-venta'), especie, {
          clientes, destinos, empresas, calidades: calidades.map((c) => c.nombre), sugCalidad, presentaciones: sugPres, productos,
          granjas: granjasArea.length ? granjasArea : granjas.filter((g) => g.activa),
        }, pintar);
      }
    } catch (e) { aviso(e.message, 'error'); }
  })();
  filtros.addEventListener('change', pintar);
  cargando(hist);
  pintar();
  const soltar = api.enVivo('ventas', pintar);
  return () => { vivo = false; soltar(); };
}

// ---------- Formulario ----------

function formulario(zona, especie, { clientes, destinos = new Map(), empresas, calidades, sugCalidad, presentaciones, productos, granjas }, alGuardar) {
  const t = TIPOS[especie];
  const NUEVO = '__nuevo__';
  const conMerma = Boolean(t.merma || t.mermaRenglon);
  const listaCalidad = t.calidad === 'catalogo'
    ? (sel) => `<select name="calidad" aria-label="Calidad"><option value="">Elige…</option>${calidades.map((c) => `<option ${c === sel ? 'selected' : ''}>${esc(c)}</option>`).join('')}</select>`
    : (sel) => `<input name="calidad" list="calidades-${especie}" maxlength="40" value="${esc(sel || '')}" aria-label="Calidad" placeholder="Calidad">`;
  const opcionesProducto = (sel) => `<option value="">Elige…</option>${productos.map((p) => `<option value="${p.id}" ${String(p.id) === String(sel) ? 'selected' : ''}>${esc(p.nombre)}</option>`).join('')}<option value="${NUEVO}">+ Producto nuevo…</option>`;
  const precioLabel = t.precioPor ? 'Precio' : 'Precio $/kg';

  zona.innerHTML = `
    <form class="tarjeta formulario" id="form-venta" autocomplete="off">
      <h2 id="titulo-venta">Registrar venta ${especie === 'general' ? 'general' : `de ${t.nombre.toLowerCase()}`}</h2>
      ${t.calidad === 'libre' ? `<datalist id="calidades-${especie}">${sugCalidad.map((c) => `<option value="${esc(c)}">`).join('')}</datalist>` : ''}
      ${t.presentacion ? `<datalist id="presentaciones-${especie}">${presentaciones.map((p) => `<option value="${esc(p.nombre)}">${p.kg_por_caja ? `${n2.format(p.kg_por_caja)} kg por caja` : ''}</option>`).join('')}</datalist>` : ''}
      <div class="rejilla">
        <label>Fecha<input type="date" name="fecha" value="${hoy()}" required></label>
        <label class="ancho2">Cliente<select name="cliente" required></select><small class="ayuda" id="rfc-cliente"></small></label>
        ${t.destino ? `<datalist id="ciudades-venta">${[...new Set([...destinos.values()].map((d) => d.ciudad))].map((c) => `<option value="${esc(c)}">`).join('')}</datalist>
          <datalist id="colonias-venta">${[...new Set([...destinos.values()].flatMap((d) => [...d.colonias]))].map((c) => `<option value="${esc(c)}">`).join('')}</datalist>
          <label>Colonia destino<input name="destino_colonia" maxlength="80" list="colonias-venta" placeholder="Opcional"></label>
          <label>Ciudad destino<input name="destino_ciudad" maxlength="80" list="ciudades-venta"></label>
          <label>Estado destino<select name="destino_estado"><option value="">Elige…</option>${ESTADOS.map((e) => `<option>${e}</option>`).join('')}</select></label>
          <label>Aumento al destino (centavos/kg)<input type="number" name="aumento_centavos_kg" min="0" step="1" inputmode="decimal" placeholder="Ej. 40">
            <small class="ayuda" id="ayuda-aumento">Solo dato de referencia: no cambia el precio ni el total</small></label>`
          : '<label>Destino<input name="destino" maxlength="120" placeholder="Ciudad / lugar"></label>'}
        <div class="ancho-total caja caja-info oculto" id="nuevo-cliente">
          <div class="rejilla">
            <label class="ancho2">Nombre del cliente<input name="nc_nombre" maxlength="120"></label>
            <label>RFC<input name="nc_rfc" maxlength="13" placeholder="Opcional"></label>
            <div class="en-linea"><button type="button" class="boton boton-chico boton-primario" id="btn-nc">Agregar cliente</button>
              <button type="button" class="boton boton-chico" id="btn-nc-cancelar">Cancelar</button></div>
          </div>
          <div class="parecidas oculto" id="nc-parecidos"></div>
        </div>
        <label>Folio / remisión<input name="folio" maxlength="40" placeholder="Opcional"></label>
        ${t.folioExterno ? '<label>Folio del cliente<input name="folio_externo" maxlength="40" placeholder="Opcional"></label>' : ''}
        ${t.moneda ? `<label>Moneda<select name="moneda"><option value="MXN">Pesos (MXN)</option><option value="USD">Dólares (USD)</option></select></label>
          <label class="campo-usd oculto">Tipo de cambio<input type="number" name="tipo_cambio" min="0" step="0.0001" inputmode="decimal" placeholder="Opcional"></label>` : ''}
        <label>Tipo de venta<select name="tipo_pago"><option value="factura">Con factura</option><option value="efectivo">Efectivo</option></select></label>
        <label class="campo-factura">Razón social<select name="empresa"><option value="">Elige…</option>${empresas.map((e) => `<option value="${e.id}">${esc(e.nombre)}</option>`).join('')}</select></label>
        <label>Pago<select name="forma_pago"><option value="contado">De contado</option><option value="credito" ${t.credito ? 'selected' : ''}>Crédito / con anticipo</option></select></label>
        <label class="campo-credito oculto">Anticipo<input type="number" name="anticipo" min="0" step="0.01" inputmode="decimal" value="0"></label>
        ${t.pesadaUnica ? '<label>Kg brutos de báscula<input type="number" name="kg_bascula" min="0" step="0.01" inputmode="decimal" placeholder="Toda la venta"><small class="ayuda">Una sola pesada de todas las cajas; se reparte por cajas</small></label>' : ''}
        ${t.merma ? `<label>Merma kg por caja<input type="number" name="merma_kg_caja" min="0" step="0.01" inputmode="decimal" value="${t.merma}"></label>` : ''}
        ${t.muertos ? '<label>Muertos<input type="number" name="muertos" min="0" step="1" inputmode="numeric" value="0"></label>' : ''}
        <div class="ancho-total campo-factura">
          <b>Facturas</b> <small class="ayuda">Una venta puede llevar varias facturas; el número se puede agregar después.</small>
          <div class="tabla-scroll"><table class="tabla-captura"><thead><tr><th>Número</th><th>Razón social</th><th class="num">Monto (opcional)</th><th></th></tr></thead>
            <tbody id="facturas-venta"></tbody></table></div>
          <button type="button" class="boton boton-chico" id="btn-factura">+ Otra factura</button>
        </div>
      </div>

      <h3>${t.merma ? 'Cajas por granja y calidad' : t.producto ? 'Productos' : 'Detalle'}</h3>
      <div class="tabla-scroll"><table class="tabla-captura">
        <thead><tr>${t.producto ? '<th>Producto</th>' : ''}<th>Granja</th>${t.presentacion ? '<th>Presentación</th>' : ''}${t.calidad ? '<th>Calidad</th>' : ''}
          <th class="num">${t.unidad}</th><th class="num">Kg ${t.pesadaUnica ? 'brutos (repartidos)' : t.merma ? 'brutos (báscula)' : conMerma ? 'brutos' : t.producto ? '(opcional)' : 'totales'}</th>${t.producto ? '' : '<th class="num">Peso prom.</th>'}
          ${conMerma ? '<th class="num">Merma kg</th><th class="num">Kg netos</th>' : ''}${t.precioPor ? '<th>Cobrar</th>' : ''}<th class="num">${precioLabel}</th><th class="num">Importe</th><th></th></tr></thead>
        <tbody id="renglones-venta"></tbody>
      </table></div>
      <button type="button" class="boton boton-chico" id="btn-renglon-venta">+ Agregar renglón</button>
      ${t.producto ? `<div class="caja caja-info oculto margen-arriba" id="nuevo-producto">
          <div class="rejilla">
            <label class="ancho2">Producto nuevo<input name="np_nombre" maxlength="80" placeholder="Ej. COSTALES VACÍOS"></label>
            <label>Se vende por<select name="np_unidad">${UNIDADES_PRODUCTO.map((u) => `<option>${u}</option>`).join('')}</select></label>
            <label>Área<select name="np_area">${AREAS.map((a) => `<option>${a}</option>`).join('')}</select></label>
            <div class="en-linea"><button type="button" class="boton boton-chico boton-primario" id="btn-np">Agregar producto</button>
              <button type="button" class="boton boton-chico" id="btn-np-cancelar">Cancelar</button></div>
          </div>
          <div class="parecidas oculto" id="np-parecidos"></div>
        </div>` : ''}

      <div class="rejilla margen-arriba">
        <label>Descuento<input type="number" name="descuento" min="0" step="0.01" inputmode="decimal" value="0"></label>
        <label class="ancho2">Motivo del descuento<input name="motivo_descuento" maxlength="200" placeholder="${t.muertos ? 'Por muertos, por calidad…' : 'Por cajas, por calidad…'}"></label>
        <label>Notas<input name="notas" maxlength="300"></label>
      </div>
      <div class="kpis" id="totales-venta"></div>
      <button class="boton boton-primario" type="submit">Guardar venta</button>
      <button class="boton oculto" type="button" id="btn-cancelar-venta">Cancelar edición</button>
      <button class="boton boton-peligro oculto" type="button" id="btn-eliminar-venta">Eliminar venta</button>
    </form>`;
  const form = zona.querySelector('#form-venta');
  const cuerpo = form.querySelector('#renglones-venta');
  const moneda = () => (t.moneda ? form.moneda.value : 'MXN');

  // ---- Clientes con RFC automático ----
  const pintarClientes = (sel = '') => {
    form.cliente.innerHTML = `<option value="">Elige…</option>${clientes.map((c) => `<option value="${c.id}">${esc(c.nombre)}</option>`).join('')}<option value="${NUEVO}">+ Agregar cliente nuevo…</option>`;
    form.cliente.value = sel;
    mostrarRfc();
  };
  function mostrarRfc() {
    const c = clientes.find((x) => String(x.id) === form.cliente.value);
    form.querySelector('#rfc-cliente').textContent = c ? (c.rfc ? `RFC ${c.rfc}` : 'Sin RFC registrado') : '';
  }
  const cajaNc = form.querySelector('#nuevo-cliente');
  form.cliente.addEventListener('change', () => {
    const nuevo = form.cliente.value === NUEVO;
    cajaNc.classList.toggle('oculto', !nuevo);
    if (nuevo) form.nc_nombre.focus();
    mostrarRfc();
  });
  const sugerir = (lista, texto, zonaSug, attr) => {
    const t2 = normalizar(texto);
    const hallados = t2.length < 3 ? [] : lista.filter((c) => normalizar(c.nombre).includes(t2) || t2.includes(normalizar(c.nombre))).slice(0, 5);
    zonaSug.classList.toggle('oculto', !hallados.length);
    zonaSug.innerHTML = hallados.length ? `<span>¿Es alguno de estos? </span>${hallados.map((c) => `<button type="button" class="chip" data-${attr}="${c.id}">${esc(c.nombre)}</button>`).join('')}` : '';
  };
  form.nc_nombre.addEventListener('input', () => sugerir(clientes, form.nc_nombre.value, form.querySelector('#nc-parecidos'), 'cliente'));
  form.querySelector('#nc-parecidos').addEventListener('click', (ev) => {
    const b = ev.target.closest('[data-cliente]');
    if (b) { cajaNc.classList.add('oculto'); pintarClientes(b.dataset.cliente); }
  });
  form.querySelector('#btn-nc-cancelar').addEventListener('click', () => { cajaNc.classList.add('oculto'); pintarClientes(''); });
  form.querySelector('#btn-nc').addEventListener('click', async () => {
    const nombre = form.nc_nombre.value.trim().toUpperCase().replace(/\s+/g, ' ');
    if (!nombre) return form.nc_nombre.focus();
    const existe = clientes.find((c) => normalizar(c.nombre) === normalizar(nombre));
    if (existe) { aviso(`Ya existe: ${existe.nombre}.`); cajaNc.classList.add('oculto'); return pintarClientes(String(existe.id)); }
    try {
      const c = await api.crearCliente({ nombre, rfc: form.nc_rfc.value.trim().toUpperCase() });
      clientes.push(c); clientes.sort((a, b) => a.nombre.localeCompare(b.nombre));
      cajaNc.classList.add('oculto'); form.nc_nombre.value = ''; form.nc_rfc.value = '';
      pintarClientes(String(c.id));
      aviso(`Cliente ${c.nombre} agregado.`);
    } catch (e) { aviso(e.message, 'error'); }
  });
  form.nc_nombre.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') { ev.preventDefault(); form.querySelector('#btn-nc').click(); } });
  pintarClientes();

  // ---- Factura / crédito / moneda ----
  const mostrarCampos = () => {
    form.querySelectorAll('.campo-factura').forEach((x) => x.classList.toggle('oculto', form.tipo_pago.value !== 'factura'));
    form.querySelectorAll('.campo-credito').forEach((x) => x.classList.toggle('oculto', form.forma_pago.value !== 'credito'));
    form.querySelectorAll('.campo-usd').forEach((x) => x.classList.toggle('oculto', moneda() !== 'USD'));
  };
  form.tipo_pago.addEventListener('change', mostrarCampos);
  // Destino ya usado: se completa el estado y se propone el último aumento registrado ahí.
  function mostrarDestino() {
    if (!t.destino) return null;
    const ciudad = normalizar(form.destino_ciudad.value);
    const d = [...destinos.entries()].find(([k]) => k === normalizar(`${form.destino_ciudad.value}|${form.destino_estado.value}`))?.[1]
      || (!form.destino_estado.value ? [...destinos.values()].find((x) => normalizar(x.ciudad) === ciudad) : null);
    form.querySelector('#ayuda-aumento').textContent = d && d.aumento != null
      ? `Último aumento a ${d.ciudad}: ${n2.format(d.aumento)} centavos/kg. Solo dato de referencia.` : 'Solo dato de referencia: no cambia el precio ni el total';
    return d;
  }
  if (t.destino) {
    const alCambiar = () => {
      const d = mostrarDestino();
      if (!d) return;
      if (!form.destino_estado.value && d.estado) form.destino_estado.value = d.estado;
      if (form.aumento_centavos_kg.value === '' && d.aumento != null) form.aumento_centavos_kg.value = d.aumento;
    };
    form.destino_ciudad.addEventListener('change', alCambiar);
    form.destino_estado.addEventListener('change', alCambiar);
  }
  form.forma_pago.addEventListener('change', mostrarCampos);
  if (t.moneda) form.moneda.addEventListener('change', mostrarCampos);
  mostrarCampos();

  // ---- Facturas ----
  const cuerpoFact = form.querySelector('#facturas-venta');
  const filaFactura = (f = {}) => `<tr>
      <td><input name="f_numero" maxlength="60" value="${esc(f.numero || '')}" placeholder="Si ya se emitió" aria-label="Número de factura"></td>
      <td><select name="f_empresa" aria-label="Razón social de la factura"><option value="">La de la venta</option>${empresas.map((e) => `<option value="${e.id}" ${String(e.id) === String(f.empresa_factura_id ?? '') ? 'selected' : ''}>${esc(e.nombre)}</option>`).join('')}</select></td>
      <td class="num"><input type="number" class="celda-num" name="f_monto" min="0" step="0.01" inputmode="decimal" value="${f.monto ?? ''}" aria-label="Monto de la factura"></td>
      <td><button type="button" class="boton boton-chico" data-quitar-factura>Quitar</button></td></tr>`;
  const leerFacturas = () => [...cuerpoFact.querySelectorAll('tr')].map((tr) => ({
    numero: tr.querySelector('[name=f_numero]').value.trim(), empresa_factura_id: tr.querySelector('[name=f_empresa]').value,
    monto: tr.querySelector('[name=f_monto]').value })).filter((f) => f.numero || f.monto);
  form.querySelector('#btn-factura').addEventListener('click', () => { cuerpoFact.insertAdjacentHTML('beforeend', filaFactura()); });
  cuerpoFact.addEventListener('click', (ev) => {
    if (!ev.target.closest('[data-quitar-factura]')) return;
    if (cuerpoFact.children.length > 1) ev.target.closest('tr').remove(); else cuerpoFact.innerHTML = filaFactura();
    actualizar();
  });
  cuerpoFact.innerHTML = filaFactura();

  // ---- Renglones ----
  const unidadDe = (id) => productos.find((p) => String(p.id) === String(id))?.unidad || '';
  const renglon = (r = {}) => {
    const kg = r.kg_brutos != null && Number(r.kg_brutos) !== 0 ? r.kg_brutos : r.kg ?? '';
    const precioPor = r.precio_por || (t.precioPor ? t.precioPor[0][0] : 'kg');
    return `<tr>
      ${t.producto ? `<td><select name="producto" aria-label="Producto">${opcionesProducto(r.producto_id)}</select></td>` : ''}
      <td><select name="granja" aria-label="Granja"><option value="">—</option>${granjas.map((g) => `<option value="${g.id}" ${String(r.granja_id) === String(g.id) ? 'selected' : ''}>${esc(g.nombre)}</option>`).join('')}</select></td>
      ${t.presentacion ? `<td><input name="presentacion" list="presentaciones-${especie}" maxlength="40" value="${esc(r.presentacion || '')}" aria-label="Presentación" placeholder="12 x 18 oz, granel…"></td>` : ''}
      ${t.calidad ? `<td>${listaCalidad(r.calidad)}</td>` : ''}
      <td class="num"><input type="number" class="celda-num" name="cantidad" min="0" step="any" inputmode="decimal" value="${r.cantidad ?? ''}" aria-label="${t.unidad}"><small class="unidad-prod">${esc(unidadDe(r.producto_id))}</small></td>
      <td class="num">${t.pesadaUnica ? '<span class="kg-repartido">—</span>' : `<input type="number" class="celda-num" name="kg" min="0" step="0.01" inputmode="decimal" value="${kg}" data-auto="${kg === '' ? '1' : '0'}" aria-label="Kg">`}</td>
      ${t.producto ? '' : '<td class="num prom">—</td>'}
      ${t.mermaRenglon ? `<td class="num"><input type="number" class="celda-num" name="merma" min="0" step="0.01" inputmode="decimal" value="${Number(r.merma_kg) ? r.merma_kg : ''}" aria-label="Merma kg"></td><td class="num netos">—</td>`
        : t.merma ? '<td class="num merma">—</td><td class="num netos">—</td>' : ''}
      ${t.precioPor ? `<td><select name="precio_por" aria-label="Cobrar">${t.precioPor.map(([v, n]) => `<option value="${v}" ${v === precioPor ? 'selected' : ''}>${n}</option>`).join('')}</select></td>` : ''}
      <td class="num"><input type="number" class="celda-num" name="precio" min="0" step="0.0001" inputmode="decimal" value="${r.precio_kg ?? ''}" aria-label="Precio"></td>
      <td class="num importe">—</td>
      <td><button type="button" class="boton boton-chico" data-quitar-renglon aria-label="Quitar renglón">Quitar</button></td>
    </tr>`;
  };
  const leer = () => {
    const merma = t.merma ? numero(form.merma_kg_caja.value) || 0 : 0;
    // Pesada única: kg de báscula repartidos por cajas (igual que en la base: el último renglón se lleva el redondeo).
    const trs = [...cuerpo.querySelectorAll('tr')];
    const bascula = t.pesadaUnica ? numero(form.kg_bascula.value) : null;
    const cajasTot = trs.reduce((x, tr) => x + (numero(tr.querySelector('[name=cantidad]').value) || 0), 0);
    let acumulado = 0;
    const ultimo = trs.map((tr) => numero(tr.querySelector('[name=cantidad]').value) || 0).findLastIndex((c) => c > 0);
    const filas = trs.map((tr, i) => {
      const v = (n) => tr.querySelector(`[name=${n}]`)?.value ?? '';
      const cantidad = numero(v('cantidad')) || 0, precio = numero(v('precio'));
      let kg = numero(v('kg'));
      if (t.pesadaUnica) {
        kg = bascula && cajasTot && cantidad ? (i === ultimo ? Math.round((bascula - acumulado) * 100) / 100 : Math.round(bascula * cantidad / cajasTot * 100) / 100) : null;
        acumulado += kg || 0;
        tr.querySelector('.kg-repartido').textContent = kg != null ? fmt.kg(kg) : '—';
      }
      const precio_por = t.precioPor ? v('precio_por') : 'kg';
      const mermaKg = t.mermaRenglon ? numero(v('merma')) || 0 : cantidad * merma;
      const netos = kg != null ? kg - mermaKg : null;
      const importe = precio == null ? 0 : precio_por === 'unidad' ? cantidad * precio : (netos || 0) * precio;
      return { tr, granja_id: numero(v('granja')), producto_id: numero(v('producto') === NUEVO ? '' : v('producto')), presentacion: v('presentacion').trim(),
        calidad: v('calidad').trim(), cantidad, kg, precio_kg: precio, precio_por, mermaKg, netos, importe };
    });
    return { filas };
  };
  const actualizar = () => {
    const { filas } = leer();
    const m = moneda();
    let cant = 0, kg = 0, netos = 0, importe = 0;
    for (const f of filas) {
      const prom = f.tr.querySelector('.prom');
      if (prom) prom.textContent = f.cantidad && f.kg ? `${n2.format(f.kg / f.cantidad)} kg` : '—';
      if (t.merma) f.tr.querySelector('.merma').textContent = f.cantidad ? fmt.kg(f.mermaKg) : '—';
      if (conMerma) f.tr.querySelector('.netos').textContent = f.netos != null ? fmt.kg(f.netos) : '—';
      f.tr.querySelector('.importe').textContent = f.importe ? dinero(f.importe, m) : '—';
      cant += f.cantidad; kg += f.kg || 0; netos += f.netos || 0; importe += f.importe;
    }
    const descuento = numero(form.descuento.value) || 0;
    const total = importe - descuento;
    const anticipo = form.forma_pago.value === 'credito' ? numero(form.anticipo.value) || 0 : 0;
    const saldo = form.forma_pago.value === 'credito' ? Math.max(total - anticipo, 0) : 0;
    form.querySelector('#totales-venta').innerHTML = `
      <div class="kpi"><span>${t.unidad}</span><b>${n2.format(cant)}</b><small>${cant && kg && !t.producto ? `peso promedio ${n2.format(kg / cant)} kg` : ''}</small></div>
      ${kg || !t.producto ? `<div class="kpi"><span>Kg ${conMerma ? 'netos' : 'totales'}</span><b>${fmt.kg(netos)}</b><small>${conMerma ? `${fmt.kg(kg)} brutos − ${fmt.kg(kg - netos)} merma` : ''}</small></div>` : ''}
      <div class="kpi"><span>Total ${t.muertos || t.merma ? 'de factura' : ''}</span><b>${dinero(total, m)}</b><small>${descuento ? `${dinero(importe, m)} − descuento ${dinero(descuento, m)}` : ''}${netos ? ` · ${dinero(total / netos, m)}/kg` : ''}</small></div>
      ${((fs) => form.tipo_pago.value === 'factura' && fs.some((f) => numero(f.monto)) ? ((fac) => `<div class="kpi ${Math.abs(fac - total) > 0.5 ? 'kpi-alerta' : ''}"><span>Facturado</span><b>${dinero(fac, m)}</b><small>${fs.length} factura${fs.length === 1 ? '' : 's'}${Math.abs(fac - total) > 0.5 ? (fac < total ? ` · falta facturar ${dinero(total - fac, m)}` : ` · facturado de más ${dinero(fac - total, m)}`) : ''}</small></div>`)(fs.reduce((x, f) => x + (numero(f.monto) || 0), 0)) : '')(leerFacturas())}
      ${form.forma_pago.value === 'credito' ? `<div class="kpi"><span>Saldo</span><b>${dinero(saldo, m)}</b><small>anticipo ${dinero(anticipo, m)}</small></div>` : ''}`;
  };
  // Berries: kg = cajas × kg por caja de la presentación, mientras no se escriban los kg a mano.
  const kgAuto = (tr) => {
    if (!t.presentacion) return;
    const kgIn = tr.querySelector('[name=kg]');
    if (kgIn.dataset.auto !== '1') return;
    const p = presentaciones.find((x) => normalizar(x.nombre) === normalizar(tr.querySelector('[name=presentacion]').value));
    const cajas = numero(tr.querySelector('[name=cantidad]').value);
    kgIn.value = p?.kg_por_caja && cajas ? Math.round(cajas * p.kg_por_caja * 100) / 100 : '';
  };
  cuerpo.addEventListener('input', (ev) => {
    const tr = ev.target.closest('tr');
    if (ev.target.name === 'kg') ev.target.dataset.auto = ev.target.value === '' ? '1' : '0';
    if (ev.target.name === 'cantidad' || ev.target.name === 'presentacion') kgAuto(tr);
  });
  form.addEventListener('input', actualizar);
  form.addEventListener('change', actualizar);
  form.querySelector('#btn-renglon-venta').addEventListener('click', () => {
    const ultimo = cuerpo.lastElementChild;
    cuerpo.insertAdjacentHTML('beforeend', renglon({ granja_id: ultimo?.querySelector('[name=granja]').value, presentacion: ultimo?.querySelector('[name=presentacion]')?.value }));
    actualizar();
  });
  cuerpo.addEventListener('click', (ev) => {
    if (!ev.target.closest('[data-quitar-renglon]')) return;
    if (cuerpo.children.length > 1) ev.target.closest('tr').remove(); else aviso('La venta necesita al menos un renglón.', 'error');
    actualizar();
  });

  // ---- Productos (ventas generales) ----
  let filaProducto = null;
  if (t.producto) {
    const cajaNp = form.querySelector('#nuevo-producto');
    const cerrarNp = () => { cajaNp.classList.add('oculto'); form.np_nombre.value = ''; filaProducto = null; };
    const elegirProducto = (tr, id) => {
      tr.querySelector('[name=producto]').value = String(id);
      const p = productos.find((x) => String(x.id) === String(id));
      tr.querySelector('.unidad-prod').textContent = p?.unidad || '';
      tr.querySelector('[name=precio_por]').value = p?.unidad === 'kg' ? 'kg' : 'unidad';
      if (p?.precio_sugerido && !tr.querySelector('[name=precio]').value) tr.querySelector('[name=precio]').value = p.precio_sugerido;
      actualizar();
    };
    cuerpo.addEventListener('change', (ev) => {
      if (ev.target.name !== 'producto') return;
      const tr = ev.target.closest('tr');
      if (ev.target.value === NUEVO) { filaProducto = tr; cajaNp.classList.remove('oculto'); form.np_nombre.focus(); return; }
      elegirProducto(tr, ev.target.value);
    });
    form.np_nombre.addEventListener('input', () => sugerir(productos, form.np_nombre.value, form.querySelector('#np-parecidos'), 'producto'));
    form.querySelector('#np-parecidos').addEventListener('click', (ev) => {
      const b = ev.target.closest('[data-producto]');
      if (b && filaProducto) { const tr = filaProducto; cerrarNp(); elegirProducto(tr, b.dataset.producto); }
    });
    form.querySelector('#btn-np-cancelar').addEventListener('click', () => { if (filaProducto) filaProducto.querySelector('[name=producto]').value = ''; cerrarNp(); });
    form.querySelector('#btn-np').addEventListener('click', async () => {
      const nombre = form.np_nombre.value.trim().toUpperCase().replace(/\s+/g, ' ');
      if (!nombre) return form.np_nombre.focus();
      const tr = filaProducto;
      const existe = productos.find((p) => normalizar(p.nombre) === normalizar(nombre));
      if (existe) { aviso(`Ya existe: ${existe.nombre}.`); cerrarNp(); if (tr) elegirProducto(tr, existe.id); return; }
      try {
        const p = await api.crearProductoVenta({ nombre, unidad: form.np_unidad.value, area: form.np_area.value });
        productos.push(p); productos.sort((a, b) => a.nombre.localeCompare(b.nombre));
        cuerpo.querySelectorAll('[name=producto]').forEach((s) => { const v = s.value === NUEVO ? '' : s.value; s.innerHTML = opcionesProducto(v); });
        cerrarNp();
        if (tr) elegirProducto(tr, p.id);
        aviso(`Producto ${p.nombre} agregado.`);
      } catch (e) { aviso(e.message, 'error'); }
    });
    form.np_nombre.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') { ev.preventDefault(); form.querySelector('#btn-np').click(); } });
  }
  cuerpo.innerHTML = renglon();
  actualizar();

  // ---- Guardar / editar ----
  let editando = null;
  const titulo = form.querySelector('#titulo-venta');
  const tituloNuevo = titulo.textContent;
  const btnCancelar = form.querySelector('#btn-cancelar-venta');
  const btnEliminar = form.querySelector('#btn-eliminar-venta');
  function limpiar() {
    const fecha = form.fecha.value;
    form.reset();
    form.fecha.value = editando ? hoy() : fecha;
    editando = null;
    pintarClientes();
    cuerpo.innerHTML = renglon();
    cuerpoFact.innerHTML = filaFactura();
    titulo.textContent = tituloNuevo;
    form.querySelector('button[type=submit]').textContent = 'Guardar venta';
    btnCancelar.classList.add('oculto'); btnEliminar.classList.add('oculto');
    btnEliminar.dataset.confirmar = ''; btnEliminar.textContent = 'Eliminar venta';
    form.classList.remove('editando');
    mostrarDestino(); mostrarCampos(); actualizar();
  }
  btnCancelar.addEventListener('click', limpiar);
  btnEliminar.addEventListener('click', async () => {
    if (btnEliminar.dataset.confirmar !== 'si') { btnEliminar.dataset.confirmar = 'si'; btnEliminar.textContent = 'Confirmar: eliminar venta'; return; }
    try { await api.eliminarVenta(editando.id); aviso('Venta eliminada.'); limpiar(); alGuardar(); } catch (e) { aviso(e.message, 'error'); }
  });

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    if (!form.cliente.value || form.cliente.value === NUEVO) return aviso('Elige el cliente (o agrégalo).', 'error');
    if (form.tipo_pago.value === 'factura' && !form.empresa.value) return aviso('Elige la razón social con la que se factura.', 'error');
    const { filas } = leer();
    const usados = filas.filter((f) => f.kg || f.cantidad || f.precio_kg != null || f.producto_id);
    if (!usados.length) return aviso('Captura al menos un renglón.', 'error');
    if (t.producto && usados.some((f) => !f.producto_id)) return aviso('Elige el producto de cada renglón.', 'error');
    if (usados.some((f) => f.precio_kg == null)) return aviso('Captura el precio de cada renglón.', 'error');
    if (t.pesadaUnica && !numero(form.kg_bascula.value)) return aviso('Captura los kg brutos de la báscula.', 'error');
    if (t.pesadaUnica && usados.some((f) => !f.cantidad)) return aviso('Captura las cajas de cada renglón.', 'error');
    if (usados.some((f) => f.precio_por === 'kg' && !f.kg)) return aviso('Captura los kg de cada renglón que se cobra por kg.', 'error');
    if (usados.some((f) => f.precio_por === 'unidad' && !f.cantidad)) return aviso(`Captura la cantidad (${t.unidad.toLowerCase()}) de cada renglón que se cobra por ${t.producto ? 'unidad' : 'caja'}.`, 'error');
    if (t.obligaCalidad && usados.some((f) => !f.calidad)) return aviso('Captura la calidad de cada renglón.', 'error');
    if (usados.some((f) => f.kg && f.netos <= 0)) return aviso('La merma es mayor que los kg en algún renglón. Revisa cajas y kg.', 'error');
    const venta = {
      especie, fecha: form.fecha.value, cliente_id: Number(form.cliente.value),
      destino: t.destino ? [form.destino_colonia.value.trim(), form.destino_ciudad.value.trim(), form.destino_estado.value].filter(Boolean).join(', ') : form.destino.value.trim(),
      destino_colonia: t.destino ? form.destino_colonia.value.trim() : '', destino_ciudad: t.destino ? form.destino_ciudad.value.trim() : '',
      destino_estado: t.destino ? form.destino_estado.value : '', aumento_centavos_kg: t.destino ? form.aumento_centavos_kg.value : '',
      folio: form.folio.value.trim(), folio_externo: t.folioExterno ? form.folio_externo.value.trim() : '',
      moneda: moneda(), tipo_cambio: t.moneda && moneda() === 'USD' ? form.tipo_cambio.value : '',
      tipo_pago: form.tipo_pago.value, empresa_factura_id: form.tipo_pago.value === 'factura' ? form.empresa.value : '',
      facturas: form.tipo_pago.value === 'factura' ? leerFacturas() : [],
      kg_bascula: t.pesadaUnica ? form.kg_bascula.value : '',
      forma_pago: form.forma_pago.value, anticipo: form.forma_pago.value === 'credito' ? numero(form.anticipo.value) || 0 : 0,
      flete_kg: 0, flete_caja: 0, merma_kg_caja: t.merma ? numero(form.merma_kg_caja.value) || 0 : 0,
      muertos: t.muertos ? numero(form.muertos.value) || 0 : 0, descuento: numero(form.descuento.value) || 0,
      motivo_descuento: form.motivo_descuento.value.trim(), notas: form.notas.value.trim(),
    };
    const renglones = usados.map((f) => ({
      granja_id: f.granja_id || '', calidad: f.calidad, cantidad: f.cantidad, kg: f.kg ?? '', precio_kg: f.precio_kg,
      presentacion: f.presentacion, producto_id: f.producto_id || '', precio_por: f.precio_por, merma_kg: t.mermaRenglon ? f.mermaKg : '',
    }));
    const boton = form.querySelector('button[type=submit]');
    boton.disabled = true;
    try {
      await api.guardarVenta(venta, renglones, editando?.id ?? null);
      const cliente = form.cliente.selectedOptions[0]?.textContent;
      aviso(editando ? `Venta corregida (${cliente}).` : `Venta guardada: ${cliente}.`);
      limpiar();
      alGuardar();
    } catch (e) { aviso(e.message, 'error'); } finally { boton.disabled = false; }
  });

  async function editar(v) {
    try {
      const [renglones, facturas] = await Promise.all([api.renglonesVenta(v.id), api.facturasVenta(v.id)]);
      editando = v;
      form.fecha.value = v.fecha;
      if (!clientes.some((c) => c.id === v.cliente_id)) clientes.push({ id: v.cliente_id, nombre: v.cliente, rfc: v.rfc });
      pintarClientes(String(v.cliente_id));
      if (t.destino) {
        form.destino_colonia.value = v.destino_colonia || ''; form.destino_ciudad.value = v.destino_ciudad || (v.destino_estado ? '' : v.destino || '');
        form.destino_estado.value = v.destino_estado || ''; form.aumento_centavos_kg.value = v.aumento_centavos_kg ?? '';
      } else form.destino.value = v.destino || '';
      form.folio.value = v.folio || '';
      if (t.folioExterno) form.folio_externo.value = v.folio_externo || '';
      if (t.moneda) { form.moneda.value = v.moneda || 'MXN'; form.tipo_cambio.value = v.tipo_cambio ?? ''; }
      form.tipo_pago.value = v.tipo_pago; form.empresa.value = v.empresa_factura_id ? String(v.empresa_factura_id) : '';
      cuerpoFact.innerHTML = facturas.map((f) => filaFactura(f)).join('') || filaFactura();
      if (t.pesadaUnica) form.kg_bascula.value = v.kg_bascula ?? (Number(v.kg_brutos) || '');
      form.forma_pago.value = v.forma_pago; form.anticipo.value = v.anticipo;
      if (t.merma) { form.merma_kg_caja.value = v.merma_kg_caja; mostrarDestino(); }
      if (t.muertos) form.muertos.value = v.muertos;
      form.descuento.value = v.descuento; form.motivo_descuento.value = v.motivo_descuento || ''; form.notas.value = v.notas || '';
      cuerpo.innerHTML = renglones.map((r) => renglon(r)).join('') || renglon();
      mostrarCampos(); actualizar();
      titulo.textContent = `Editar venta: ${v.cliente}, ${fmt.fecha(v.fecha)}`;
      form.querySelector('button[type=submit]').textContent = 'Guardar cambios';
      btnCancelar.classList.remove('oculto');
      btnEliminar.classList.toggle('oculto', !sesion.esAdmin());
      form.classList.add('editando');
      if (Number(v.pagado)) aviso(`Esta venta ya tiene pagos aplicados por ${dinero(v.pagado, v.moneda)}. Si baja el total, revisa la cobranza.`);
      form.scrollIntoView({ behavior: 'smooth', block: 'start' });
    } catch (e) { aviso(e.message, 'error'); }
  }
  return { editar };
}

// ---------- Historial ----------

const totalesPorMoneda = (filas, k) => {
  const m = new Map();
  for (const v of filas) m.set(v.moneda || 'MXN', (m.get(v.moneda || 'MXN') || 0) + Number(v[k] || 0));
  return [...m].filter(([, x]) => x).map(([mon, x]) => dinero(x, mon)).join(' + ') || dinero(0);
};

async function historial(zona, especie, filtros, sigueVivo, alEditar) {
  const t = TIPOS[especie];
  const conMerma = Boolean(t.merma || t.mermaRenglon);
  try {
    const filas = await api.ventas({ especie, desde: filtros.desde.value, hasta: filtros.hasta.value, cliente: filtros.cliente.value || null, conSaldo: filtros.saldo.checked });
    if (!sigueVivo()) return;
    if (!filas.length) { zona.innerHTML = '<p class="vacio">No hay ventas con ese filtro.</p>'; return; }
    const suma = (k) => filas.reduce((s, v) => s + Number(v[k] || 0), 0);
    const kg = suma('kg_netos');
    const unaMoneda = new Set(filas.map((v) => v.moneda || 'MXN')).size === 1;
    const puede = sesion.puedeCapturar('ventas');
    const porId = new Map(filas.map((v) => [String(v.id), v]));
    const describe = (v) => (t.producto ? esc(v.productos || '—') : t.presentacion ? esc([v.presentaciones, v.calidades].filter(Boolean).join(' · ') || '—') : esc(v.calidades || '—'));
    zona.innerHTML = `
      <p class="nota">${filas.length} venta${filas.length === 1 ? '' : 's'} · ${n2.format(suma('cantidad'))} ${t.unidad.toLowerCase()}${kg ? ` · ${fmt.kg(kg)}` : ''} · <b>${totalesPorMoneda(filas, 'total')}</b>${unaMoneda && kg ? ` · precio promedio ${dinero(suma('total') / kg, filas[0].moneda)}/kg` : ''}${suma('saldo') ? ` · saldo pendiente <b>${totalesPorMoneda(filas, 'saldo')}</b>` : ''}</p>
      <div class="tabla-scroll"><table>
        <thead><tr><th>Fecha</th><th>Cliente</th><th>${t.producto ? 'Producto' : t.presentacion ? 'Presentación / calidad' : 'Calidad / granja'}</th><th class="num">${t.unidad}</th><th class="num">Kg ${conMerma ? 'netos' : ''}</th><th class="num">Precio prom.</th><th class="num">Total</th><th>Pago</th><th>Capturó</th><th></th></tr></thead>
        <tbody>${filas.map((v) => `
          <tr class="${Number(v.saldo) > 0 ? 'fila-alerta' : ''}">
            <td>${fmt.fecha(v.fecha)}${v.folio ? `<small>Folio ${esc(v.folio)}</small>` : ''}${v.folio_externo ? `<small>Cliente ${esc(v.folio_externo)}</small>` : ''}</td>
            <td>${esc(v.cliente)}<small>${esc([v.rfc, v.destino].filter(Boolean).join(' · '))}</small>${v.aumento_centavos_kg != null ? `<small>Aumento al destino: ${n2.format(v.aumento_centavos_kg)} ¢/kg</small>` : ''}</td>
            <td>${describe(v)}<small>${esc(v.granjas || '')}</small></td>
            <td class="num">${n2.format(v.cantidad)}${v.peso_promedio && !t.producto ? `<small>${n2.format(v.peso_promedio)} kg prom.</small>` : ''}${Number(v.muertos) ? `<small class="dif-menos">${v.muertos} muertos</small>` : ''}</td>
            <td class="num">${Number(v.kg_netos) ? fmt.kg(v.kg_netos) : '—'}${Number(v.merma_kg) ? `<small>brutos ${fmt.kg(v.kg_brutos)} − merma ${fmt.kg(v.merma_kg)}</small>` : ''}</td>
            <td class="num">${v.precio_promedio_kg ? `${dinero(v.precio_promedio_kg, v.moneda)}/kg` : '—'}</td>
            <td class="num">${dinero(v.total, v.moneda)}${Number(v.descuento) ? `<small title="${esc(v.motivo_descuento || '')}">desc. ${dinero(v.descuento, v.moneda)}</small>` : ''}${v.moneda === 'USD' && v.tipo_cambio ? `<small>TC ${n2.format(v.tipo_cambio)}</small>` : ''}</td>
            <td>${v.tipo_pago === 'factura' ? `${Number(v.num_facturas) > 1 ? 'Facturas' : 'Factura'} ${esc(v.factura || '(sin número)')}<small>${esc(Number(v.num_facturas) > 1 ? v.facturas : v.empresa_factura || '')}</small>${v.facturado != null && Math.abs(Number(v.facturado) - Number(v.total)) > 0.5 ? `<small class="dif-menos">facturado ${dinero(v.facturado, v.moneda)}</small>` : ''}` : 'Efectivo'}
              <small>${v.forma_pago === 'contado' ? 'De contado' : Number(v.saldo) > 0 ? `Saldo ${dinero(v.saldo, v.moneda)}${Number(v.anticipo) + Number(v.pagado) ? ` (pagado ${dinero(Number(v.anticipo) + Number(v.pagado), v.moneda)})` : ''}` : 'Crédito pagado'}</small></td>
            <td>${esc(v.capturado_por || '—')}<small>${esc(fmt.hora(v.capturado_en))}</small>${v.modificado_por ? `<small>Modificó ${esc(v.modificado_por)}</small>` : ''}</td>
            <td class="acciones"><button type="button" class="boton boton-chico" data-ver-venta="${v.id}" aria-expanded="false">Ver</button>${puede ? `<button type="button" class="boton boton-chico" data-editar-venta="${v.id}">Editar</button>` : ''}${puede && Number(v.saldo) > 0 ? `<button type="button" class="boton boton-chico" data-cobrar="${v.id}">Registrar pago</button>` : ''}</td>
          </tr>`).join('')}</tbody>
      </table></div>`;
    zona.querySelector('tbody').addEventListener('click', async (ev) => {
      const ed = ev.target.closest('[data-editar-venta]');
      if (ed) return alEditar(porId.get(ed.dataset.editarVenta));
      const co = ev.target.closest('[data-cobrar]');
      if (co) { const v = porId.get(co.dataset.cobrar); return irACobrar(v.cliente_id, v.moneda); }
      const ver = ev.target.closest('[data-ver-venta]');
      if (!ver) return;
      const tr = ver.closest('tr');
      if (tr.nextElementSibling?.classList.contains('detalle')) { tr.nextElementSibling.remove(); ver.setAttribute('aria-expanded', 'false'); return; }
      ver.setAttribute('aria-expanded', 'true');
      tr.insertAdjacentHTML('afterend', '<tr class="detalle"><td colspan="10"><p class="cargando">Cargando…</p></td></tr>');
      const celda = tr.nextElementSibling.firstElementChild;
      try {
        const v = porId.get(ver.dataset.verVenta);
        const rs = await api.renglonesVenta(v.id);
        celda.innerHTML = `<table class="tabla-detalle">
          <thead><tr>${t.producto ? '<th>Producto</th>' : ''}<th>Granja</th>${t.presentacion ? '<th>Presentación</th>' : ''}${t.calidad ? '<th>Calidad</th>' : ''}<th class="num">${t.unidad}</th><th class="num">Kg brutos</th>${conMerma ? '<th class="num">Merma</th><th class="num">Kg netos</th>' : ''}<th class="num">Precio</th><th class="num">Importe</th></tr></thead>
          <tbody>${rs.map((r) => `<tr>${t.producto ? `<td>${esc(r.producto || '—')}</td>` : ''}<td>${esc(r.granja || '—')}</td>${t.presentacion ? `<td>${esc(r.presentacion || '—')}</td>` : ''}${t.calidad ? `<td>${esc(r.calidad || '—')}</td>` : ''}
            <td class="num">${n2.format(r.cantidad)}${r.unidad ? ` ${esc(r.unidad)}` : ''}</td><td class="num">${Number(r.kg_brutos) ? fmt.kg(r.kg_brutos) : '—'}${r.peso_promedio && !t.producto ? `<small>${n2.format(r.peso_promedio)} kg prom.</small>` : ''}</td>
            ${conMerma ? `<td class="num">${fmt.kg(r.merma_kg)}</td><td class="num">${fmt.kg(r.kg_netos)}</td>` : ''}
            <td class="num">${dinero(r.precio_total_kg, v.moneda)}/${r.precio_por === 'unidad' ? esc(r.unidad || (t.presentacion ? 'caja' : 'unidad')) : 'kg'}</td><td class="num">${dinero(r.importe, v.moneda)}</td></tr>`).join('')}</tbody>
        </table>${Number(v.pagado) ? `<p class="nota">Pagos aplicados: ${dinero(v.pagado, v.moneda)}${Number(v.anticipo) ? ` · anticipo ${dinero(v.anticipo, v.moneda)}` : ''}. El detalle está en Cobranza y saldos.</p>` : ''}${v.motivo_descuento ? `<p class="nota">Descuento: ${esc(v.motivo_descuento)}</p>` : ''}${v.notas ? `<p class="nota">${esc(v.notas)}</p>` : ''}`;
      } catch (e) { celda.innerHTML = `<span class="caja-error">${esc(e.message)}</span>`; }
    });
  } catch (e) { if (sigueVivo()) errorEn(zona, e); }
}
