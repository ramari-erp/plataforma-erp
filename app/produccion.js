// Planta → Producción: órdenes con fórmula ajustable por orden y extras (medicamentos o ingredientes aparte).
import { api } from './api.js';
import { esc, fmt, hoy, aviso, cargando, errorEn } from './ui.js';
import { sesion } from './sesion.js';

const ESPECIES = { cerdos: 'Cerdos', aves: 'Aves', ganado: 'Ganado', borregos: 'Borregos', otro: 'Otros' };
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
    </form>
    <div id="historial-ordenes"></div>`;
  const filtros = zona.querySelector('#filtros-ordenes');
  filtros.desde.value = hoy(-30);
  filtros.hasta.value = hoy();
  const hist = zona.querySelector('#historial-ordenes');
  const pintarHistorial = () => historial(hist, filtros, () => vivo);

  if (puede) {
    (async () => {
      try {
        const [formulas, exis] = await Promise.all([api.formulas(), api.existencias()]);
        if (vivo) formularioOrden(zona.querySelector('#zona-orden'), formulas, exis, pintarHistorial);
      } catch (e) { errorEn(zona.querySelector('#zona-orden'), e); }
    })();
  }
  filtros.addEventListener('change', pintarHistorial);
  cargando(hist);
  pintarHistorial();
  const soltar = api.enVivo('ordenes_produccion', pintarHistorial);
  return () => { vivo = false; soltar(); };
}

// ---------- Formulario ----------

function formularioOrden(zona, formulas, exis, alGuardar) {
  const materias = new Map(exis.map((m) => [m.id, m]));
  const opcionesFormula = Object.entries(ESPECIES).map(([esp, nombre]) => {
    const lista = formulas.filter((f) => (f.especie || 'otro') === esp);
    return lista.length ? `<optgroup label="${nombre}">${lista.map((f) => `<option value="${f.id}">${esc(f.nombre)}</option>`).join('')}</optgroup>` : '';
  }).join('');
  const ordenadas = [...materias.values()].sort((a, b) => a.nombre.localeCompare(b.nombre));
  const opcionesMp = (preferir) => {
    const primero = ordenadas.filter((m) => preferir(m)), resto = ordenadas.filter((m) => !preferir(m));
    const op = (l) => l.map((m) => `<option value="${m.id}">${esc(m.nombre)}</option>`).join('');
    return `<option value="">Elige…</option><optgroup label="Medicamentos y aditivos">${op(primero)}</optgroup><optgroup label="Ingredientes">${op(resto)}</optgroup>`;
  };
  const esMedicamento = (m) => m.categoria === 'medicamento';

  zona.innerHTML = `
    <form class="tarjeta formulario" id="form-orden" autocomplete="off">
      <h2>Nueva orden de producción</h2>
      <div class="rejilla">
        <label>Fecha<input type="date" name="fecha" value="${hoy()}" required></label>
        <label class="ancho2">Fórmula<select name="formula" required><option value="">Elige…</option>${opcionesFormula}</select></label>
        <label>Toneladas producidas<input type="number" name="toneladas" min="0.001" step="0.001" inputmode="decimal" required></label>
      </div>

      <div id="bloque-ingredientes" class="oculto">
        <h3>Ingredientes de esta orden</h3>
        <p class="nota">Vienen de la fórmula. Cambia los kg por tonelada si en esta orden se usó otra cantidad, quita o agrega ingredientes. Solo afecta a esta orden.</p>
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
      </div>
    </form>`;

  const form = zona.querySelector('#form-orden');
  const cuerpo = form.querySelector('#filas-ing');
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

  const leer = () => {
    const t = numero(form.toneladas.value) || 0;
    const ingredientes = [...cuerpo.querySelectorAll('tr')].map((tr) => ({
      tr, materia_prima_id: Number(tr.dataset.id), kg_por_tonelada: numero(tr.querySelector('[name=kgt]').value),
    }));
    const extras = [...extrasZona.querySelectorAll('.fila-extra')].map((d) => ({
      materia_prima_id: numero(d.querySelector('[name=extra_mp]').value),
      cantidad: numero(d.querySelector('[name=extra_cant]').value),
      unidad: d.querySelector('[name=extra_unidad]').value,
      nota: d.querySelector('[name=extra_nota]').value.trim(),
    }));
    return { t, ingredientes, extras };
  };

  const actualizar = () => {
    const { t, ingredientes, extras } = leer();
    let totalKgt = 0, modificada = ingredientes.length !== base.size;
    const necesidad = new Map();
    for (const i of ingredientes) {
      const kgt = i.kg_por_tonelada ?? 0;
      totalKgt += kgt;
      const usar = kgt * t;
      i.tr.querySelector('.usar').textContent = t ? kgFmt(usar) : '—';
      const cambio = !base.has(i.materia_prima_id) || Math.abs(base.get(i.materia_prima_id) - kgt) > 0.00005;
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
    form.querySelector('#resumen-orden').textContent = t
      ? `${fmt.t(t * 1000)} · costo estimado ${fmt.dinero(costo)} (${fmt.precio(costo / (t * 1000))})${modificada ? ' · fórmula modificada' : ''}${nExtras ? ` · ${nExtras} extra${nExtras > 1 ? 's' : ''}` : ''}`
      : '';
  };

  form.formula.addEventListener('change', async () => {
    const id = Number(form.formula.value);
    const bloque = form.querySelector('#bloque-ingredientes');
    if (!id) { bloque.classList.add('oculto'); return; }
    try {
      const ing = await api.formulaIngredientes(id);
      base = new Map(ing.map((i) => [i.materia_prima_id, Number(i.kg_por_tonelada)]));
      cuerpo.innerHTML = ing
        .sort((a, b) => Number(b.kg_por_tonelada) - Number(a.kg_por_tonelada))
        .map((i) => filaIngrediente(i.materia_prima_id, Number(i.kg_por_tonelada))).join('');
      bloque.classList.remove('oculto');
      actualizar();
    } catch (e) { aviso(e.message, 'error'); }
  });

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
    const { t, ingredientes, extras } = leer();
    if (!t) return aviso('Captura las toneladas producidas.', 'error');
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
        kg: Math.round(t * 1000 * 100) / 100,
        ingredientes: ingredientes.map(({ materia_prima_id, kg_por_tonelada }) => ({ materia_prima_id, kg_por_tonelada })),
        extras: extras.filter((e) => e.materia_prima_id && e.cantidad),
        notas: form.notas.value.trim() || null,
        actualizarFormula: !!form.actualizar_base?.checked && !form.querySelector('#campo-base')?.classList.contains('oculto'),
      });
      aviso(`Orden guardada: ${fmt.t(t * 1000)} de ${formula}.`);
      // Existencias nuevas para la siguiente orden
      const nuevas = await api.existencias();
      nuevas.forEach((m) => materias.set(m.id, m));
      const fecha = form.fecha.value;
      form.reset();
      form.fecha.value = fecha;
      cuerpo.innerHTML = ''; extrasZona.innerHTML = '';
      form.querySelector('#bloque-ingredientes').classList.add('oculto');
      alGuardar();
    } catch (e) {
      aviso(e.message, 'error');
    } finally {
      boton.disabled = false; boton.textContent = 'Guardar orden';
    }
  });
}

// ---------- Historial ----------

async function historial(zona, filtros, sigueVivo) {
  try {
    const filas = await api.ordenes({ desde: filtros.desde.value, hasta: filtros.hasta.value });
    if (!sigueVivo()) return;
    if (!filas.length) { zona.innerHTML = '<p class="vacio">No hay órdenes en esas fechas.</p>'; return; }
    const kg = filas.reduce((s, o) => s + Number(o.kg_producidos), 0);
    const costo = filas.reduce((s, o) => s + Number(o.costo_mp), 0);
    const admin = sesion.esAdmin();
    zona.innerHTML = `
      <p class="nota">${filas.length} órdenes · ${fmt.t(kg)} · costo de materia prima ${fmt.dinero(costo)} (${fmt.precio(kg ? costo / kg : 0)})</p>
      <div class="tabla-scroll"><table>
        <thead><tr><th>Fecha</th><th>Fórmula</th><th class="num">Producido</th><th class="num">Costo/kg</th><th class="num">Costo MP</th><th>Cambios</th><th>Capturó</th><th></th></tr></thead>
        <tbody>${filas.map((o) => `
          <tr data-orden="${o.id}">
            <td>${fmt.fecha(o.fecha)}</td>
            <td>${esc(o.formula)}${o.notas ? `<small>${esc(o.notas)}</small>` : ''}</td>
            <td class="num">${fmt.t(o.kg_producidos)}</td>
            <td class="num">${fmt.precio(o.costo_kg)}</td>
            <td class="num">${fmt.dinero(o.costo_mp)}</td>
            <td>${o.formula_modificada ? '<span class="etiqueta">Fórmula modificada</span> ' : ''}${Number(o.extras) ? `<span class="etiqueta etiqueta-extra">${o.extras} extra${Number(o.extras) > 1 ? 's' : ''}</span>` : ''}</td>
            <td>${esc(o.capturado_por || '—')}<small>${esc(fmt.hora(o.capturado_en))}</small></td>
            <td><button type="button" class="boton boton-chico" data-ver="${o.id}" aria-expanded="false">Ver</button></td>
          </tr>`).join('')}
        </tbody>
      </table></div>`;

    zona.querySelector('tbody').addEventListener('click', async (ev) => {
      const ver = ev.target.closest('[data-ver]');
      const borrar = ev.target.closest('[data-borrar]');
      if (ver) {
        const tr = ver.closest('tr');
        const siguiente = tr.nextElementSibling;
        if (siguiente?.classList.contains('detalle')) { siguiente.remove(); ver.setAttribute('aria-expanded', 'false'); return; }
        ver.setAttribute('aria-expanded', 'true');
        tr.insertAdjacentHTML('afterend', `<tr class="detalle"><td colspan="8"><p class="cargando">Cargando…</p></td></tr>`);
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
          historial(zona, filtros, sigueVivo);
        } catch (e) { aviso(e.message, 'error'); borrar.disabled = false; }
      }
    });
  } catch (e) { if (sigueVivo()) errorEn(zona, e); }
}
