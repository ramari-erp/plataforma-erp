// Ventas: huevo, cerdo, ganado y borregos. Cada venta = encabezado + renglones (granja, calidad, cantidad, kg, precio).
import { api } from './api.js';
import { esc, fmt, hoy, aviso, cargando, errorEn } from './ui.js';
import { sesion } from './sesion.js';
import { normalizar } from './materias.js';

const TIPOS = {
  huevo:   { nombre: 'Huevo',    unidad: 'Cajas',  area: 'aves',     flete: true,  merma: 2, muertos: false },
  cerdo:   { nombre: 'Cerdo',    unidad: 'Cerdos', area: 'cerdos',   flete: false, merma: 0, muertos: true },
  ganado:  { nombre: 'Ganado',   unidad: 'Cabezas', area: 'ganado',  flete: false, merma: 0, muertos: false },
  borrego: { nombre: 'Borregos', unidad: 'Cabezas', area: 'borregos', flete: false, merma: 0, muertos: false },
};
const numero = (v) => (v === '' || v == null ? null : Number(v));
const n2 = new Intl.NumberFormat('es-MX', { maximumFractionDigits: 2 });

export function pantallaVentas(cont, seccion = 'huevo') {
  const especie = TIPOS[seccion] ? seccion : 'huevo';
  const t = TIPOS[especie];
  let vivo = true;
  const puede = sesion.puedeCapturar('ventas');
  cont.innerHTML = `
    <h1>Ventas</h1>
    <nav class="pestanas" aria-label="Tipo de venta">
      ${Object.entries(TIPOS).map(([k, v]) => `<a href="#/ventas/${k}" class="${k === especie ? 'activo' : ''}">${v.nombre}</a>`).join('')}
    </nav>
    ${puede ? '<div id="zona-venta"></div>' : '<div class="caja caja-info">Puedes consultar las ventas. Para capturarlas pide permiso de Ventas al administrador.</div>'}
    <h2>Historial de ventas de ${t.nombre.toLowerCase()}</h2>
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
  const pintar = () => historial(hist, especie, filtros, () => vivo, (v) => editor?.editar(v), pintar);

  (async () => {
    try {
      const [clientes, empresas, calidades, granjas, granjaAreas, previas] = await Promise.all([
        api.clientes(), api.empresasFactura(), api.calidadesVenta(especie), api.granjas(), api.granjaAreas(),
        api.ventas({ especie, desde: hoy(-365) }),
      ]);
      if (!vivo) return;
      filtros.cliente.insertAdjacentHTML('beforeend', clientes.map((c) => `<option value="${c.id}">${esc(c.nombre)}</option>`).join(''));
      if (puede) {
        const ids = new Set(granjaAreas.filter((x) => x.area === t.area).map((x) => x.granja_id));
        const granjasArea = granjas.filter((g) => ids.has(g.id) && g.activa);
        // Sin lista fija de calidades: sugerencias con las ya usadas.
        const usadas = [...new Set(previas.flatMap((v) => (v.calidades || '').split(', ').filter(Boolean)))];
        editor = formulario(cont.querySelector('#zona-venta'), especie, {
          clientes, empresas, calidades: calidades.map((c) => c.nombre), usadas, granjas: granjasArea.length ? granjasArea : granjas.filter((g) => g.activa),
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

function formulario(zona, especie, { clientes, empresas, calidades, usadas, granjas }, alGuardar) {
  const t = TIPOS[especie];
  const NUEVO = '__nuevo__';
  const listaCalidad = calidades.length
    ? (sel) => `<select name="calidad" aria-label="Calidad"><option value="">Elige…</option>${calidades.map((c) => `<option ${c === sel ? 'selected' : ''}>${esc(c)}</option>`).join('')}</select>`
    : (sel) => `<input name="calidad" list="calidades-${especie}" maxlength="40" value="${esc(sel || '')}" aria-label="Calidad" placeholder="Calidad">`;
  zona.innerHTML = `
    <form class="tarjeta formulario" id="form-venta" autocomplete="off">
      <h2 id="titulo-venta">Registrar venta de ${t.nombre.toLowerCase()}</h2>
      ${calidades.length ? '' : `<datalist id="calidades-${especie}">${usadas.map((c) => `<option value="${esc(c)}">`).join('')}</datalist>`}
      <div class="rejilla">
        <label>Fecha<input type="date" name="fecha" value="${hoy()}" required></label>
        <label class="ancho2">Cliente<select name="cliente" required></select><small class="ayuda" id="rfc-cliente"></small></label>
        <label>Destino<input name="destino" maxlength="120" placeholder="Ciudad / lugar"></label>
        <div class="ancho-total caja caja-info oculto" id="nuevo-cliente">
          <div class="rejilla">
            <label class="ancho2">Nombre del cliente<input name="nc_nombre" maxlength="120"></label>
            <label>RFC<input name="nc_rfc" maxlength="13" placeholder="Opcional"></label>
            <div class="en-linea"><button type="button" class="boton boton-chico boton-primario" id="btn-nc">Agregar cliente</button>
              <button type="button" class="boton boton-chico" id="btn-nc-cancelar">Cancelar</button></div>
          </div>
          <div class="parecidas oculto" id="nc-parecidos"></div>
        </div>
        <label>Tipo de venta<select name="tipo_pago"><option value="factura">Con factura</option><option value="efectivo">Efectivo</option></select></label>
        <label class="campo-factura">Razón social<select name="empresa"><option value="">Elige…</option>${empresas.map((e) => `<option value="${e.id}">${esc(e.nombre)}</option>`).join('')}</select></label>
        <label class="campo-factura">Número de factura<input name="factura" maxlength="60" placeholder="Si ya se emitió"></label>
        <label>Pago<select name="forma_pago"><option value="contado">De contado</option><option value="credito">Crédito / con anticipo</option></select></label>
        <label class="campo-credito oculto">Anticipo $<input type="number" name="anticipo" min="0" step="0.01" inputmode="decimal" value="0"></label>
        ${t.flete ? `<label>Flete $/kg<input type="number" name="flete_kg" min="0" step="0.0001" inputmode="decimal" value="0"></label>
          <label>Merma kg por caja<input type="number" name="merma_kg_caja" min="0" step="0.01" inputmode="decimal" value="${t.merma}"></label>` : ''}
        ${t.muertos ? '<label>Muertos<input type="number" name="muertos" min="0" step="1" inputmode="numeric" value="0"></label>' : ''}
      </div>

      <h3>${t.nombre === 'Huevo' ? 'Cajas por granja y calidad' : 'Detalle'}</h3>
      <div class="tabla-scroll"><table class="tabla-captura">
        <thead><tr><th>Granja</th><th>Calidad</th><th class="num">${t.unidad}</th><th class="num">Kg ${t.flete ? 'brutos (báscula)' : 'totales'}</th><th class="num">Peso prom.</th>
          ${t.merma ? '<th class="num">Merma</th><th class="num">Kg netos</th>' : ''}<th class="num">${t.flete ? 'Precio base $/kg' : 'Precio $/kg'}</th>${t.flete ? '<th class="num">Precio total $/kg</th>' : ''}<th class="num">Importe</th><th></th></tr></thead>
        <tbody id="renglones-venta"></tbody>
      </table></div>
      <button type="button" class="boton boton-chico" id="btn-renglon-venta">+ Agregar renglón</button>

      <div class="rejilla margen-arriba">
        <label>Descuento $<input type="number" name="descuento" min="0" step="0.01" inputmode="decimal" value="0"></label>
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
  form.nc_nombre.addEventListener('input', () => {
    const t2 = normalizar(form.nc_nombre.value);
    const lista = t2.length < 3 ? [] : clientes.filter((c) => normalizar(c.nombre).includes(t2) || t2.includes(normalizar(c.nombre))).slice(0, 5);
    const z = form.querySelector('#nc-parecidos');
    z.classList.toggle('oculto', !lista.length);
    z.innerHTML = lista.length ? `<span>¿Es alguno de estos? </span>${lista.map((c) => `<button type="button" class="chip" data-cliente="${c.id}">${esc(c.nombre)}</button>`).join('')}` : '';
  });
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

  // ---- Factura / crédito ----
  const mostrarCampos = () => {
    form.querySelectorAll('.campo-factura').forEach((x) => x.classList.toggle('oculto', form.tipo_pago.value !== 'factura'));
    form.querySelectorAll('.campo-credito').forEach((x) => x.classList.toggle('oculto', form.forma_pago.value !== 'credito'));
  };
  form.tipo_pago.addEventListener('change', mostrarCampos);
  form.forma_pago.addEventListener('change', mostrarCampos);
  mostrarCampos();

  // ---- Renglones ----
  const renglon = (r = {}) => `<tr>
      <td><select name="granja" aria-label="Granja"><option value="">—</option>${granjas.map((g) => `<option value="${g.id}" ${String(r.granja_id) === String(g.id) ? 'selected' : ''}>${esc(g.nombre)}</option>`).join('')}</select></td>
      <td>${listaCalidad(r.calidad)}</td>
      <td class="num"><input type="number" class="celda-num" name="cantidad" min="0" step="1" inputmode="numeric" value="${r.cantidad ?? ''}" aria-label="${t.unidad}"></td>
      <td class="num"><input type="number" class="celda-num" name="kg" min="0.01" step="0.01" inputmode="decimal" value="${r.kg_brutos ?? ''}" aria-label="Kg"></td>
      <td class="num prom">—</td>
      ${t.merma ? '<td class="num merma">—</td><td class="num netos">—</td>' : ''}
      <td class="num"><input type="number" class="celda-num" name="precio" min="0" step="0.0001" inputmode="decimal" value="${r.precio_kg ?? ''}" aria-label="Precio por kg"></td>
      ${t.flete ? '<td class="num ptotal">—</td>' : ''}
      <td class="num importe">—</td>
      <td><button type="button" class="boton boton-chico" data-quitar-renglon aria-label="Quitar renglón">Quitar</button></td>
    </tr>`;
  const leer = () => {
    const flete = t.flete ? numero(form.flete_kg.value) || 0 : 0;
    const merma = t.merma ? numero(form.merma_kg_caja.value) || 0 : 0;
    const filas = [...cuerpo.querySelectorAll('tr')].map((tr) => {
      const v = (n) => tr.querySelector(`[name=${n}]`).value;
      const cantidad = numero(v('cantidad')) || 0, kg = numero(v('kg')), precio = numero(v('precio'));
      const mermaKg = cantidad * merma;
      const netos = kg != null ? kg - mermaKg : null;
      return { tr, granja_id: numero(v('granja')), calidad: v('calidad').trim(), cantidad, kg, precio_kg: precio, mermaKg, netos,
        importe: netos != null && precio != null ? netos * (precio + flete) : 0 };
    });
    return { flete, merma, filas };
  };
  const actualizar = () => {
    const { flete, filas } = leer();
    let cant = 0, kg = 0, netos = 0, importe = 0;
    for (const f of filas) {
      f.tr.querySelector('.prom').textContent = f.cantidad && f.kg ? `${n2.format(f.kg / f.cantidad)} kg` : '—';
      if (t.merma) {
        f.tr.querySelector('.merma').textContent = f.cantidad ? fmt.kg(f.mermaKg) : '—';
        f.tr.querySelector('.netos').textContent = f.netos != null ? fmt.kg(f.netos) : '—';
      }
      if (t.flete) f.tr.querySelector('.ptotal').textContent = f.precio_kg != null ? fmt.precio(f.precio_kg + flete) : '—';
      f.tr.querySelector('.importe').textContent = f.importe ? fmt.dinero(f.importe) : '—';
      cant += f.cantidad; kg += f.kg || 0; netos += f.netos || 0; importe += f.importe;
    }
    const descuento = numero(form.descuento.value) || 0;
    const total = importe - descuento;
    const anticipo = form.forma_pago.value === 'credito' ? numero(form.anticipo.value) || 0 : 0;
    const saldo = form.forma_pago.value === 'credito' ? Math.max(total - anticipo, 0) : 0;
    form.querySelector('#totales-venta').innerHTML = `
      <div class="kpi"><span>${t.unidad}</span><b>${n2.format(cant)}</b><small>${cant && kg ? `peso promedio ${n2.format(kg / cant)} kg` : ''}</small></div>
      <div class="kpi"><span>Kg ${t.merma ? 'netos' : 'totales'}</span><b>${fmt.kg(netos)}</b><small>${t.merma ? `${fmt.kg(kg)} brutos − ${fmt.kg(kg - netos)} merma` : ''}</small></div>
      <div class="kpi"><span>Total ${t.muertos ? 'de factura' : ''}</span><b>${fmt.dinero(total)}</b><small>${descuento ? `${fmt.dinero(importe)} − descuento ${fmt.dinero(descuento)}` : ''}${netos ? ` · ${fmt.precio(total / netos)}` : ''}</small></div>
      ${form.forma_pago.value === 'credito' ? `<div class="kpi"><span>Saldo</span><b>${fmt.dinero(saldo)}</b><small>anticipo ${fmt.dinero(anticipo)}</small></div>` : ''}`;
  };
  form.addEventListener('input', actualizar);
  form.addEventListener('change', actualizar);
  form.querySelector('#btn-renglon-venta').addEventListener('click', () => {
    const ultimo = cuerpo.lastElementChild;
    cuerpo.insertAdjacentHTML('beforeend', renglon({ granja_id: ultimo?.querySelector('[name=granja]').value }));
    actualizar();
  });
  cuerpo.addEventListener('click', (ev) => {
    if (!ev.target.closest('[data-quitar-renglon]')) return;
    if (cuerpo.children.length > 1) ev.target.closest('tr').remove(); else aviso('La venta necesita al menos un renglón.', 'error');
    actualizar();
  });
  cuerpo.innerHTML = renglon();
  actualizar();

  // ---- Guardar / editar ----
  let editando = null;
  const titulo = form.querySelector('#titulo-venta');
  const btnCancelar = form.querySelector('#btn-cancelar-venta');
  const btnEliminar = form.querySelector('#btn-eliminar-venta');
  function limpiar() {
    const fecha = form.fecha.value;
    form.reset();
    form.fecha.value = editando ? hoy() : fecha;
    editando = null;
    pintarClientes();
    cuerpo.innerHTML = renglon();
    titulo.textContent = `Registrar venta de ${t.nombre.toLowerCase()}`;
    form.querySelector('button[type=submit]').textContent = 'Guardar venta';
    btnCancelar.classList.add('oculto'); btnEliminar.classList.add('oculto');
    btnEliminar.dataset.confirmar = ''; btnEliminar.textContent = 'Eliminar venta';
    form.classList.remove('editando');
    mostrarCampos(); actualizar();
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
    const usados = filas.filter((f) => f.kg || f.cantidad || f.precio_kg != null);
    if (!usados.length) return aviso('Captura al menos un renglón.', 'error');
    if (usados.some((f) => !f.kg)) return aviso('Captura los kg de cada renglón.', 'error');
    if (usados.some((f) => f.precio_kg == null)) return aviso('Captura el precio por kg de cada renglón.', 'error');
    if (usados.some((f) => !f.calidad)) return aviso('Captura la calidad de cada renglón.', 'error');
    if (usados.some((f) => f.netos <= 0)) return aviso('La merma es mayor que los kg en algún renglón. Revisa cajas y kg.', 'error');
    const venta = {
      especie, fecha: form.fecha.value, cliente_id: Number(form.cliente.value), destino: form.destino.value.trim(),
      tipo_pago: form.tipo_pago.value, empresa_factura_id: form.tipo_pago.value === 'factura' ? form.empresa.value : '',
      factura: form.tipo_pago.value === 'factura' ? form.factura.value.trim() : '',
      forma_pago: form.forma_pago.value, anticipo: form.forma_pago.value === 'credito' ? numero(form.anticipo.value) || 0 : 0,
      flete_kg: t.flete ? numero(form.flete_kg.value) || 0 : 0, merma_kg_caja: t.merma ? numero(form.merma_kg_caja.value) || 0 : 0,
      muertos: t.muertos ? numero(form.muertos.value) || 0 : 0, descuento: numero(form.descuento.value) || 0,
      motivo_descuento: form.motivo_descuento.value.trim(), notas: form.notas.value.trim(),
    };
    const renglones = usados.map((f) => ({ granja_id: f.granja_id || '', calidad: f.calidad, cantidad: f.cantidad, kg: f.kg, precio_kg: f.precio_kg }));
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
      const renglones = await api.renglonesVenta(v.id);
      editando = v;
      form.fecha.value = v.fecha;
      if (!clientes.some((c) => c.id === v.cliente_id)) clientes.push({ id: v.cliente_id, nombre: v.cliente, rfc: v.rfc });
      pintarClientes(String(v.cliente_id));
      form.destino.value = v.destino || '';
      form.tipo_pago.value = v.tipo_pago; form.empresa.value = v.empresa_factura_id ? String(v.empresa_factura_id) : '';
      form.factura.value = v.factura || ''; form.forma_pago.value = v.forma_pago; form.anticipo.value = v.anticipo;
      if (t.flete) { form.flete_kg.value = v.flete_kg; form.merma_kg_caja.value = v.merma_kg_caja; }
      if (t.muertos) form.muertos.value = v.muertos;
      form.descuento.value = v.descuento; form.motivo_descuento.value = v.motivo_descuento || ''; form.notas.value = v.notas || '';
      cuerpo.innerHTML = renglones.map((r) => renglon(r)).join('') || renglon();
      mostrarCampos(); actualizar();
      titulo.textContent = `Editar venta: ${v.cliente}, ${fmt.fecha(v.fecha)}`;
      form.querySelector('button[type=submit]').textContent = 'Guardar cambios';
      btnCancelar.classList.remove('oculto');
      btnEliminar.classList.toggle('oculto', !sesion.esAdmin());
      form.classList.add('editando');
      form.scrollIntoView({ behavior: 'smooth', block: 'start' });
    } catch (e) { aviso(e.message, 'error'); }
  }
  return { editar };
}

// ---------- Historial ----------

async function historial(zona, especie, filtros, sigueVivo, alEditar) {
  const t = TIPOS[especie];
  try {
    const filas = await api.ventas({ especie, desde: filtros.desde.value, hasta: filtros.hasta.value, cliente: filtros.cliente.value || null, conSaldo: filtros.saldo.checked });
    if (!sigueVivo()) return;
    if (!filas.length) { zona.innerHTML = '<p class="vacio">No hay ventas con ese filtro.</p>'; return; }
    const suma = (k) => filas.reduce((s, v) => s + Number(v[k] || 0), 0);
    const kg = suma('kg_netos'), total = suma('total');
    const puede = sesion.puedeCapturar('ventas');
    const porId = new Map(filas.map((v) => [String(v.id), v]));
    zona.innerHTML = `
      <p class="nota">${filas.length} venta${filas.length === 1 ? '' : 's'} · ${n2.format(suma('cantidad'))} ${t.unidad.toLowerCase()} · ${fmt.kg(kg)} · <b>${fmt.dinero(total)}</b> · precio promedio ${fmt.precio(kg ? total / kg : 0)}${suma('saldo') ? ` · saldo pendiente <b>${fmt.dinero(suma('saldo'))}</b>` : ''}</p>
      <div class="tabla-scroll"><table>
        <thead><tr><th>Fecha</th><th>Cliente</th><th>Calidad / granja</th><th class="num">${t.unidad}</th><th class="num">Kg ${t.merma ? 'netos' : ''}</th><th class="num">Precio prom.</th><th class="num">Total</th><th>Pago</th><th>Capturó</th><th></th></tr></thead>
        <tbody>${filas.map((v) => `
          <tr class="${Number(v.saldo) > 0 ? 'fila-alerta' : ''}">
            <td>${fmt.fecha(v.fecha)}</td>
            <td>${esc(v.cliente)}<small>${esc([v.rfc, v.destino].filter(Boolean).join(' · '))}</small></td>
            <td>${esc(v.calidades || '—')}<small>${esc(v.granjas || '')}</small></td>
            <td class="num">${n2.format(v.cantidad)}${v.peso_promedio ? `<small>${n2.format(v.peso_promedio)} kg prom.</small>` : ''}${Number(v.muertos) ? `<small class="dif-menos">${v.muertos} muertos</small>` : ''}</td>
            <td class="num">${fmt.kg(v.kg_netos)}${Number(v.merma_kg) ? `<small>merma ${fmt.kg(v.merma_kg)}</small>` : ''}</td>
            <td class="num">${fmt.precio(v.precio_promedio_kg)}${Number(v.flete_kg) ? `<small>flete ${fmt.precio(v.flete_kg)}</small>` : ''}</td>
            <td class="num">${fmt.dinero(v.total)}${Number(v.descuento) ? `<small title="${esc(v.motivo_descuento || '')}">desc. ${fmt.dinero(v.descuento)}</small>` : ''}</td>
            <td>${v.tipo_pago === 'factura' ? `Factura ${esc(v.factura || '(sin número)')}<small>${esc(v.empresa_factura || '')}</small>` : 'Efectivo'}
              <small>${v.forma_pago === 'contado' ? 'De contado' : `Saldo ${fmt.dinero(v.saldo)} (anticipo ${fmt.dinero(v.anticipo)})`}</small></td>
            <td>${esc(v.capturado_por || '—')}<small>${esc(fmt.hora(v.capturado_en))}</small>${v.modificado_por ? `<small>Modificó ${esc(v.modificado_por)}</small>` : ''}</td>
            <td class="acciones"><button type="button" class="boton boton-chico" data-ver-venta="${v.id}" aria-expanded="false">Ver</button>${puede ? `<button type="button" class="boton boton-chico" data-editar-venta="${v.id}">Editar</button>` : ''}</td>
          </tr>`).join('')}</tbody>
      </table></div>`;
    zona.querySelector('tbody').addEventListener('click', async (ev) => {
      const ed = ev.target.closest('[data-editar-venta]');
      if (ed) return alEditar(porId.get(ed.dataset.editarVenta));
      const ver = ev.target.closest('[data-ver-venta]');
      if (!ver) return;
      const tr = ver.closest('tr');
      if (tr.nextElementSibling?.classList.contains('detalle')) { tr.nextElementSibling.remove(); ver.setAttribute('aria-expanded', 'false'); return; }
      ver.setAttribute('aria-expanded', 'true');
      tr.insertAdjacentHTML('afterend', '<tr class="detalle"><td colspan="10"><p class="cargando">Cargando…</p></td></tr>');
      const celda = tr.nextElementSibling.firstElementChild;
      try {
        const rs = await api.renglonesVenta(ver.dataset.verVenta);
        const v = porId.get(ver.dataset.verVenta);
        celda.innerHTML = `<table class="tabla-detalle">
          <thead><tr><th>Granja</th><th>Calidad</th><th class="num">${t.unidad}</th><th class="num">Kg brutos</th>${t.merma ? '<th class="num">Merma</th><th class="num">Kg netos</th>' : ''}<th class="num">Peso prom.</th><th class="num">Precio $/kg</th><th class="num">Importe</th></tr></thead>
          <tbody>${rs.map((r) => `<tr><td>${esc(r.granja || '—')}</td><td>${esc(r.calidad || '—')}</td><td class="num">${n2.format(r.cantidad)}</td><td class="num">${fmt.kg(r.kg_brutos)}</td>
            ${t.merma ? `<td class="num">${fmt.kg(r.merma_kg)}</td><td class="num">${fmt.kg(r.kg_netos)}</td>` : ''}<td class="num">${r.peso_promedio ? `${n2.format(r.peso_promedio)} kg` : '—'}</td>
            <td class="num">${fmt.precio(r.precio_total_kg)}${Number(r.flete_kg) ? `<small>${fmt.precio(r.precio_kg)} base + ${fmt.precio(r.flete_kg)} flete</small>` : ''}</td><td class="num">${fmt.dinero(r.importe)}</td></tr>`).join('')}</tbody>
        </table>${v.motivo_descuento ? `<p class="nota">Descuento: ${esc(v.motivo_descuento)}</p>` : ''}${v.notas ? `<p class="nota">${esc(v.notas)}</p>` : ''}`;
      } catch (e) { celda.innerHTML = `<span class="caja-error">${esc(e.message)}</span>`; }
    });
  } catch (e) { if (sigueVivo()) errorEn(zona, e); }
}
