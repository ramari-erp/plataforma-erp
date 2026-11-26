// Cobranza: saldos por cliente, pagos aplicados a una o varias ventas y estado de cuenta.
import { api } from './api.js';
import { esc, fmt, hoy, aviso, cargando, errorEn } from './ui.js';
import { sesion } from './sesion.js';
import { dinero } from './ventas_tipos.js';
import { selectorCuenta } from './cuentas.js';

const n2 = new Intl.NumberFormat('es-MX', { maximumFractionDigits: 2 });
const numero = (v) => (v === '' || v == null ? null : Number(v));
const redondo = (x) => Math.round(x * 100) / 100;
const ESPECIES = { huevo: 'Huevo', cerdo: 'Cerdo', ganado: 'Ganado', borrego: 'Borrego', berries: 'Berries', general: 'General' };
const dias = (fecha) => Math.round((new Date(hoy()) - new Date(fecha)) / 86400000);

let preseleccion = null;   // { cliente_id, moneda } cuando se llega desde "Registrar pago" en una venta
export function irACobrar(clienteId, moneda = 'MXN') {
  preseleccion = { cliente_id: clienteId, moneda };
  if (location.hash === '#/ventas/cobranza') window.dispatchEvent(new HashChangeEvent('hashchange'));
  else location.hash = '#/ventas/cobranza';
}

export function pantallaCobranza(cont, pestanas) {
  let vivo = true;
  const puede = sesion.puedeCapturar('cobranza');
  cont.innerHTML = `
    <h1>Ventas</h1>
    ${pestanas}
    <h2>Saldos por cliente</h2>
    <p class="nota">Ventas a crédito de todas las áreas (huevo, cerdo, ganado, borregos, berries y generales) menos anticipos y pagos.</p>
    <div id="saldos-clientes"></div>
    ${puede ? '<div id="zona-pago"></div>' : ''}
    <div id="estado-cuenta"></div>
    <h2>Pagos recibidos</h2>
    <form class="filtros" id="filtros-pagos">
      <label>Desde<input type="date" name="desde"></label>
      <label>Hasta<input type="date" name="hasta"></label>
      <label>Cliente<select name="cliente"><option value="">Todos</option></select></label>
    </form>
    <div id="historial-pagos"></div>
    <h2>Depósitos por cuenta</h2>
    <p class="nota">Todo lo cobrado (ventas de contado, anticipos y pagos de clientes) según la cuenta donde se depositó. Será la base de la sección de Bancos.</p>
    <form class="filtros" id="filtros-depositos">
      <label>Desde<input type="date" name="desde"></label>
      <label>Hasta<input type="date" name="hasta"></label>
      <label>Cuenta<select name="cuenta"><option value="">Todas</option><option value="sin">Sin cuenta indicada</option></select></label>
    </form>
    <div id="depositos"></div>`;
  const zSaldos = cont.querySelector('#saldos-clientes');
  const zEstado = cont.querySelector('#estado-cuenta');
  const zPagos = cont.querySelector('#historial-pagos');
  const zDep = cont.querySelector('#depositos');
  const filtrosDep = cont.querySelector('#filtros-depositos');
  filtrosDep.desde.value = hoy(-30); filtrosDep.hasta.value = hoy();
  const pintarDepositos = () => depositos(zDep, filtrosDep, () => vivo);
  filtrosDep.addEventListener('change', pintarDepositos);
  const filtros = cont.querySelector('#filtros-pagos');
  filtros.desde.value = hoy(-60);
  filtros.hasta.value = hoy();
  let editor = null;
  let estadoAbierto = null;

  const pintarSaldos = async () => {
    try {
      const filas = (await api.saldosClientes()).filter((s) => Math.abs(Number(s.saldo)) >= 0.01 || Number(s.a_favor) >= 0.01);
      if (!vivo) return;
      if (!filas.length) { zSaldos.innerHTML = '<p class="vacio">Ningún cliente tiene saldo pendiente.</p>'; return; }
      const totales = ['MXN', 'USD'].map((m) => [m, filas.filter((s) => s.moneda === m).reduce((x, s) => x + Number(s.saldo), 0)]).filter(([, x]) => x);
      zSaldos.innerHTML = `
        <div class="kpis">${totales.map(([m, x]) => `<div class="kpi"><span>Por cobrar ${m === 'USD' ? 'en dólares' : 'en pesos'}</span><b>${dinero(x, m)}</b><small>${((n) => `${n} cliente${n === 1 ? '' : 's'}`)(filas.filter((s) => s.moneda === m && Number(s.saldo) > 0).length)}</small></div>`).join('')}</div>
        <div class="tabla-scroll margen-arriba"><table>
          <thead><tr><th>Cliente</th><th class="num">Vendido a crédito</th><th class="num">Pagado</th><th class="num">Ventas con saldo</th><th>Más antigua</th><th class="num">Saldo</th><th></th></tr></thead>
          <tbody>${filas.map((s) => `<tr class="${dias(s.venta_mas_antigua || hoy()) > 30 && Number(s.saldo) > 0 ? 'fila-alerta' : ''}">
            <td>${esc(s.cliente)}<small>${esc([s.rfc, s.moneda].filter(Boolean).join(' · '))}</small></td>
            <td class="num">${dinero(s.vendido, s.moneda)}</td>
            <td class="num">${dinero(s.pagado, s.moneda)}${s.ultimo_pago ? `<small>último ${fmt.fecha(s.ultimo_pago)}</small>` : ''}</td>
            <td class="num">${s.ventas_con_saldo}</td>
            <td>${s.venta_mas_antigua ? `${fmt.fecha(s.venta_mas_antigua)}<small>hace ${dias(s.venta_mas_antigua)} días</small>` : '—'}</td>
            <td class="num"><b>${dinero(s.saldo, s.moneda)}</b>${Number(s.a_favor) >= 0.01 ? `<small>${dinero(s.a_favor, s.moneda)} a favor sin aplicar</small>` : ''}</td>
            <td class="acciones"><button type="button" class="boton boton-chico" data-estado="${s.cliente_id}" data-moneda="${s.moneda}">Estado de cuenta</button>${puede ? `<button type="button" class="boton boton-chico" data-pagar="${s.cliente_id}" data-moneda="${s.moneda}">Registrar pago</button>` : ''}</td>
          </tr>`).join('')}</tbody>
        </table></div>`;
    } catch (e) { if (vivo) errorEn(zSaldos, e); }
  };
  zSaldos.addEventListener('click', (ev) => {
    const b = ev.target.closest('[data-estado]');
    if (b) { estadoAbierto = { cliente_id: Number(b.dataset.estado), moneda: b.dataset.moneda }; return pintarEstado(); }
    const p = ev.target.closest('[data-pagar]');
    if (p && editor) editor.nuevo(Number(p.dataset.pagar), p.dataset.moneda);
  });

  const pintarEstado = async () => {
    if (!estadoAbierto) return;
    const { cliente_id, moneda } = estadoAbierto;
    cargando(zEstado);
    try {
      const [ventas, pagos] = await Promise.all([api.ventas({ cliente: cliente_id, moneda }), api.pagos({ cliente: cliente_id })]);
      if (!vivo) return;
      const nombre = ventas[0]?.cliente || pagos[0]?.cliente || '';
      const movs = [];
      for (const v of ventas.filter((x) => x.forma_pago === 'credito')) {
        movs.push({ fecha: v.fecha, orden: v.id * 10, concepto: `Venta ${ESPECIES[v.especie] || v.especie}${v.folio ? ` folio ${v.folio}` : ''}`, detalle: v.productos || [v.presentaciones, v.calidades].filter(Boolean).join(' · '), cargo: Number(v.total), abono: 0 });
        if (Number(v.anticipo)) movs.push({ fecha: v.fecha, orden: v.id * 10 + 1, concepto: 'Anticipo', detalle: v.folio ? `folio ${v.folio}` : '', cargo: 0, abono: Number(v.anticipo) });
      }
      for (const p of pagos.filter((x) => x.moneda === moneda)) {
        movs.push({ fecha: p.fecha, orden: 1e12 + p.id, concepto: `Pago ${p.forma}${p.banco ? ` ${p.banco}` : ''}${p.referencia ? ` · ${p.referencia}` : ''}`, detalle: p.ventas ? `Aplicado a ${p.ventas}` : 'Sin aplicar', cargo: 0, abono: Number(p.monto), pago: p });
      }
      movs.sort((a, b) => a.fecha.localeCompare(b.fecha) || a.orden - b.orden);
      let saldo = 0;
      zEstado.innerHTML = `
        <div class="tarjeta margen-arriba">
          <h2>Estado de cuenta: ${esc(nombre)} (${moneda})</h2>
          <p class="nota">Ventas a crédito, anticipos y pagos en orden de fecha. Las ventas de contado no aparecen porque se pagan al momento.</p>
          ${movs.length ? `<div class="tabla-scroll"><table>
            <thead><tr><th>Fecha</th><th>Concepto</th><th class="num">Cargo</th><th class="num">Abono</th><th class="num">Saldo</th>${puede ? '<th></th>' : ''}</tr></thead>
            <tbody>${movs.map((m) => { saldo += m.cargo - m.abono; return `<tr><td>${fmt.fecha(m.fecha)}</td><td>${esc(m.concepto)}<small>${esc(m.detalle || '')}</small></td>
              <td class="num">${m.cargo ? dinero(m.cargo, moneda) : ''}</td><td class="num">${m.abono ? dinero(m.abono, moneda) : ''}</td><td class="num">${dinero(saldo, moneda)}</td>
              ${puede ? `<td class="acciones">${m.pago ? botonesPago(m.pago.id) : ''}</td>` : ''}</tr>`; }).join('')}</tbody>
          </table></div><p><b>Saldo al día: ${dinero(saldo, moneda)}</b>${saldo < 0 ? ' (a favor del cliente)' : ''}</p>` : '<p class="vacio">Sin movimientos a crédito.</p>'}
          <button type="button" class="boton boton-chico" id="cerrar-estado">Cerrar</button>
        </div>`;
      zEstado.querySelector('#cerrar-estado').onclick = () => { estadoAbierto = null; zEstado.innerHTML = ''; };
      const pagosId = new Map(pagos.map((p) => [String(p.id), p]));
      zEstado.querySelector('tbody')?.addEventListener('click', (ev) => accionPago(ev, pagosId, (p) => editor?.editar(p), recargar));
      zEstado.scrollIntoView({ behavior: 'smooth', block: 'start' });
    } catch (e) { if (vivo) errorEn(zEstado, e); }
  };

  const pintarPagos = () => historialPagos(zPagos, filtros, () => vivo, (p) => editor?.editar(p), recargar);
  function recargar() { pintarSaldos(); pintarPagos(); pintarEstado(); pintarDepositos(); }

  (async () => {
    try {
      const [clientes, cuentas, empresas] = await Promise.all([api.clientes(), api.cuentasBancarias().catch(() => []), api.empresasFactura()]);
      if (!vivo) return;
      filtrosDep.cuenta.insertAdjacentHTML('beforeend', cuentas.map((c) => `<option value="${c.id}">${esc(c.nombre)}</option>`).join(''));
      filtros.cliente.insertAdjacentHTML('beforeend', clientes.map((c) => `<option value="${c.id}">${esc(c.nombre)}</option>`).join(''));
      if (puede) editor = formularioPago(cont.querySelector('#zona-pago'), clientes, cuentas, empresas, recargar);
      if (preseleccion && editor) { editor.nuevo(preseleccion.cliente_id, preseleccion.moneda); }
      preseleccion = null;
    } catch (e) { aviso(e.message, 'error'); }
  })();
  filtros.addEventListener('change', pintarPagos);
  cargando(zSaldos); cargando(zPagos);
  pintarSaldos(); pintarPagos(); pintarDepositos();
  const soltar1 = api.enVivo('pagos_cliente', recargar);
  const soltar2 = api.enVivo('ventas', recargar);
  return () => { vivo = false; soltar1(); soltar2(); };
}

// ---------- Registrar pago ----------

function formularioPago(zona, clientes, cuentas, empresas, alGuardar) {
  zona.innerHTML = `
    <form class="tarjeta formulario margen-arriba" id="form-pago" autocomplete="off">
      <h2 id="titulo-pago">Registrar pago de cliente</h2>
      <div class="rejilla">
        <label>Fecha<input type="date" name="fecha" value="${hoy()}" required></label>
        <label class="ancho2">Cliente<select name="cliente" required><option value="">Elige…</option>${clientes.map((c) => `<option value="${c.id}">${esc(c.nombre)}</option>`).join('')}</select></label>
        <label>Moneda<select name="moneda"><option value="MXN">Pesos (MXN)</option><option value="USD">Dólares (USD)</option></select></label>
        <label>Monto recibido<input type="number" name="monto" min="0.01" step="0.01" inputmode="decimal" required></label>
        <label class="campo-usd oculto">Tipo de cambio<input type="number" name="tipo_cambio" min="0" step="0.0001" inputmode="decimal" placeholder="Opcional"></label>
        <label>Forma<select name="forma"><option value="transferencia">Transferencia</option><option value="efectivo">Efectivo</option><option value="cheque">Cheque</option><option value="otro">Otro</option></select></label>
        <div class="ancho2" id="zona-cuenta-pago"></div>
        <label>Banco del cliente<input name="banco" maxlength="60" placeholder="Opcional"></label>
        <label>Referencia / vale<input name="referencia" maxlength="80"></label>
        <label>Factura<input name="factura" maxlength="60" placeholder="Opcional"></label>
        <label class="ancho2">Notas<input name="notas" maxlength="300"></label>
      </div>
      <h3>Aplicar a ventas con saldo</h3>
      <div id="ventas-pendientes"><p class="vacio">Elige el cliente para ver sus ventas pendientes.</p></div>
      <div class="kpis margen-arriba" id="resumen-pago"></div>
      <button class="boton boton-primario" type="submit">Guardar pago</button>
      <button class="boton oculto" type="button" id="btn-cancelar-pago">Cancelar edición</button>
      <button class="boton boton-peligro oculto" type="button" id="btn-eliminar-pago">Eliminar pago</button>
    </form>`;
  const form = zona.querySelector('#form-pago');
  const zVentas = form.querySelector('#ventas-pendientes');
  const cuenta = selectorCuenta(form.querySelector('#zona-cuenta-pago'), cuentas, empresas);
  let pendientes = [];        // ventas del cliente con saldo disponible para este pago
  let manual = false;         // si se escribió a mano lo aplicado, ya no se reparte solo
  let editando = null;
  let previas = new Map();    // aplicaciones del pago en edición (venta_id → monto)

  const repartir = () => {
    let resto = numero(form.monto.value) || 0;
    zVentas.querySelectorAll('[name=aplicar]').forEach((inp) => {
      const disp = Number(inp.dataset.disponible);
      const x = redondo(Math.min(disp, Math.max(resto, 0)));
      inp.value = x > 0 ? x : '';
      resto = redondo(resto - x);
    });
    resumen();
  };
  const resumen = () => {
    const m = form.moneda.value;
    const monto = numero(form.monto.value) || 0;
    const aplicado = [...zVentas.querySelectorAll('[name=aplicar]')].reduce((s, i) => s + (numero(i.value) || 0), 0);
    const resto = redondo(monto - aplicado);
    form.querySelector('#resumen-pago').innerHTML = `
      <div class="kpi"><span>Pago</span><b>${dinero(monto, m)}</b></div>
      <div class="kpi"><span>Aplicado a ventas</span><b>${dinero(aplicado, m)}</b></div>
      <div class="kpi ${resto < 0 ? 'kpi-alerta' : ''}"><span>${resto < 0 ? 'Aplicado de más' : 'Queda a favor del cliente'}</span><b>${dinero(Math.abs(resto), m)}</b>${resto > 0 ? '<small>se puede aplicar después editando el pago</small>' : ''}</div>`;
  };
  const cargarVentas = async () => {
    const cliente = form.cliente.value;
    form.querySelectorAll('.campo-usd').forEach((x) => x.classList.toggle('oculto', form.moneda.value !== 'USD'));
    if (!cliente) { pendientes = []; zVentas.innerHTML = '<p class="vacio">Elige el cliente para ver sus ventas pendientes.</p>'; resumen(); return; }
    cargando(zVentas);
    try {
      const todas = await api.ventas({ cliente, moneda: form.moneda.value });
      pendientes = todas.filter((v) => v.forma_pago === 'credito' && (Number(v.saldo) > 0 || previas.has(v.id)))
        .map((v) => ({ ...v, disponible: redondo(Number(v.saldo) + (previas.get(v.id) || 0)) }))
        .sort((a, b) => a.fecha.localeCompare(b.fecha) || a.id - b.id);
      if (!pendientes.length) {
        zVentas.innerHTML = `<p class="vacio">Este cliente no tiene ventas a crédito pendientes en ${form.moneda.value === 'USD' ? 'dólares' : 'pesos'}. El pago quedará a favor.</p>`;
      } else {
        zVentas.innerHTML = `
          <div class="tabla-scroll"><table class="tabla-captura">
            <thead><tr><th>Fecha</th><th>Venta</th><th class="num">Total</th><th class="num">Saldo</th><th class="num">Aplicar</th></tr></thead>
            <tbody>${pendientes.map((v) => `<tr>
              <td>${fmt.fecha(v.fecha)}<small>hace ${dias(v.fecha)} días</small></td>
              <td>${esc(ESPECIES[v.especie] || v.especie)}${v.folio ? ` · folio ${esc(v.folio)}` : ''}<small>${esc(v.productos || [v.presentaciones, v.calidades].filter(Boolean).join(' · ') || '')}</small></td>
              <td class="num">${dinero(v.total, v.moneda)}</td>
              <td class="num">${dinero(v.disponible, v.moneda)}</td>
              <td class="num"><input type="number" class="celda-num" name="aplicar" data-venta="${v.id}" data-disponible="${v.disponible}" min="0" max="${v.disponible}" step="0.01" inputmode="decimal" value="${previas.get(v.id) ?? ''}" aria-label="Aplicar a la venta del ${fmt.fecha(v.fecha)}"></td>
            </tr>`).join('')}</tbody>
          </table></div>
          <button type="button" class="boton boton-chico" id="btn-repartir">Repartir desde la más antigua</button>`;
        zVentas.querySelector('#btn-repartir').onclick = () => { manual = false; repartir(); };
        if (!editando && !manual) repartir();
      }
      resumen();
    } catch (e) { errorEn(zVentas, e); }
  };
  form.cliente.addEventListener('change', () => { manual = false; cargarVentas(); });
  form.moneda.addEventListener('change', () => { manual = false; cargarVentas(); });
  form.monto.addEventListener('input', () => { if (!manual) repartir(); else resumen(); });
  zVentas.addEventListener('input', (ev) => { if (ev.target.name === 'aplicar') { manual = true; resumen(); } });
  resumen();

  const titulo = form.querySelector('#titulo-pago');
  const btnCancelar = form.querySelector('#btn-cancelar-pago');
  const btnEliminar = form.querySelector('#btn-eliminar-pago');
  function limpiar() {
    form.reset(); form.fecha.value = hoy(); cuenta.fijar('');
    editando = null; previas = new Map(); manual = false;
    titulo.textContent = 'Registrar pago de cliente';
    form.querySelector('button[type=submit]').textContent = 'Guardar pago';
    btnCancelar.classList.add('oculto'); btnEliminar.classList.add('oculto');
    btnEliminar.dataset.confirmar = ''; btnEliminar.textContent = 'Eliminar pago';
    form.classList.remove('editando');
    cargarVentas();
  }
  btnCancelar.addEventListener('click', limpiar);
  btnEliminar.addEventListener('click', async () => {
    if (btnEliminar.dataset.confirmar !== 'si') { btnEliminar.dataset.confirmar = 'si'; btnEliminar.textContent = 'Confirmar: eliminar pago'; return; }
    try { await api.eliminarPago(editando.id); aviso('Pago eliminado; las ventas recuperan su saldo.'); limpiar(); alGuardar(); } catch (e) { aviso(e.message, 'error'); }
  });

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    if (!form.cliente.value) return aviso('Elige el cliente.', 'error');
    const monto = numero(form.monto.value) || 0;
    if (monto <= 0) return aviso('Captura el monto recibido.', 'error');
    const aplicaciones = [...zVentas.querySelectorAll('[name=aplicar]')].map((i) => ({ venta_id: Number(i.dataset.venta), monto: numero(i.value) || 0, disp: Number(i.dataset.disponible) })).filter((a) => a.monto > 0);
    if (aplicaciones.some((a) => a.monto > a.disp + 0.005)) return aviso('A una venta le aplicaste más que su saldo.', 'error');
    if (aplicaciones.reduce((s, a) => s + a.monto, 0) > monto + 0.005) return aviso('Lo aplicado a las ventas es mayor que el pago.', 'error');
    const pago = {
      cliente_id: Number(form.cliente.value), fecha: form.fecha.value, monto, moneda: form.moneda.value,
      tipo_cambio: form.moneda.value === 'USD' ? form.tipo_cambio.value : '', forma: form.forma.value,
      cuenta_id: cuenta.valor(), banco: form.banco.value.trim(), referencia: form.referencia.value.trim(), factura: form.factura.value.trim(), notas: form.notas.value.trim(),
    };
    const boton = form.querySelector('button[type=submit]');
    boton.disabled = true;
    try {
      await api.registrarPago(pago, aplicaciones.map(({ venta_id, monto: m }) => ({ venta_id, monto: m })), editando?.id ?? null);
      aviso(`${editando ? 'Pago corregido' : 'Pago guardado'}: ${form.cliente.selectedOptions[0]?.textContent} ${dinero(monto, pago.moneda)}.`);
      limpiar();
      alGuardar();
    } catch (e) { aviso(e.message, 'error'); } finally { boton.disabled = false; }
  });

  return {
    nuevo(clienteId, moneda) {
      if (editando) limpiar();
      form.cliente.value = String(clienteId); form.moneda.value = moneda || 'MXN';
      manual = false; cargarVentas();
      form.scrollIntoView({ behavior: 'smooth', block: 'start' });
      form.monto.focus({ preventScroll: true });
    },
    async editar(p) {
      try {
        const apl = await api.aplicacionesPago(p.id);
        editando = p; previas = new Map(apl.map((a) => [a.venta_id, Number(a.monto)])); manual = true;
        form.fecha.value = p.fecha; form.cliente.value = String(p.cliente_id); form.moneda.value = p.moneda;
        form.monto.value = p.monto; form.tipo_cambio.value = p.tipo_cambio ?? ''; form.forma.value = p.forma;
        cuenta.fijar(p.cuenta_id); form.banco.value = p.banco || ''; form.referencia.value = p.referencia || ''; form.factura.value = p.factura || ''; form.notas.value = p.notas || '';
        titulo.textContent = `Editar pago: ${p.cliente}, ${fmt.fecha(p.fecha)}`;
        form.querySelector('button[type=submit]').textContent = 'Guardar cambios';
        btnCancelar.classList.remove('oculto');
        btnEliminar.classList.remove('oculto');
        form.classList.add('editando');
        await cargarVentas();
        form.scrollIntoView({ behavior: 'smooth', block: 'start' });
      } catch (e) { aviso(e.message, 'error'); }
    },
  };
}

// ---------- Historial de pagos ----------

// Botones Editar / Eliminar de un pago (eliminar pide confirmación con un segundo clic).
const botonesPago = (id) => `<button type="button" class="boton boton-chico" data-editar-pago="${id}">Editar</button><button type="button" class="boton boton-chico boton-peligro" data-eliminar-pago="${id}">Eliminar</button>`;
async function accionPago(ev, porId, alEditar, alEliminar) {
  const ed = ev.target.closest('[data-editar-pago]');
  if (ed) return alEditar(porId.get(ed.dataset.editarPago));
  const el = ev.target.closest('[data-eliminar-pago]');
  if (!el) return;
  if (el.dataset.confirmar !== 'si') { el.dataset.confirmar = 'si'; el.textContent = 'Confirmar: eliminar'; return; }
  el.disabled = true;
  try {
    const p = porId.get(el.dataset.eliminarPago);
    await api.eliminarPago(p.id);
    aviso(`Pago eliminado (${p.cliente}, ${dinero(p.monto, p.moneda)}); las ventas recuperan su saldo.`);
    alEliminar();
  } catch (e) { aviso(e.message, 'error'); el.disabled = false; }
}

async function historialPagos(zona, filtros, sigueVivo, alEditar, alEliminar) {
  try {
    const filas = await api.pagos({ cliente: filtros.cliente.value || null, desde: filtros.desde.value, hasta: filtros.hasta.value });
    if (!sigueVivo()) return;
    if (!filas.length) { zona.innerHTML = '<p class="vacio">No hay pagos con ese filtro.</p>'; return; }
    const puede = sesion.puedeCapturar('cobranza');
    const porId = new Map(filas.map((p) => [String(p.id), p]));
    const total = (m) => filas.filter((p) => p.moneda === m).reduce((s, p) => s + Number(p.monto), 0);
    zona.innerHTML = `
      <p class="nota">${filas.length} pago${filas.length === 1 ? '' : 's'} · <b>${['MXN', 'USD'].filter((m) => total(m)).map((m) => dinero(total(m), m)).join(' + ')}</b></p>
      <div class="tabla-scroll"><table>
        <thead><tr><th>Fecha</th><th>Cliente</th><th class="num">Monto</th><th>Forma</th><th>Aplicado a</th><th>Capturó</th><th></th></tr></thead>
        <tbody>${filas.map((p) => `<tr class="${Number(p.sin_aplicar) >= 0.01 ? 'fila-alerta' : ''}">
          <td>${fmt.fecha(p.fecha)}</td>
          <td>${esc(p.cliente)}</td>
          <td class="num">${dinero(p.monto, p.moneda)}${p.moneda === 'USD' && p.tipo_cambio ? `<small>TC ${n2.format(p.tipo_cambio)}</small>` : ''}</td>
          <td>${esc(p.forma)}${p.cuenta ? `<small>A: ${esc(p.cuenta)}</small>` : ''}<small>${esc([p.banco, p.referencia, p.factura ? `Factura ${p.factura}` : ''].filter(Boolean).join(' · '))}</small></td>
          <td>${esc(p.ventas || '—')}${Number(p.sin_aplicar) >= 0.01 ? `<small>${dinero(p.sin_aplicar, p.moneda)} sin aplicar</small>` : ''}${p.notas ? `<small>${esc(p.notas)}</small>` : ''}</td>
          <td>${esc(p.capturado_por || '—')}<small>${esc(fmt.hora(p.capturado_en))}</small></td>
          <td class="acciones">${puede ? botonesPago(p.id) : ''}</td>
        </tr>`).join('')}</tbody>
      </table></div>`;
    zona.querySelector('tbody').addEventListener('click', (ev) => accionPago(ev, porId, alEditar, alEliminar));
  } catch (e) { if (sigueVivo()) errorEn(zona, e); }
}

// ---------- Depósitos por cuenta ----------

async function depositos(zona, filtros, sigueVivo) {
  try {
    const filas = await api.depositos({ desde: filtros.desde.value, hasta: filtros.hasta.value, cuenta: filtros.cuenta.value || null });
    if (!sigueVivo()) return;
    if (!filas.length) { zona.innerHTML = '<p class="vacio">No hay cobros con ese filtro.</p>'; return; }
    const grupos = new Map();
    for (const d of filas) {
      const k = `${d.cuenta || 'Sin cuenta indicada'}|${d.moneda}`;
      const g = grupos.get(k) || { cuenta: d.cuenta || 'Sin cuenta indicada', sin: !d.cuenta, moneda: d.moneda, monto: 0, n: 0 };
      g.monto += Number(d.monto); g.n += 1; grupos.set(k, g);
    }
    zona.innerHTML = `
      <div class="kpis">${[...grupos.values()].map((g) => `<div class="kpi ${g.sin ? 'kpi-alerta' : ''}"><span>${esc(g.cuenta)}</span><b>${dinero(g.monto, g.moneda)}</b><small>${g.n} cobro${g.n === 1 ? '' : 's'}</small></div>`).join('')}</div>
      <div class="tabla-scroll margen-arriba"><table>
        <thead><tr><th>Fecha</th><th>Cuenta</th><th>Cliente</th><th>Concepto</th><th class="num">Monto</th></tr></thead>
        <tbody>${filas.map((d) => `<tr class="${d.cuenta ? '' : 'fila-alerta'}">
          <td>${fmt.fecha(d.fecha)}</td><td>${esc(d.cuenta || 'Sin indicar')}</td><td>${esc(d.cliente)}</td>
          <td>${esc(d.concepto)}<small>${esc([d.especie ? ESPECIES[d.especie] : '', d.folio].filter(Boolean).join(' · '))}</small></td>
          <td class="num">${dinero(d.monto, d.moneda)}</td></tr>`).join('')}</tbody>
      </table></div>`;
  } catch (e) { if (sigueVivo()) errorEn(zona, e); }
}
