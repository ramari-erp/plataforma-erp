// Planta de alimentos: resumen de capacidad, llegadas de materia prima y existencias.
import { api } from './api.js';
import { esc, fmt, hoy, aviso, cargando, errorEn } from './ui.js';
import { sesion } from './sesion.js';
import { seccionInventario } from './inventario.js';
import { seccionProduccion } from './produccion.js';
import { seccionContratos, alertasContratos, precioContrato } from './contratos.js';
import { miniFormularioMateria, seccionMaterias } from './materias.js';
import { seccionFormulas } from './formulas.js';
import { formularioNota } from './notas.js';

const SECCIONES = [
  { codigo: 'resumen', nombre: 'Resumen' },
  { codigo: 'llegadas', nombre: 'Llegadas de materia prima' },
  { codigo: 'produccion', nombre: 'Producción' },
  { codigo: 'contratos', nombre: 'Contratos' },
  { codigo: 'existencias', nombre: 'Existencias' },
  { codigo: 'inventario', nombre: 'Inventario físico' },
  { codigo: 'formulas', nombre: 'Fórmulas' },
  { codigo: 'materias', nombre: 'Materias primas' },
];

export function pantallaPlanta(cont, seccion = 'resumen') {
  const actual = SECCIONES.find((s) => s.codigo === seccion) || SECCIONES[0];
  cont.innerHTML = `
    <h1>Planta de alimentos</h1>
    <nav class="pestanas" aria-label="Secciones de planta">
      ${SECCIONES.map((s) => `<a href="#/planta/${s.codigo}" class="${s === actual ? 'activo' : ''}">${esc(s.nombre)}</a>`).join('')}
    </nav>
    <section id="seccion"></section>`;
  const zona = cont.querySelector('#seccion');
  if (actual.codigo === 'resumen') return resumen(zona);
  if (actual.codigo === 'llegadas') return llegadas(zona);
  if (actual.codigo === 'inventario') return seccionInventario(zona);
  if (actual.codigo === 'produccion') return seccionProduccion(zona);
  if (actual.codigo === 'contratos') return seccionContratos(zona);
  if (actual.codigo === 'materias') return seccionMaterias(zona);
  if (actual.codigo === 'formulas') return seccionFormulas(zona);
  return existencias(zona);
}

// ---------- Resumen ----------

function resumen(zona) {
  let vivo = true;
  async function pintar() {
    try {
      const [cap, exis, ult, prod, cob, contr] = await Promise.all([
        api.capacidad(), api.existencias(), api.llegadas({ desde: hoy(-6) }), api.ordenes({ desde: hoy(-6) }),
        api.cobertura(), api.contratos({ soloVigentes: true }),
      ]);
      const alertasCont = alertasContratos(cob, contr);
      if (!vivo) return;
      const valor = exis.reduce((s, x) => s + Number(x.valor_inventario || 0), 0);
      const deHoy = ult.filter((l) => l.fecha === hoy());
      const kgHoy = deHoy.reduce((s, l) => s + Number(l.kg_neto), 0);
      const kgSemana = ult.reduce((s, l) => s + Number(l.kg_neto), 0);
      const prodHoy = prod.filter((o) => o.fecha === hoy());
      const kgProd = prod.reduce((s, o) => s + Number(o.kg_producidos), 0);
      const costoProdKg = kgProd ? prod.reduce((s, o) => s + Number(o.costo_mp), 0) / kgProd : 0;
      const negativas = exis.filter((x) => Number(x.existencia_kg) < 0);
      const bajoMin = exis.filter((x) => x.bajo_minimo);
      const enGrupo = new Set(cap.flatMap((g) => (g.materias || '').split(', ')));
      const otras = exis.filter((x) => !enGrupo.has(x.nombre) && Number(x.existencia_kg) !== 0);

      zona.innerHTML = `
        <div class="kpis">
          <div class="kpi"><span>Valor del inventario de materia prima</span><b>${fmt.dinero(valor)}</b></div>
          <div class="kpi"><span>Llegadas de hoy</span><b>${fmt.t(kgHoy)}</b><small>${deHoy.length} ${deHoy.length === 1 ? 'descarga' : 'descargas'}</small></div>
          <div class="kpi"><span>Llegadas últimos 7 días</span><b>${fmt.t(kgSemana)}</b><small>${ult.length} descargas</small></div>
          <div class="kpi"><span>Producido hoy</span><b>${fmt.t(prodHoy.reduce((s, o) => s + Number(o.kg_producidos), 0))}</b><small>${prodHoy.length} ${prodHoy.length === 1 ? 'orden' : 'órdenes'}</small></div>
          <div class="kpi"><span>Producido últimos 7 días</span><b>${fmt.t(prod.reduce((s, o) => s + Number(o.kg_producidos), 0))}</b><small>costo MP ${fmt.precio(costoProdKg)}</small></div>
        </div>
        ${negativas.length || bajoMin.length || alertasCont.length ? `
          <div class="caja caja-alerta">
            ${alertasCont.map((t) => `<p>${t} <a href="#/planta/contratos">Ver contratos</a></p>`).join('')}
            ${negativas.length ? `<p><b>Existencia negativa:</b> ${negativas.map((x) => esc(x.nombre)).join(', ')}. Falta capturar el inventario de arranque o alguna llegada.</p>` : ''}
            ${bajoMin.length ? `<p><b>Bajo el mínimo:</b> ${bajoMin.map((x) => esc(x.nombre)).join(', ')}.</p>` : ''}
          </div>` : ''}
        <h2>Capacidad de almacenamiento</h2>
        <p class="nota">Existencia contra capacidad de bodega + tolvas de planta, por grupo de materias primas.</p>
        <div class="capacidades">
          ${cap.map(tarjetaCapacidad).join('')}
        </div>
        <h2>Otras materias primas</h2>
        <p class="nota">En racks de bodega, sin capacidad definida.</p>
        ${otras.length ? tablaExistencias(otras) : '<p class="vacio">Sin existencias registradas todavía.</p>'}`;
    } catch (e) { if (vivo) errorEn(zona, e); }
  }
  cargando(zona);
  pintar();
  const soltar = api.enVivo('llegadas_mp', () => pintar());
  const soltar2 = api.enVivo('ordenes_produccion', () => pintar());
  return () => { vivo = false; soltar(); soltar2(); };
}

function tarjetaCapacidad(g) {
  const pct = Number(g.ocupacion_pct ?? 0);
  const estado = pct >= 90 ? 'lleno' : pct < 0 ? 'negativo' : '';
  const ancho = Math.max(0, Math.min(100, pct));
  return `
    <article class="tarjeta capacidad ${estado}">
      <header><h3>${esc(g.nombre)}</h3><b>${fmt.pct(g.ocupacion_pct)}</b></header>
      <div class="barra-cap" role="meter" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${ancho}" aria-label="Ocupación de ${esc(g.nombre)}">
        <div style="width:${ancho}%"></div>
      </div>
      <p><b>${fmt.t(g.existencia_kg)}</b> de ${fmt.t(g.capacidad_total_kg)} · libre ${fmt.t(g.espacio_libre_kg)}</p>
      <p class="nota">${esc(g.materias || 'Sin materias asignadas')}${g.notas ? ` · ${esc(g.notas)}` : ''}</p>
    </article>`;
}

// ---------- Llegadas ----------

function llegadas(zona) {
  let vivo = true;
  let editorLlegada = null;
  let porIdLlegada = new Map();
  const puede = sesion.puedeCapturar('planta');
  zona.innerHTML = `
    ${puede ? `
    <div class="selector-modo" role="radiogroup" aria-label="Tipo de captura">
      <label class="casilla"><input type="radio" name="modo-llegada" value="uno" checked> Un producto</label>
      <label class="casilla"><input type="radio" name="modo-llegada" value="nota"> Nota con varios productos (encostalado)</label>
    </div>
    <div id="zona-nota" class="oculto"></div>
    <form class="tarjeta formulario" id="form-llegada" autocomplete="off">
      <h2 id="titulo-llegada">Registrar llegada</h2>
      <div class="rejilla">
        <label>Fecha<input type="date" name="fecha" required></label>
        <label class="ancho2">Materia prima<select name="materia_prima_id" required><option value="">Cargando…</option></select></label>
        <div class="ancho-total caja caja-info oculto" id="campo-nueva-mp"></div>
        <label class="ancho2">Proveedor<select name="proveedor_id"><option value="">Cargando…</option></select></label>
        <label class="ancho2" id="campo-contrato">Contrato<select name="contrato_id"><option value="">Elige primero la materia prima</option></select>
          <small class="ayuda" id="ayuda-contrato"></small></label>
        <label class="oculto" id="campo-tc">Tipo de cambio (MXN por USD)<input type="number" name="tipo_cambio" min="0.0001" step="0.0001" inputmode="decimal"></label>
        <label class="ancho2 oculto" id="campo-nuevo-prov">Nombre del proveedor nuevo
          <span class="en-linea"><input name="nuevo_proveedor" maxlength="120"><button type="button" class="boton boton-chico" id="btn-guardar-prov">Agregar</button></span>
        </label>
        <label>Kg bruto<input type="number" name="kg_bruto" min="0" step="0.01" inputmode="decimal"></label>
        <label>Kg tara<input type="number" name="kg_tara" min="0" step="0.01" inputmode="decimal"></label>
        <label>Kg neto<input type="number" name="kg_neto" min="0.01" step="0.01" inputmode="decimal" required></label>
        <label>Humedad %<input type="number" name="humedad_pct" min="0" max="100" step="0.01" inputmode="decimal"></label>
        <label>Precio $/kg (sin IVA, con flete)<input type="number" name="precio_kg" min="0" step="0.0001" inputmode="decimal" required></label>
        <label>Total<output name="total">$0.00</output></label>
        <label>Factura / remisión<input name="factura" maxlength="60"><small class="ayuda" id="ayuda-factura"></small></label>
        <label>Boleta de báscula<input name="boleta" maxlength="60"><small class="ayuda" id="ayuda-boleta"></small></label>
        <label class="casilla ancho-total"><input type="checkbox" name="precio_provisional"> Precio o tipo de cambio <b>provisional</b> (aún no se paga; se corrige después)</label>
        <label class="ancho-total">Notas<input name="notas" maxlength="300"></label>
      </div>
      <button class="boton boton-primario" type="submit">Guardar llegada</button>
      <button class="boton oculto" type="button" id="btn-cancelar-llegada">Cancelar edición</button>
      <button class="boton boton-peligro oculto" type="button" id="btn-eliminar-llegada">Eliminar llegada</button>
    </form>` : '<div class="caja caja-info">Puedes consultar el historial. Para capturar llegadas pide permiso de Planta al administrador.</div>'}

    <h2>Historial de llegadas</h2>
    <form class="filtros" id="filtros">
      <label>Desde<input type="date" name="desde"></label>
      <label>Hasta<input type="date" name="hasta"></label>
      <label>Materia prima<select name="materia"><option value="">Todas</option></select></label>
      <label class="casilla"><input type="checkbox" name="pendientes"> Solo con información pendiente</label>
    </form>
    <div id="historial"></div>`;

  const hist = zona.querySelector('#historial');
  const filtros = zona.querySelector('#filtros');
  filtros.desde.value = hoy(-30);
  filtros.hasta.value = hoy();

  async function pintarHistorial() {
    try {
      const filas = await api.llegadas({ desde: filtros.desde.value, hasta: filtros.hasta.value, materia: filtros.materia.value || null, pendientes: filtros.pendientes.checked });
      porIdLlegada = new Map(filas.map((l) => [String(l.id), l]));
      if (!vivo) return;
      if (!filas.length) { hist.innerHTML = `<p class="vacio">${filtros.pendientes.checked ? 'No hay llegadas con información pendiente en esas fechas.' : 'No hay llegadas en esas fechas.'}</p>`; return; }
      const conPendientes = filas.filter((l) => (l.pendientes || []).length).length;
      const kg = filas.reduce((s, l) => s + Number(l.kg_neto), 0);
      const total = filas.reduce((s, l) => s + Number(l.total), 0);
      hist.innerHTML = `
        <p class="nota">${filas.length} llegadas · ${fmt.t(kg)} · ${fmt.dinero(total)} · precio promedio ${fmt.precio(kg ? total / kg : 0)}${conPendientes ? ` · <b>${conPendientes} con información pendiente</b>` : ''}</p>
        <div class="tabla-scroll"><table>
          <thead><tr><th>Fecha</th><th>Materia prima</th><th>Proveedor</th><th class="num">Kg neto</th><th class="num">Humedad</th><th class="num">Precio</th><th class="num">Total</th><th>Factura / boleta</th><th>Contrato</th><th>Pendiente</th><th>Capturó</th>${puede ? '<th></th>' : ''}</tr></thead>
          <tbody>${filas.map((l) => `
            <tr class="${(l.pendientes || []).length ? 'fila-alerta' : ''}">
              <td>${fmt.fecha(l.fecha)}</td>
              <td>${esc(l.materia_prima)}</td>
              <td>${esc(l.proveedor || '—')}</td>
              <td class="num">${fmt.kg(l.kg_neto)}${Number(l.kg_excedente_contrato) > 0 ? `<small class="dif-mas">excedente ${fmt.kg(l.kg_excedente_contrato)}</small>` : ''}</td>
              <td class="num">${l.humedad_pct == null ? '—' : fmt.pct(l.humedad_pct)}</td>
              <td class="num">${fmt.precio(l.precio_kg)}${l.tipo_cambio ? `<small>TC ${Number(l.tipo_cambio).toFixed(4)}</small>` : ''}</td>
              <td class="num">${fmt.dinero(l.total)}</td>
              <td>${esc([l.factura, l.boleta].filter(Boolean).join(' / ') || '—')}${l.nota_id ? `<small>Nota ${esc(l.nota_folio || `#${l.nota_id}`)} · ${l.nota_productos} producto${Number(l.nota_productos) === 1 ? '' : 's'}${l.nota_kg_bascula ? ` · báscula ${fmt.kg(l.nota_kg_bascula)}` : ''}</small>` : ''}</td>
              <td>${esc(l.contrato || '—')}</td>
              <td>${(l.pendientes || []).map((p) => `<span class="etiqueta">${p === 'factura' ? 'Sin factura' : 'Precio provisional'}</span>`).join(' ') || '—'}</td>
              <td title="${esc(fmt.hora(l.capturado_en))}">${esc(l.capturado_por || '—')}<small>${esc(fmt.hora(l.capturado_en))}</small>${l.modificado_por ? `<small>Modificó ${esc(l.modificado_por)}</small>` : ''}</td>
              ${puede ? `<td><button type="button" class="boton boton-chico" data-editar-llegada="${l.id}">Editar</button></td>` : ''}
            </tr>`).join('')}
          </tbody>
        </table></div>`;
    } catch (e) { if (vivo) errorEn(hist, e); }
  }

  (async () => {
    try {
      const [materias, provs, grupos] = await Promise.all([api.materias(), puede ? api.proveedores() : [], puede ? api.gruposAlmacen() : []]);
      if (!vivo) return;
      const opcionesMp = materias.map((m) => `<option value="${m.id}">${esc(m.nombre)}</option>`).join('');
      filtros.materia.innerHTML = `<option value="">Todas</option>${opcionesMp}`;
      if (puede) {
        editorLlegada = prepararFormulario(zona.querySelector('#form-llegada'), materias, provs, pintarHistorial, filtros, grupos);
        formularioNota(zona.querySelector('#zona-nota'), { materias, provs, grupos, alGuardar: pintarHistorial });
        zona.querySelectorAll('[name=modo-llegada]').forEach((r) => r.addEventListener('change', () => {
          const nota = zona.querySelector('[name=modo-llegada]:checked').value === 'nota';
          zona.querySelector('#zona-nota').classList.toggle('oculto', !nota);
          zona.querySelector('#form-llegada').classList.toggle('oculto', nota);
        }));
      }
    } catch (e) { aviso(e.message, 'error'); }
  })();

  filtros.addEventListener('change', pintarHistorial);
  hist.addEventListener('click', (ev) => {
    const b = ev.target.closest('[data-editar-llegada]');
    if (b && editorLlegada) editorLlegada.editar(porIdLlegada.get(b.dataset.editarLlegada));
  });
  if (location.hash.includes('pendientes')) filtros.pendientes.checked = true;
  cargando(hist);
  pintarHistorial();
  const soltar = api.enVivo('llegadas_mp', () => pintarHistorial());
  return () => { vivo = false; soltar(); };
}

function prepararFormulario(form, materias, provs, alGuardar, filtros, grupos) {
  const NUEVO = '__nuevo__', NUEVA_MP = '__nueva_mp__';
  form.fecha.value = hoy();
  const pintarMaterias = (elegida = '') => {
    const op = materias.map((m) => `<option value="${m.id}">${esc(m.nombre)}</option>`).join('');
    form.materia_prima_id.innerHTML = `<option value="">Elige…</option>${op}<option value="${NUEVA_MP}">+ Agregar materia prima nueva…</option>`;
    form.materia_prima_id.value = elegida;
    const filtroAntes = filtros.materia.value;
    filtros.materia.innerHTML = `<option value="">Todas</option>${op}`;
    filtros.materia.value = filtroAntes;
  };
  pintarMaterias();
  const cajaNuevaMp = form.querySelector('#campo-nueva-mp');
  const elegirMateria = (id) => {
    cajaNuevaMp.classList.add('oculto'); cajaNuevaMp.innerHTML = '';
    pintarMaterias(id ? String(id) : '');
    form.materia_prima_id.dispatchEvent(new Event('change'));
  };
  const pintarProvs = (lista, elegido = '') => {
    form.proveedor_id.innerHTML = `<option value="">Sin proveedor</option>${lista.map((p) => `<option value="${p.id}">${esc(p.nombre)}</option>`).join('')}<option value="${NUEVO}">+ Agregar proveedor nuevo…</option>`;
    form.proveedor_id.value = elegido;
  };
  pintarProvs(provs);

  const campoNuevo = form.querySelector('#campo-nuevo-prov');
  form.proveedor_id.addEventListener('change', () => {
    const nuevo = form.proveedor_id.value === NUEVO;
    campoNuevo.classList.toggle('oculto', !nuevo);
    if (nuevo) form.nuevo_proveedor.focus();
  });
  form.querySelector('#btn-guardar-prov').addEventListener('click', async () => {
    const nombre = form.nuevo_proveedor.value.trim().toUpperCase();
    if (!nombre) return form.nuevo_proveedor.focus();
    try {
      const p = await api.crearProveedor(nombre);
      provs.push(p);
      provs.sort((a, b) => a.nombre.localeCompare(b.nombre));
      pintarProvs(provs, String(p.id));
      form.nuevo_proveedor.value = '';
      campoNuevo.classList.add('oculto');
      aviso(`Proveedor ${p.nombre} agregado.`);
    } catch (e) { aviso(e.message, 'error'); }
  });

  // ---- Contrato: corte automático con cada llegada ----
  let contratos = [];
  let editando = null;   // llegada que se está corrigiendo
  const campoTc = form.querySelector('#campo-tc');
  const ayudaContrato = form.querySelector('#ayuda-contrato');
  const contratoElegido = () => contratos.find((c) => String(c.id) === form.contrato_id.value);
  const pintarAyudaContrato = () => {
    const c = contratoElegido();
    campoTc.classList.toggle('oculto', !c || c.moneda !== 'USD');
    if (!c) { ayudaContrato.textContent = form.materia_prima_id.value ? 'Compra libre: no descuenta de ningún contrato.' : ''; return; }
    const kg = parseFloat(form.kg_neto.value) || 0;
    // Al editar, lo que esta llegada ya surtía vuelve a contar como pendiente.
    const yaSurtido = editando && editando.contrato_id === c.id ? Math.max(0, Number(editando.kg_neto) - Number(editando.kg_excedente_contrato || 0)) : 0;
    const pendiente = Number(c.kg_pendientes) + yaSurtido;
    const exceso = kg - pendiente;
    ayudaContrato.textContent = `Pendiente ${fmt.t(pendiente)} de ${fmt.t(c.kg_contratados)}`
      + (exceso > 0.5 ? ` · excedente de contrato: ${fmt.kg(exceso)} (se registra al precio del contrato)` : kg ? ` · quedarán ${fmt.t(pendiente - kg)}` : '');
    ayudaContrato.classList.toggle('ayuda-alerta', exceso > 0.5);
  };
  const aplicarContrato = () => {
    const c = contratoElegido();
    if (c) {
      if (String(c.proveedor_id) !== form.proveedor_id.value) form.proveedor_id.value = String(c.proveedor_id);
      if (c.moneda === 'MXN') form.precio_kg.value = Number(c.precio);
      else if (form.tipo_cambio.value) form.precio_kg.value = (Number(c.precio) * Number(form.tipo_cambio.value)).toFixed(4);
    }
    pintarAyudaContrato();
  };
  const cargarContratos = async (contratoFijo = null) => {
    const materia = form.materia_prima_id.value;
    contratos = [];
    form.contrato_id.innerHTML = '<option value="">Compra libre (sin contrato)</option>';
    if (materia) {
      try {
        contratos = (await api.contratos({ materia })).filter((c) => c.estado === 'abierto' || c.id === contratoFijo);
        form.contrato_id.innerHTML += contratos.map((c) => `<option value="${c.id}">${esc(c.folio || `#${c.id}`)} · ${esc(c.proveedor)} · pendiente ${fmt.t(c.kg_pendientes)} · ${precioContrato(c)}${c.estado_actual === 'vencido' ? ' · VENCIDO' : ''}</option>`).join('');
        if (contratoFijo) form.contrato_id.value = String(contratoFijo);
        else {
          // Si hay uno solo (o uno solo del proveedor elegido), se elige solo.
          const delProv = contratos.filter((c) => String(c.proveedor_id) === form.proveedor_id.value && Number(c.kg_pendientes) > 0);
          const candidato = delProv.length === 1 ? delProv[0] : contratos.length === 1 ? contratos[0] : null;
          if (candidato) form.contrato_id.value = String(candidato.id);
        }
      } catch (e) { aviso(e.message, 'error'); }
    }
  };
  form.materia_prima_id.addEventListener('change', async () => {
    const materia = form.materia_prima_id.value;
    if (materia === NUEVA_MP) {
      cajaNuevaMp.classList.remove('oculto');
      miniFormularioMateria(cajaNuevaMp, materias, grupos, {
        alCrear: (m) => { materias.push(m); materias.sort((a, b) => a.nombre.localeCompare(b.nombre)); elegirMateria(m.id); },
        alElegir: (id) => elegirMateria(id),
        alCancelar: () => elegirMateria(null),
      });
      return;
    }
    if (!cajaNuevaMp.classList.contains('oculto')) { cajaNuevaMp.classList.add('oculto'); cajaNuevaMp.innerHTML = ''; }
    await cargarContratos();
    aplicarContrato();
  });
  form.contrato_id.addEventListener('change', aplicarContrato);
  form.tipo_cambio.addEventListener('input', aplicarContrato);

  // Neto = bruto − tara (si se capturan los dos). Total = neto × precio.
  const recalcular = (ev) => {
    const bruto = parseFloat(form.kg_bruto.value), tara = parseFloat(form.kg_tara.value);
    if (ev && (ev.target === form.kg_bruto || ev.target === form.kg_tara) && !isNaN(bruto) && !isNaN(tara)) {
      form.kg_neto.value = Math.max(0, bruto - tara).toFixed(2);
    }
    const total = (parseFloat(form.kg_neto.value) || 0) * (parseFloat(form.precio_kg.value) || 0);
    form.total.value = fmt.dinero(total);
    pintarAyudaContrato();
  };
  form.addEventListener('input', recalcular);

  // Boleta repetida = error; factura repetida = solo aviso (una factura puede cubrir varios viajes).
  const repetidos = { boleta: [], factura: [] };
  const esperas = {};
  const revisarRepetido = async (campo) => {
    const valor = form[campo].value.trim();
    const ayuda = form.querySelector(`#ayuda-${campo}`);
    repetidos[campo] = [];
    if (valor) {
      try {
        const r = await api.buscarLlegadaPor(campo, valor);
        if (valor === form[campo].value.trim()) repetidos[campo] = r.filter((l) => !editando || l.id !== editando.id);
      } catch { /* la base de datos valida la boleta al guardar */ }
    }
    const otra = repetidos[campo][0];
    ayuda.textContent = !otra ? '' : campo === 'boleta'
      ? `La boleta ya está en la llegada del ${fmt.fecha(otra.fecha)} (${otra.materia_prima}). No puede repetirse.`
      : `Esta factura ya está en ${repetidos[campo].length} llegada${repetidos[campo].length > 1 ? 's' : ''} (${fmt.fecha(otra.fecha)}, ${otra.materia_prima}). Si cubre varios viajes, está bien.`;
    ayuda.classList.toggle('ayuda-error', !!otra && campo === 'boleta');
    ayuda.classList.toggle('ayuda-alerta', !!otra && campo === 'factura');
  };
  ['boleta', 'factura'].forEach((campo) => form[campo].addEventListener('input', () => {
    clearTimeout(esperas[campo]); esperas[campo] = setTimeout(() => revisarRepetido(campo), 350);
  }));

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    if (form.proveedor_id.value === NUEVO) return aviso('Agrega el proveedor nuevo o elige uno de la lista.', 'error');
    if (form.boleta.value.trim()) {
      await revisarRepetido('boleta');
      if (repetidos.boleta.length) { form.boleta.focus(); return aviso(`La boleta ${form.boleta.value.trim()} ya está registrada. No puede repetirse.`, 'error'); }
    }
    if (form.materia_prima_id.value === NUEVA_MP) return aviso('Agrega la materia prima nueva o elige una de la lista.', 'error');
    const bruto = parseFloat(form.kg_bruto.value), tara = parseFloat(form.kg_tara.value);
    if (!isNaN(bruto) && !isNaN(tara) && Math.abs(bruto - tara - parseFloat(form.kg_neto.value)) > 0.5) {
      return aviso('El neto no coincide con bruto − tara. Revisa los kilos.', 'error');
    }
    const c = contratoElegido();
    if (c && c.moneda === 'USD' && !form.tipo_cambio.value) return aviso('El contrato es en dólares: captura el tipo de cambio (si aún no se paga, uno estimado y marca "provisional").', 'error');
    const n = (v) => (v === '' ? null : Number(v));
    const datos = {
      contrato_id: c ? c.id : null,
      tipo_cambio: c && c.moneda === 'USD' ? Number(form.tipo_cambio.value) : null,
      fecha: form.fecha.value,
      materia_prima_id: Number(form.materia_prima_id.value),
      proveedor_id: form.proveedor_id.value ? Number(form.proveedor_id.value) : null,
      kg_bruto: n(form.kg_bruto.value),
      kg_tara: n(form.kg_tara.value),
      kg_neto: Number(form.kg_neto.value),
      humedad_pct: n(form.humedad_pct.value),
      precio_kg: Number(form.precio_kg.value),
      factura: form.factura.value.trim() || null,
      boleta: form.boleta.value.trim() || null,
      notas: form.notas.value.trim() || null,
      precio_provisional: form.precio_provisional.checked,
    };
    const boton = form.querySelector('button[type=submit]');
    boton.disabled = true; boton.textContent = 'Guardando…';
    try {
      const mp = form.materia_prima_id.selectedOptions[0]?.textContent;
      if (editando) {
        await api.actualizarLlegada(editando.id, datos);
        if (editando.nota_id && (datos.factura || '') !== (editando.factura || '')) {
          await api.facturaNota(editando.nota_id, datos.factura);
          aviso(`La factura se aplicó a los ${editando.nota_productos} productos de la nota.`);
        }
        aviso(`Llegada corregida: ${fmt.kg(datos.kg_neto)} de ${mp}. Existencias y costos recalculados.`);
      } else {
        await api.crearLlegada(datos);
        const faltan = [!datos.factura && 'factura', datos.precio_provisional && 'precio definitivo'].filter(Boolean);
        aviso(`Llegada guardada: ${fmt.kg(datos.kg_neto)} de ${mp}.${faltan.length ? ` Queda pendiente: ${faltan.join(' y ')}.` : ''}`);
      }
      limpiar();
      alGuardar();
    } catch (e) {
      aviso(e.message, 'error');
    } finally {
      boton.disabled = false; boton.textContent = editando ? 'Guardar cambios' : 'Guardar llegada';
    }
  });

  // ---- Edición ----
  const titulo = form.querySelector('#titulo-llegada');
  const btnCancelar = form.querySelector('#btn-cancelar-llegada');
  const btnEliminar = form.querySelector('#btn-eliminar-llegada');
  function limpiar() {
    const fecha = form.fecha.value;
    form.reset();
    form.fecha.value = editando ? hoy() : fecha;
    editando = null;
    contratos = [];
    form.contrato_id.innerHTML = '<option value="">Elige primero la materia prima</option>';
    titulo.textContent = 'Registrar llegada';
    form.querySelector('button[type=submit]').textContent = 'Guardar llegada';
    btnCancelar.classList.add('oculto');
    btnEliminar.classList.add('oculto');
    btnEliminar.dataset.confirmar = '';
    btnEliminar.textContent = 'Eliminar llegada';
    form.classList.remove('editando');
    ['boleta', 'factura'].forEach((c) => { repetidos[c] = []; form.querySelector(`#ayuda-${c}`).textContent = ''; });
    recalcular();
  }
  btnCancelar.addEventListener('click', limpiar);
  btnEliminar.addEventListener('click', async () => {
    if (btnEliminar.dataset.confirmar !== 'si') { btnEliminar.dataset.confirmar = 'si'; btnEliminar.textContent = 'Confirmar: eliminar llegada'; return; }
    try {
      await api.eliminarLlegada(editando.id);
      aviso('Llegada eliminada; existencias y costos recalculados.');
      limpiar();
      alGuardar();
    } catch (e) { aviso(e.message, 'error'); }
  });

  async function editar(l) {
    editando = l;
    form.fecha.value = l.fecha;
    if (!materias.some((m) => m.id === l.materia_prima_id)) materias.push({ id: l.materia_prima_id, nombre: l.materia_prima });
    pintarMaterias(String(l.materia_prima_id));
    if (l.proveedor_id && !provs.some((p) => p.id === l.proveedor_id)) { provs.push({ id: l.proveedor_id, nombre: l.proveedor }); }
    pintarProvs(provs, l.proveedor_id ? String(l.proveedor_id) : '');
    await cargarContratos(l.contrato_id);
    form.tipo_cambio.value = l.tipo_cambio ?? '';
    const v = (x) => (x == null ? '' : x);
    form.kg_bruto.value = v(l.kg_bruto); form.kg_tara.value = v(l.kg_tara); form.kg_neto.value = v(l.kg_neto);
    form.humedad_pct.value = v(l.humedad_pct); form.precio_kg.value = v(l.precio_kg);
    form.factura.value = v(l.factura); form.boleta.value = v(l.boleta); form.notas.value = v(l.notas);
    form.precio_provisional.checked = !!l.precio_provisional;
    pintarAyudaContrato();
    recalcular();
    titulo.textContent = `Editar llegada: ${l.materia_prima}, ${fmt.fecha(l.fecha)}`;
    form.querySelector('button[type=submit]').textContent = 'Guardar cambios';
    btnCancelar.classList.remove('oculto');
    btnEliminar.classList.toggle('oculto', !sesion.esAdmin());
    form.classList.add('editando');
    form.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
  return { editar };
}

// ---------- Existencias ----------

function existencias(zona) {
  let vivo = true;
  async function pintar() {
    try {
      const exis = await api.existencias();
      if (!vivo) return;
      const valor = exis.reduce((s, x) => s + Number(x.valor_inventario || 0), 0);
      zona.innerHTML = `
        <p class="nota">Calculado con todas las llegadas, órdenes de producción y ajustes. Costo = promedio ponderado. Valor total: <b>${fmt.dinero(valor)}</b>.</p>
        ${tablaExistencias(exis)}`;
    } catch (e) { if (vivo) errorEn(zona, e); }
  }
  cargando(zona);
  pintar();
  const soltar = api.enVivo('llegadas_mp', () => pintar());
  return () => { vivo = false; soltar(); };
}

function tablaExistencias(filas) {
  return `
    <div class="tabla-scroll"><table>
      <thead><tr><th>Materia prima</th><th>Categoría</th><th class="num">Existencia</th><th class="num">Costo promedio</th><th class="num">Valor</th></tr></thead>
      <tbody>${filas.map((x) => `
        <tr class="${Number(x.existencia_kg) < 0 ? 'fila-negativa' : x.bajo_minimo ? 'fila-alerta' : ''}">
          <td>${esc(x.nombre)}</td>
          <td>${esc(x.categoria)}</td>
          <td class="num">${Math.abs(Number(x.existencia_kg)) >= 10000 ? fmt.t(x.existencia_kg) : fmt.kg(x.existencia_kg)}</td>
          <td class="num">${fmt.precio(x.costo_promedio)}</td>
          <td class="num">${fmt.dinero(x.valor_inventario)}</td>
        </tr>`).join('')}
      </tbody>
    </table></div>`;
}
