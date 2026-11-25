// Planta → Producción: órdenes con fórmula ajustable por orden y extras (medicamentos o ingredientes aparte).
import { api } from './api.js';
import { esc, fmt, hoy, aviso, cargando, errorEn } from './ui.js';
import { sesion } from './sesion.js';
import { parecidas, normalizar } from './materias.js';

const ESPECIES = { cerdos: 'Cerdos', aves: 'Aves', ganado: 'Ganado', borregos: 'Borregos', otro: 'Otros' };
const AREAS = { cerdos: 'Cerdos', aves: 'Aves', ganado: 'Ganado', borregos: 'Borregos' };
const numero = (v) => (v === '' || v == null ? null : Number(v));
const kgFmt = (v) => fmt.kg(Math.round(Number(v) * 100) / 100);

export function seccionProduccion(zona) {
  let vivo = true;
  const puede = sesion.puedeCapturar('planta');
  zona.innerHTML = `
    ${puede ? '<div id="zona-orden"></div>' : '<div class="caja caja-info">Puedes consultar las órdenes. Para capturarlas pide permiso de Planta al administrador.</div>'}
    <h2>Órdenes de producción</h2>
    <form class="filtros" id="filtros-ordenes">
      <label>Desde<input type="date" name="desde"></label>
      <label>Hasta<input type="date" name="hasta"></label>
      <label>Área<select name="area"><option value="">Todas</option>${Object.entries(AREAS).map(([v, t]) => `<option value="${v}">${t}</option>`).join('')}</select></label>
      <label>Granja destino<select name="granja"><option value="">Todas</option><option value="ninguna">Sin granja</option></select></label>
    </form>
    <div id="historial-ordenes"></div>`;
  const filtros = zona.querySelector('#filtros-ordenes');
  filtros.desde.value = hoy(-30);
  filtros.hasta.value = hoy();
  const hist = zona.querySelector('#historial-ordenes');
  let editor = null;   // el formulario expone editar(orden)
  const pintarHistorial = () => historial(hist, filtros, () => vivo, (orden) => editor?.editar(orden), pintarHistorial);

  if (puede) {
    (async () => {
      try {
        const [formulas, exis, granjas, granjaAreas] = await Promise.all([api.formulas(), api.existencias(), api.granjas(), api.granjaAreas()]);
        if (vivo) editor = formularioOrden(zona.querySelector('#zona-orden'), formulas, exis, granjas.filter((g) => g.activa), granjaAreas, pintarHistorial);
      } catch (e) { errorEn(zona.querySelector('#zona-orden'), e); }
    })();
  }
  api.granjas().then((gs) => {
    filtros.granja.insertAdjacentHTML('beforeend', gs.map((g) => `<option value="${g.id}">${esc(g.nombre)}</option>`).join(''));
  }).catch(() => {});
  filtros.addEventListener('change', pintarHistorial);
  cargando(hist);
  pintarHistorial();
  const soltar = api.enVivo('ordenes_produccion', pintarHistorial);
  return () => { vivo = false; soltar(); };
}

// ---------- Formulario ----------

function formularioOrden(zona, formulas, exis, granjas, granjaAreas, alGuardar) {
  const materias = new Map(exis.map((m) => [m.id, m]));
  const NUEVA_F = '__nueva_formula__';
  const opcionesFormula = () => Object.entries(ESPECIES).map(([esp, nombre]) => {
    const lista = formulas.filter((f) => (f.especie || 'otro') === esp);
    return lista.length ? `<optgroup label="${nombre}">${lista.map((f) => `<option value="${f.id}">${esc(f.nombre)}</option>`).join('')}</optgroup>` : '';
  }).join('') + `<option value="${NUEVA_F}">+ Agregar fórmula nueva…</option>`;
  const ordenadas = [...materias.values()].sort((a, b) => a.nombre.localeCompare(b.nombre));
  const opcionesMp = (preferir) => {
    const primero = ordenadas.filter((m) => preferir(m)), resto = ordenadas.filter((m) => !preferir(m));
    const op = (l) => l.map((m) => `<option value="${m.id}">${esc(m.nombre)}</option>`).join('');
    return `<option value="">Elige…</option><optgroup label="Medicamentos y aditivos">${op(primero)}</optgroup><optgroup label="Ingredientes">${op(resto)}</optgroup>`;
  };
  const esMedicamento = (m) => m.categoria === 'medicamento';

  zona.innerHTML = `
    <form class="tarjeta formulario" id="form-orden" autocomplete="off">
      <h2 id="titulo-orden">Nueva orden de producción</h2>
      <div class="rejilla">
        <label>Fecha<input type="date" name="fecha" value="${hoy()}" required></label>
        <label class="ancho2">Fórmula<select name="formula" required><option value="">Elige…</option>${opcionesFormula()}</select></label>
        <label>Kg solicitados<input type="number" name="kg_solicitados" min="0.01" step="0.01" inputmode="decimal" required></label>
        <label>Kg reales (pesada)<input type="number" name="kg_reales" min="0.01" step="0.01" inputmode="decimal" placeholder="Si ya se pesó"></label>
        <label>Área<select name="area"><option value="">Elige…</option>${Object.entries(AREAS).map(([v, t]) => `<option value="${v}">${t}</option>`).join('')}</select></label>
        <label>Granja destino<select name="granja"></select></label>
        <div class="ancho-total caja caja-info oculto" id="campo-nueva-formula"></div>
      </div>

      <div id="bloque-ingredientes" class="oculto">
        <h3>Ingredientes de esta orden</h3>
        <p class="nota oculto" id="nota-formula-nueva"><b>Fórmula nueva sin ingredientes:</b> agrégalos abajo; los de esta orden quedarán como su fórmula base.</p>
        <p class="nota" id="nota-formula">Vienen de la fórmula. Cambia los kg por tonelada si en esta orden se usó otra cantidad, quita o agrega ingredientes. Solo afecta a esta orden.</p>
        <div class="tabla-scroll"><table class="tabla-captura">
          <thead><tr><th>Ingrediente</th><th class="num">Kg por tonelada</th><th class="num">Kg a usar</th><th class="num">Existencia</th><th></th></tr></thead>
          <tbody id="filas-ing"></tbody>
          <tfoot><tr><td><b>Total</b></td><td class="num" id="total-kgt"></td><td class="num" id="total-kg"></td><td colspan="2"></td></tr></tfoot>
        </table></div>
        <div class="agregar-fila">
          <select name="nuevo_ing" aria-label="Ingrediente a agregar">${opcionesMp(() => false)}</select>
          <input type="number" name="nuevo_ing_kgt" min="0.0001" step="0.0001" inputmode="decimal" placeholder="Kg por t" aria-label="Kg por tonelada del ingrediente a agregar">
          <button type="button" class="boton boton-chico" id="btn-agregar-ing">Agregar ingrediente</button>
        </div>

        <h3>Extras agregados aparte</h3>
        <p class="nota">Medicamentos o ingredientes extra que se agregaron en esta orden.</p>
        <div id="filas-extras"></div>
        <button type="button" class="boton boton-chico" id="btn-agregar-extra">+ Agregar extra</button>

        <div class="caja caja-alerta oculto" id="alertas-orden"></div>
        <label class="ancho-total">Notas<input name="notas" maxlength="300"></label>
        ${sesion.puedeCapturar('catalogos') ? `
          <label class="casilla oculto" id="campo-base"><input type="checkbox" name="actualizar_base">
            Guardar estos cambios como la nueva fórmula base (las próximas órdenes los traerán)</label>` : ''}
        <p class="resumen-captura" id="resumen-orden"></p>
        <button class="boton boton-primario" type="submit">Guardar orden</button>
        <button class="boton oculto" type="button" id="btn-cancelar-edicion">Cancelar edición</button>
      </div>
    </form>`;

  const form = zona.querySelector('#form-orden');
  const cuerpo = form.querySelector('#filas-ing');

  // Granjas del área elegida (si no hay área, todas las activas).
  const pintarGranjas = () => {
    const area = form.area.value, antes = form.granja.value;
    const ids = new Set(granjaAreas.filter((x) => x.area === area).map((x) => x.granja_id));
    const lista = area ? granjas.filter((g) => ids.has(g.id)) : granjas;
    form.granja.innerHTML = `<option value="">Sin granja (queda en planta)</option>${lista.map((g) => `<option value="${g.id}">${esc(g.nombre)}</option>`).join('')}`;
    if (lista.some((g) => String(g.id) === antes)) form.granja.value = antes;
  };
  pintarGranjas();
  form.area.addEventListener('change', pintarGranjas);
  const extrasZona = form.querySelector('#filas-extras');
  let base = new Map();   // materia_prima_id → kg/t de la fórmula base

  const filaIngrediente = (id, kgt) => {
    const m = materias.get(id);
    return `<tr data-id="${id}">
      <td>${esc(m?.nombre || `#${id}`)} <span class="etiqueta oculto">Modificado</span></td>
      <td class="num"><input type="number" class="celda-num" name="kgt" min="0.0001" step="0.0001" inputmode="decimal" value="${kgt}" aria-label="Kg por tonelada de ${esc(m?.nombre)}"></td>
      <td class="num usar"></td>
      <td class="num exis">${m ? kgFmt(m.existencia_kg) : '—'}</td>
      <td><button type="button" class="boton boton-chico" data-quitar aria-label="Quitar ${esc(m?.nombre)}">Quitar</button></td>
    </tr>`;
  };
  const filaExtra = () => `
    <div class="fila-extra">
      <select name="extra_mp" aria-label="Medicamento o ingrediente extra">${opcionesMp(esMedicamento)}</select>
      <input type="number" name="extra_cant" min="0.0001" step="0.0001" inputmode="decimal" placeholder="Cantidad" aria-label="Cantidad">
      <select name="extra_unidad" aria-label="Unidad"><option value="kg_por_tonelada">kg por tonelada</option><option value="kg_total">kg en total</option></select>
      <input name="extra_nota" maxlength="200" placeholder="Nota (motivo, caseta…)" aria-label="Nota">
      <button type="button" class="boton boton-chico" data-quitar-extra>Quitar</button>
    </div>`;

  // Lo que cuenta para el inventario: la pesada real si ya está; si no, lo solicitado.
  const leer = () => {
    const kgSol = numero(form.kg_solicitados.value), kgReal = numero(form.kg_reales.value);
    const t = (kgReal || kgSol || 0) / 1000;
    const ingredientes = [...cuerpo.querySelectorAll('tr')].map((tr) => ({
      tr, materia_prima_id: Number(tr.dataset.id), kg_por_tonelada: numero(tr.querySelector('[name=kgt]').value),
    }));
    const extras = [...extrasZona.querySelectorAll('.fila-extra')].map((d) => ({
      materia_prima_id: numero(d.querySelector('[name=extra_mp]').value),
      cantidad: numero(d.querySelector('[name=extra_cant]').value),
      unidad: d.querySelector('[name=extra_unidad]').value,
      nota: d.querySelector('[name=extra_nota]').value.trim(),
    }));
    return { t, kgSol, kgReal, ingredientes, extras };
  };

  const actualizar = () => {
    const { t, kgSol, kgReal, ingredientes, extras } = leer();
    const nueva = base.size === 0;   // fórmula sin base: lo de esta orden será su base
    let totalKgt = 0, modificada = !nueva && ingredientes.length !== base.size;
    const necesidad = new Map();
    for (const i of ingredientes) {
      const kgt = i.kg_por_tonelada ?? 0;
      totalKgt += kgt;
      const usar = kgt * t;
      i.tr.querySelector('.usar').textContent = t ? kgFmt(usar) : '—';
      const cambio = !nueva && (!base.has(i.materia_prima_id) || Math.abs(base.get(i.materia_prima_id) - kgt) > 0.00005);
      i.tr.querySelector('.etiqueta').classList.toggle('oculto', !cambio);
      if (cambio) modificada = true;
      necesidad.set(i.materia_prima_id, (necesidad.get(i.materia_prima_id) || 0) + usar);
    }
    for (const e of extras) {
      if (!e.materia_prima_id || !e.cantidad) continue;
      const kg = e.unidad === 'kg_total' ? e.cantidad : e.cantidad * t;
      necesidad.set(e.materia_prima_id, (necesidad.get(e.materia_prima_id) || 0) + kg);
    }
    form.querySelector('#total-kgt').textContent = `${fmt.kg(totalKgt)}/t`;
    form.querySelector('#total-kg').textContent = t ? kgFmt(totalKgt * t) : '—';

    const alertas = [];
    if (ingredientes.length && Math.abs(totalKgt - 1000) > 1) {
      alertas.push(`La suma de ingredientes es ${fmt.kg(totalKgt)} por tonelada (debería ser 1,000 kg).`);
    }
    const faltan = [...necesidad].filter(([id, kg]) => kg > Number(materias.get(id)?.existencia_kg ?? 0) + 0.005);
    if (t && faltan.length) {
      alertas.push(`No alcanza la existencia de: ${faltan.map(([id, kg]) => `${esc(materias.get(id)?.nombre)} (faltan ${kgFmt(kg - Number(materias.get(id)?.existencia_kg ?? 0))})`).join(', ')}. Puedes guardar, pero revisa el inventario.`);
    }
    const cajaAlertas = form.querySelector('#alertas-orden');
    cajaAlertas.innerHTML = alertas.map((a) => `<p>${a}</p>`).join('');
    cajaAlertas.classList.toggle('oculto', !alertas.length);
    const campoBase = form.querySelector('#campo-base');
    if (campoBase) campoBase.classList.toggle('oculto', !modificada);

    const costo = [...necesidad].reduce((s, [id, kg]) => s + kg * Number(materias.get(id)?.costo_promedio || 0), 0);
    const nExtras = extras.filter((e) => e.materia_prima_id && e.cantidad).length;
    const dif = kgSol && kgReal ? kgReal - kgSol : null;
    form.querySelector('#resumen-orden').textContent = t
      ? `${kgReal ? `Pesada ${fmt.kg(kgReal)}` : `Solicitado ${fmt.kg(kgSol)} (pendiente de pesada)`}${dif != null ? ` · diferencia ${dif > 0 ? '+' : ''}${fmt.kg(dif)} (${fmt.pct(100 * dif / kgSol)})` : ''} · costo estimado ${fmt.dinero(costo)} (${fmt.precio(costo / (t * 1000))})${modificada ? ' · fórmula modificada' : ''}${nExtras ? ` · ${nExtras} extra${nExtras > 1 ? 's' : ''}` : ''}`
      : '';
  };

  // Carga la fórmula base; si se pasan `usados` (al editar), la tabla muestra los de la orden.
  const cargarFormula = async (usados = null) => {
    const id = Number(form.formula.value);
    const bloque = form.querySelector('#bloque-ingredientes');
    if (!id) { bloque.classList.add('oculto'); return; }
    const ing = await api.formulaIngredientes(id);
    base = new Map(ing.map((i) => [i.materia_prima_id, Number(i.kg_por_tonelada)]));
    form.querySelector('#nota-formula-nueva').classList.toggle('oculto', base.size > 0);
    form.querySelector('#nota-formula').classList.toggle('oculto', base.size === 0);
    cuerpo.innerHTML = (usados || ing).slice()
      .sort((a, b) => Number(b.kg_por_tonelada) - Number(a.kg_por_tonelada))
      .map((i) => filaIngrediente(i.materia_prima_id, Number(i.kg_por_tonelada))).join('');
    bloque.classList.remove('oculto');
    actualizar();
  };
  // ---- Fórmula nueva ----
  const cajaNuevaF = form.querySelector('#campo-nueva-formula');
  const cerrarNuevaF = () => { cajaNuevaF.classList.add('oculto'); cajaNuevaF.innerHTML = ''; };
  const elegirFormula = (id) => {
    cerrarNuevaF();
    form.formula.innerHTML = `<option value="">Elige…</option>${opcionesFormula()}`;
    form.formula.value = id ? String(id) : '';
    form.formula.dispatchEvent(new Event('change'));
  };
  const abrirNuevaF = () => {
    cajaNuevaF.classList.remove('oculto');
    form.querySelector('#bloque-ingredientes').classList.add('oculto');
    const opBase = Object.entries(ESPECIES).map(([esp, nombre]) => {
      const lista = formulas.filter((f) => (f.especie || 'otro') === esp);
      return lista.length ? `<optgroup label="${nombre}">${lista.map((f) => `<option value="${f.id}">${esc(f.nombre)}</option>`).join('')}</optgroup>` : '';
    }).join('');
    cajaNuevaF.innerHTML = `
      <p><b>Fórmula nueva</b> — quedará por revisar por el administrador.</p>
      <div class="rejilla">
        <label class="ancho2">Nombre<input name="nf_nombre" maxlength="120" autocomplete="off"></label>
        <label>Área<select name="nf_especie">${Object.entries(ESPECIES).map(([v, t]) => `<option value="${v}" ${v === form.area.value ? 'selected' : ''}>${t}</option>`).join('')}</select></label>
        <label>Etapa<input name="nf_etapa" maxlength="60" placeholder="Iniciador, finalizador…"></label>
        <label class="ancho-total">Partir de<select name="nf_base"><option value="">Fórmula vacía (capturo los ingredientes)</option>${opBase}</select></label>
      </div>
      <div class="parecidas oculto" id="nf-parecidas"></div>
      <button type="button" class="boton boton-chico boton-primario" id="nf-guardar">Agregar fórmula</button>
      <button type="button" class="boton boton-chico" id="nf-cancelar">Cancelar</button>`;
    const $ = (s) => cajaNuevaF.querySelector(s);
    $('[name=nf_nombre]').focus();
    $('[name=nf_nombre]').addEventListener('input', () => {
      const lista = parecidas($('[name=nf_nombre]').value, formulas);
      $('#nf-parecidas').classList.toggle('oculto', !lista.length);
      $('#nf-parecidas').innerHTML = lista.length ? `<span>¿Es alguna de estas? </span>${lista.map((f) => `<button type="button" class="chip" data-elegir="${f.id}">${esc(f.nombre)}</button>`).join('')}` : '';
    });
    $('#nf-parecidas').addEventListener('click', (ev) => { const b = ev.target.closest('[data-elegir]'); if (b) elegirFormula(Number(b.dataset.elegir)); });
    $('#nf-cancelar').addEventListener('click', () => elegirFormula(null));
    cajaNuevaF.onkeydown = (ev) => { if (ev.key === 'Enter' && $('#nf-guardar')) { ev.preventDefault(); $('#nf-guardar').click(); } };
    $('#nf-guardar').addEventListener('click', async () => {
      const nombre = $('[name=nf_nombre]').value.trim();
      if (!nombre) return $('[name=nf_nombre]').focus();
      const exacta = formulas.find((f) => normalizar(f.nombre) === normalizar(nombre));
      if (exacta) { aviso(`Ya existe: ${exacta.nombre}. Se eligió la existente.`); return elegirFormula(exacta.id); }
      $('#nf-guardar').disabled = true;
      try {
        const f = await api.crearFormula({ nombre, especie: $('[name=nf_especie]').value, etapa: $('[name=nf_etapa]').value.trim(), copiarDe: Number($('[name=nf_base]').value) || null });
        formulas.push(f);
        formulas.sort((a, b) => a.nombre.localeCompare(b.nombre));
        aviso(`Fórmula ${f.nombre} agregada${sesion.esAdmin() ? '' : ' (queda por revisar)'}.`);
        elegirFormula(f.id);
      } catch (e) { aviso(e.message, 'error'); $('#nf-guardar').disabled = false; }
    });
  };

  form.formula.addEventListener('change', async () => {
    if (form.formula.value === NUEVA_F) return abrirNuevaF();
    if (!cajaNuevaF.classList.contains('oculto')) cerrarNuevaF();
    const especie = formulas.find((f) => f.id === Number(form.formula.value))?.especie;
    if (AREAS[especie]) { form.area.value = especie; pintarGranjas(); }
    try { await cargarFormula(); } catch (e) { aviso(e.message, 'error'); }
  });

  // ---- Modo edición ----
  let ordenId = null;
  const titulo = form.querySelector('#titulo-orden');
  const btnCancelar = form.querySelector('#btn-cancelar-edicion');
  const limpiar = () => {
    const fecha = form.fecha.value;
    form.reset();
    form.fecha.value = ordenId ? hoy() : fecha;
    ordenId = null;
    cuerpo.innerHTML = ''; extrasZona.innerHTML = ''; base = new Map();
    pintarGranjas();
    form.querySelector('#bloque-ingredientes').classList.add('oculto');
    titulo.textContent = 'Nueva orden de producción';
    form.querySelector('button[type=submit]').textContent = 'Guardar orden';
    btnCancelar.classList.add('oculto');
    form.classList.remove('editando');
  };
  btnCancelar.addEventListener('click', limpiar);

  async function editar(o) {
    try {
      const [usados, extras] = await Promise.all([api.ingredientesOrden(o.id), api.extrasOrden(o.id)]);
      ordenId = o.id;
      form.fecha.value = o.fecha;
      form.formula.value = String(o.formula_id);
      form.area.value = o.area || '';
      pintarGranjas();
      form.granja.value = o.granja_id ? String(o.granja_id) : '';
      form.kg_solicitados.value = o.kg_solicitados ?? o.kg_producidos;
      form.kg_reales.value = o.kg_reales ?? '';
      form.notas.value = o.notas || '';
      extrasZona.innerHTML = extras.map(() => filaExtra()).join('');
      [...extrasZona.querySelectorAll('.fila-extra')].forEach((d, i) => {
        const e = extras.at(i);
        d.querySelector('[name=extra_mp]').value = String(e.materia_prima_id);
        d.querySelector('[name=extra_cant]').value = e.cantidad;
        d.querySelector('[name=extra_unidad]').value = e.unidad;
        d.querySelector('[name=extra_nota]').value = e.nota || '';
      });
      await cargarFormula(usados.length ? usados : null);
      titulo.textContent = `Editar orden: ${o.formula}, ${fmt.fecha(o.fecha)}`;
      form.querySelector('button[type=submit]').textContent = 'Guardar cambios';
      btnCancelar.classList.remove('oculto');
      form.classList.add('editando');
      form.scrollIntoView({ behavior: 'smooth', block: 'start' });
    } catch (e) { aviso(e.message, 'error'); }
  }

  form.querySelector('#btn-agregar-ing').addEventListener('click', () => {
    const id = numero(form.nuevo_ing.value), kgt = numero(form.nuevo_ing_kgt.value);
    if (!id || !kgt) return aviso('Elige el ingrediente y sus kg por tonelada.', 'error');
    if (cuerpo.querySelector(`tr[data-id="${id}"]`)) return aviso('Ese ingrediente ya está en la lista; cambia su cantidad.', 'error');
    cuerpo.insertAdjacentHTML('beforeend', filaIngrediente(id, kgt));
    form.nuevo_ing.value = ''; form.nuevo_ing_kgt.value = '';
    actualizar();
  });
  form.querySelector('#btn-agregar-extra').addEventListener('click', () => {
    extrasZona.insertAdjacentHTML('beforeend', filaExtra());
    extrasZona.lastElementChild.querySelector('select').focus();
  });
  form.addEventListener('click', (ev) => {
    if (ev.target.closest('[data-quitar]')) { ev.target.closest('tr').remove(); actualizar(); }
    if (ev.target.closest('[data-quitar-extra]')) { ev.target.closest('.fila-extra').remove(); actualizar(); }
  });
  form.addEventListener('input', actualizar);
  form.addEventListener('change', actualizar);

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const { t, kgSol, kgReal, ingredientes, extras } = leer();
    if (!kgSol) return aviso('Captura los kg solicitados.', 'error');
    if (form.formula.value === NUEVA_F) return aviso('Agrega la fórmula nueva o elige una de la lista.', 'error');
    if (!ingredientes.length) return aviso('La orden necesita al menos un ingrediente.', 'error');
    if (ingredientes.some((i) => !i.kg_por_tonelada)) return aviso('Hay un ingrediente sin kg por tonelada.', 'error');
    const incompletos = extras.filter((e) => (e.materia_prima_id && !e.cantidad) || (!e.materia_prima_id && e.cantidad));
    if (incompletos.length) return aviso('Hay un extra incompleto: elige qué es y su cantidad, o quítalo.', 'error');
    const boton = form.querySelector('button[type=submit]');
    boton.disabled = true; boton.textContent = 'Guardando…';
    const formula = form.formula.selectedOptions[0]?.textContent;
    try {
      await api.guardarOrden({
        fecha: form.fecha.value,
        formulaId: Number(form.formula.value),
        granjaId: form.granja.value ? Number(form.granja.value) : null,
        area: form.area.value || null,
        kg: kgSol,
        kgReales: kgReal,
        ordenId,
        ingredientes: ingredientes.map(({ materia_prima_id, kg_por_tonelada }) => ({ materia_prima_id, kg_por_tonelada })),
        extras: extras.filter((e) => e.materia_prima_id && e.cantidad),
        notas: form.notas.value.trim() || null,
        actualizarFormula: !!form.actualizar_base?.checked && !form.querySelector('#campo-base')?.classList.contains('oculto'),
      });
      const granja = form.granja.value ? ` para ${form.granja.selectedOptions[0].textContent}` : '';
      aviso(ordenId ? `Orden corregida: ${formula}.` : `Orden guardada: ${fmt.kg(kgReal || kgSol)} de ${formula}${granja}${kgReal ? '' : ' (pendiente de pesada)'}.`);
      // Existencias nuevas para la siguiente orden
      const nuevas = await api.existencias();
      nuevas.forEach((m) => materias.set(m.id, m));
      limpiar();
      alGuardar();
    } catch (e) {
      aviso(e.message, 'error');
    } finally {
      boton.disabled = false;
      boton.textContent = ordenId ? 'Guardar cambios' : 'Guardar orden';
    }
  });
  return { editar };
}

// ---------- Historial ----------

// Selección para la pesada conjunta (se conserva al recargar el historial).
const seleccion = new Map();
let pesadaCorrigiendo = null;

async function historial(zona, filtros, sigueVivo, alEditar, recargar) {
  try {
    const filas = await api.ordenes({ desde: filtros.desde.value, hasta: filtros.hasta.value, granja: filtros.granja.value || null, area: filtros.area.value || null });
    if (!sigueVivo()) return;
    if (!filas.length) { zona.innerHTML = '<p class="vacio">No hay órdenes en esas fechas.</p>'; return; }
    const kg = filas.reduce((s, o) => s + Number(o.kg_producidos), 0);
    const costo = filas.reduce((s, o) => s + Number(o.costo_mp), 0);
    const admin = sesion.esAdmin();
    const puede = sesion.puedeCapturar('planta');
    const pendientes = filas.filter((o) => o.pendiente_pesada).length;
    const porId = new Map(filas.map((o) => [String(o.id), o]));
    const columnas = puede ? 11 : 10;
    zona.innerHTML = `
      ${puede ? `<div class="caja caja-info barra-pesada oculto" id="barra-pesada"></div>` : ''}
      <p class="nota">${filas.length} órdenes · ${fmt.t(kg)} · costo de materia prima ${fmt.dinero(costo)} (${fmt.precio(kg ? costo / kg : 0)})${pendientes ? ` · <b>${pendientes} pendiente${pendientes > 1 ? 's' : ''} de pesada</b>` : ''}</p>
      <div class="tabla-scroll"><table>
        <thead><tr>${puede ? '<th title="Selecciona las órdenes que se cargaron y pesaron juntas">Pesar<br>juntas</th>' : ''}<th>Fecha</th><th>Fórmula</th><th>Destino</th><th class="num">Solicitado</th><th class="num">Pesada real</th><th class="num">Costo/kg</th><th class="num">Costo MP</th><th>Cambios</th><th>Capturó</th><th></th></tr></thead>
        <tbody>${filas.map((o) => `
          <tr data-orden="${o.id}">
            ${puede ? `<td><input type="checkbox" data-sel="${o.id}" aria-label="Pesar junto con otras: ${esc(o.formula)}" ${seleccion.has(o.id) ? 'checked' : ''}></td>` : ''}
            <td>${fmt.fecha(o.fecha)}</td>
            <td>${esc(o.formula)}${o.notas ? `<small>${esc(o.notas)}</small>` : ''}</td>
            <td>${esc(o.granja || '—')}<small>${esc(AREAS[o.area] || 'Sin área')}</small></td>
            <td class="num">${fmt.kg(o.kg_solicitados)}</td>
            <td class="num celda-pesada">${celdaPesada(o, puede)}</td>
            <td class="num">${fmt.precio(o.costo_kg)}</td>
            <td class="num">${fmt.dinero(o.costo_mp)}</td>
            <td>${o.formula_modificada ? '<span class="etiqueta">Fórmula modificada</span> ' : ''}${Number(o.extras) ? `<span class="etiqueta etiqueta-extra">${o.extras} extra${Number(o.extras) > 1 ? 's' : ''}</span>` : ''}</td>
            <td>${esc(o.capturado_por || '—')}<small>${esc(fmt.hora(o.capturado_en))}</small>${o.modificado_por ? `<small>Modificó ${esc(o.modificado_por)}, ${esc(fmt.hora(o.modificado_en))}</small>` : ''}</td>
            <td class="acciones"><button type="button" class="boton boton-chico" data-ver="${o.id}" aria-expanded="false">Ver</button>${puede ? `<button type="button" class="boton boton-chico" data-editar="${o.id}">Editar</button>` : ''}</td>
          </tr>`).join('')}
        </tbody>
      </table></div>`;

    // ---- Pesada conjunta: varias órdenes pesadas juntas ----
    const barra = zona.querySelector('#barra-pesada');
    // El campo del total se pinta una sola vez; al escribir solo se actualizan el reparto y la diferencia
    // (si se volviera a pintar el campo, el cursor regresaría al inicio y el número se escribiría al revés).
    const pintarReparto = () => {
      const ords = [...seleccion.values()];
      const sol = ords.reduce((s, o) => s + Number(o.kg_solicitados), 0);
      const total = numero(barra.querySelector('[name=kg_total]').value);
      barra.querySelector('.titulo-pesada').innerHTML = `<b>${pesadaCorrigiendo ? 'Corregir pesada conjunta' : 'Pesada conjunta'}:</b> ${ords.length} órden${ords.length === 1 ? '' : 'es'} · ordenado ${fmt.kg(sol)}${ords.length < 2 ? ' — elige al menos otra orden' : ''}`;
      barra.querySelector('.lista-reparto').innerHTML = ords.map((o) => `<li>${esc(o.formula)}: ordenado ${fmt.kg(o.kg_solicitados)}${total ? ` → <b>${fmt.kg(Math.round(o.kg_solicitados * total / sol * 100) / 100)}</b>` : ''}</li>`).join('');
      barra.querySelector('.nota-diferencia').innerHTML = total && sol ? `Diferencia ${total - sol > 0 ? '+' : ''}${fmt.kg(total - sol)} (${fmt.pct(100 * (total - sol) / sol)}), repartida en proporción a lo ordenado.` : '';
      const btn = barra.querySelector('[data-registrar-conjunta]');
      btn.disabled = ords.length < 2;
      btn.textContent = pesadaCorrigiendo ? 'Guardar corrección' : 'Registrar pesada conjunta';
    };
    const pintarBarra = () => {
      if (!barra) return;
      const ords = [...seleccion.values()];
      barra.classList.toggle('oculto', ords.length === 0);
      if (!ords.length) return;
      if (!barra.querySelector('[name=kg_total]')) {
        barra.innerHTML = `
          <p class="titulo-pesada"></p>
          <ul class="lista-reparto"></ul>
          <div class="en-linea">
            <input type="number" name="kg_total" class="celda-num" min="0.01" step="0.01" inputmode="decimal" placeholder="Total báscula (kg)" aria-label="Total de la báscula en kg" value="${pesadaCorrigiendo ? esc(String(pesadaCorrigiendo.total ?? '')) : ''}">
            <button type="button" class="boton boton-chico boton-primario" data-registrar-conjunta></button>
            <button type="button" class="boton boton-chico" data-cancelar-conjunta>Cancelar</button>
          </div>
          <p class="nota nota-diferencia"></p>`;
      }
      pintarReparto();
    };
    if (barra) {
      barra.addEventListener('input', (ev) => { if (ev.target.name === 'kg_total') pintarReparto(); });
      barra.addEventListener('click', async (ev) => {
        if (ev.target.closest('[data-cancelar-conjunta]')) {
          seleccion.clear(); pesadaCorrigiendo = null;
          zona.querySelectorAll('[data-sel]').forEach((c) => { c.checked = false; });
          barra.innerHTML = '';
          return pintarBarra();
        }
        const btn = ev.target.closest('[data-registrar-conjunta]');
        if (!btn) return;
        const total = numero(barra.querySelector('[name=kg_total]').value);
        if (!total || total <= 0) return aviso('Captura el total de la báscula.', 'error');
        btn.disabled = true;
        try {
          await api.registrarPesadaConjunta([...seleccion.keys()], total, pesadaCorrigiendo?.id ?? null);
          aviso(`Pesada conjunta registrada: ${fmt.kg(total)} repartidos entre ${seleccion.size} órdenes. La materia prima se recalculó.`);
          seleccion.clear(); pesadaCorrigiendo = null;
          recargar();
        } catch (e) { aviso(e.message, 'error'); btn.disabled = false; }
      });
      pintarBarra();
    }
    zona.querySelector('tbody').addEventListener('change', (ev) => {
      const c = ev.target.closest('[data-sel]');
      if (!c) return;
      const o = porId.get(c.dataset.sel);
      if (c.checked) seleccion.set(o.id, o); else seleccion.delete(o.id);
      pintarBarra();
    });

    zona.querySelector('tbody').addEventListener('click', async (ev) => {
      const conjunta = ev.target.closest('[data-corregir-conjunta]');
      if (conjunta) {
        try {
          const grupo = await api.ordenes({ pesadaConjunta: conjunta.dataset.corregirConjunta });
          seleccion.clear();
          grupo.forEach((o) => seleccion.set(o.id, o));
          pesadaCorrigiendo = { id: Number(conjunta.dataset.corregirConjunta), total: grupo[0]?.pesada_kg_total ?? '' };
          zona.querySelectorAll('[data-sel]').forEach((c) => { c.checked = seleccion.has(Number(c.dataset.sel)); });
          if (barra) barra.innerHTML = '';
          pintarBarra();
          barra?.scrollIntoView({ behavior: 'smooth', block: 'center' });
        } catch (e) { aviso(e.message, 'error'); }
        return;
      }
      const ver = ev.target.closest('[data-ver]');
      const borrar = ev.target.closest('[data-borrar]');
      const editarBtn = ev.target.closest('[data-editar]');
      const pesadaBtn = ev.target.closest('[data-pesada]');
      const guardarPesada = ev.target.closest('[data-guardar-pesada]');
      if (editarBtn) return alEditar(porId.get(editarBtn.dataset.editar));
      if (pesadaBtn) {
        const o = porId.get(pesadaBtn.dataset.pesada);
        const celda = pesadaBtn.closest('td');
        celda.innerHTML = `<span class="en-linea"><input type="number" class="celda-num" min="0.01" step="0.01" inputmode="decimal" value="${o.kg_reales ?? ''}" placeholder="Kg reales" aria-label="Kg reales de la pesada">
          <button type="button" class="boton boton-chico boton-primario" data-guardar-pesada="${o.id}">Guardar</button></span>`;
        celda.querySelector('input').focus();
        return;
      }
      if (guardarPesada) {
        const valor = numero(guardarPesada.closest('td').querySelector('input').value);
        if (!valor || valor <= 0) return aviso('Captura los kg reales de la pesada.', 'error');
        guardarPesada.disabled = true;
        try {
          await api.registrarPesada(Number(guardarPesada.dataset.guardarPesada), valor);
          aviso(`Pesada registrada: ${fmt.kg(valor)}. La materia prima se recalculó.`);
          recargar();
        } catch (e) { aviso(e.message, 'error'); guardarPesada.disabled = false; }
        return;
      }
      if (ver) {
        const tr = ver.closest('tr');
        const siguiente = tr.nextElementSibling;
        if (siguiente?.classList.contains('detalle')) { siguiente.remove(); ver.setAttribute('aria-expanded', 'false'); return; }
        ver.setAttribute('aria-expanded', 'true');
        tr.insertAdjacentHTML('afterend', `<tr class="detalle"><td colspan="${columnas}"><p class="cargando">Cargando…</p></td></tr>`);
        const celda = tr.nextElementSibling.firstElementChild;
        try {
          const [consumos, extras] = await Promise.all([api.consumosOrden(ver.dataset.ver), api.extrasOrden(ver.dataset.ver)]);
          const notas = extras.filter((e) => e.nota);
          celda.innerHTML = `
            <table class="tabla-detalle">
              <thead><tr><th>Consumo</th><th class="num">Kg</th><th class="num">Costo</th><th class="num">Importe</th></tr></thead>
              <tbody>${consumos.map((c) => `<tr><td>${esc(c.materia_prima)}${c.es_extra ? ' <span class="etiqueta etiqueta-extra">Extra</span>' : ''}</td>
                <td class="num">${kgFmt(c.kg)}</td><td class="num">${fmt.precio(c.costo_kg)}</td><td class="num">${fmt.dinero(c.importe)}</td></tr>`).join('')}</tbody>
            </table>
            ${notas.length ? `<p class="nota">Notas de extras: ${notas.map((e) => esc(e.nota)).join(' · ')}</p>` : ''}
            ${admin ? `<button type="button" class="boton boton-chico boton-peligro" data-borrar="${ver.dataset.ver}">Eliminar orden</button>` : ''}`;
        } catch (e) { celda.innerHTML = `<span class="caja-error">${esc(e.message)}</span>`; }
      }
      if (borrar) {
        if (borrar.dataset.confirmar !== 'si') {
          borrar.dataset.confirmar = 'si';
          borrar.textContent = 'Confirmar: eliminar y devolver materia prima';
          return;
        }
        borrar.disabled = true;
        try {
          await api.eliminarOrden(borrar.dataset.borrar);
          aviso('Orden eliminada; la materia prima regresó al inventario.');
          recargar();
        } catch (e) { aviso(e.message, 'error'); borrar.disabled = false; }
      }
    });
  } catch (e) { if (sigueVivo()) errorEn(zona, e); }
}

function celdaPesada(o, puede) {
  if (o.pendiente_pesada) {
    return `<span class="etiqueta">Pendiente de pesada</span>${puede ? `<button type="button" class="boton boton-chico" data-pesada="${o.id}">Capturar</button>` : ''}`;
  }
  const d = Number(o.kg_diferencia);
  const conjunta = o.pesada_conjunta_id
    ? `<small>Pesada conjunta: ${fmt.kg(o.pesada_kg_total)} de ${o.pesada_ordenes} alimentos</small>${puede ? `<button type="button" class="boton-enlace" data-corregir-conjunta="${o.pesada_conjunta_id}">Corregir conjunta</button>` : ''}`
    : (puede ? `<button type="button" class="boton-enlace" data-pesada="${o.id}">Corregir</button>` : '');
  return `${fmt.kg(o.kg_reales)}<small class="${d < 0 ? 'dif-menos' : d > 0 ? 'dif-mas' : ''}">${d > 0 ? '+' : ''}${fmt.kg(d)} (${fmt.pct(o.pct_diferencia)})</small>${conjunta}`;
}
