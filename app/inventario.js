// Planta → Inventario físico: inventario de arranque (una vez) y conteo físico semanal.
import { api } from './api.js';
import { esc, fmt, hoy, aviso, cargando, errorEn } from './ui.js';
import { sesion } from './sesion.js';

const ORDEN_CATEGORIA = ['grano', 'pasta', 'mineral', 'ingrediente', 'aminoacido', 'nucleo', 'alimento_comprado', 'medicamento', 'otro'];
const NOMBRE_CATEGORIA = {
  grano: 'Granos', pasta: 'Pastas', mineral: 'Minerales', ingrediente: 'Ingredientes', aminoacido: 'Aminoácidos',
  nucleo: 'Núcleos', alimento_comprado: 'Alimento comprado', medicamento: 'Medicamentos y aditivos', otro: 'Otros',
};

function ordenar(lista) {
  return lista.slice().sort((a, b) =>
    ORDEN_CATEGORIA.indexOf(a.categoria) - ORDEN_CATEGORIA.indexOf(b.categoria) || a.nombre.localeCompare(b.nombre));
}

const numero = (v) => (v === '' || v == null ? null : Number(v));

export function seccionInventario(zona) {
  let vivo = true;
  const puede = sesion.puedeCapturar('planta');

  async function pintar() {
    cargando(zona);
    try {
      const [exis, inicial] = await Promise.all([api.existencias(), api.inventarioInicial()]);
      if (!vivo) return;
      const materias = ordenar(exis);
      if (!inicial.length) {
        if (!puede) {
          zona.innerHTML = '<div class="caja caja-info">Todavía no se captura el inventario de arranque de la planta.</div>';
          return;
        }
        return formularioArranque(zona, materias, new Map(), pintar);
      }
      zona.innerHTML = `
        ${puede ? '<div id="zona-conteo"></div>' : ''}
        <h2>Historial de conteos</h2>
        <div id="historial-conteos"></div>
        <details class="tarjeta desplegable">
          <summary>Inventario de arranque (${fmt.fecha(inicial[0].fecha)})</summary>
          <div id="zona-arranque"></div>
        </details>`;
      if (puede) formularioConteo(zona.querySelector('#zona-conteo'), materias, pintar);
      historialConteos(zona.querySelector('#historial-conteos'));
      const porId = new Map(inicial.map((i) => [i.materia_prima_id, i]));
      const arr = zona.querySelector('#zona-arranque');
      if (sesion.esAdmin()) formularioArranque(arr, materias, porId, pintar);
      else arr.innerHTML = tablaArranqueLectura(materias, porId);
    } catch (e) { if (vivo) errorEn(zona, e); }
  }
  pintar();
  return () => { vivo = false; };
}

// ---------- Inventario de arranque ----------

function formularioArranque(zona, materias, previo, alGuardar) {
  const nuevo = previo.size === 0;
  const fechaPrevia = nuevo ? hoy() : [...previo.values()][0].fecha;
  let categoriaActual = null;
  const filas = materias.map((m) => {
    const p = previo.get(m.id);
    const encabezado = m.categoria !== categoriaActual
      ? `<tr class="fila-grupo"><td colspan="4">${esc(NOMBRE_CATEGORIA[m.categoria] || m.categoria)}</td></tr>` : '';
    categoriaActual = m.categoria;
    const costo = p ? p.costo_kg : (m.precio_referencia ?? '');
    return `${encabezado}
      <tr data-id="${m.id}" data-nombre="${esc(m.nombre.toLowerCase())}">
        <td>${esc(m.nombre)}</td>
        <td class="num"><input type="number" class="celda-num" name="kg" min="0" step="0.01" inputmode="decimal" value="${p ? p.kg : ''}" aria-label="Kg de ${esc(m.nombre)}"></td>
        <td class="num"><input type="number" class="celda-num" name="costo" min="0" step="0.0001" inputmode="decimal" value="${costo}" aria-label="Costo por kg de ${esc(m.nombre)}"></td>
        <td class="num valor">—</td>
      </tr>`;
  }).join('');

  zona.innerHTML = `
    <form class="formulario" id="form-arranque">
      ${nuevo ? `
        <h2>Inventario de arranque</h2>
        <div class="caja caja-info">
          <p>Captura lo que hay físicamente en la planta el día que empiezan a usar la plataforma: kilos y costo por kilo de cada materia prima.
          Es el punto de partida; desde ahí el sistema suma llegadas y resta lo que se produce.</p>
          <p>El costo viene sugerido con los precios de septiembre de tu archivo de costos; cámbialo si tienes uno más reciente.
          Deja en blanco lo que no haya en planta.</p>
        </div>` : `
        <p class="nota">Como administrador puedes corregir el arranque. Al guardar, el sistema recalcula existencias y costos.</p>`}
      <div class="filtros">
        <label>Fecha del inventario<input type="date" name="fecha" value="${fechaPrevia}" required></label>
        <label>Buscar<input type="search" name="buscar" placeholder="Nombre de la materia prima"></label>
      </div>
      <div class="tabla-scroll"><table class="tabla-captura">
        <thead><tr><th>Materia prima</th><th class="num">Kg en planta</th><th class="num">Costo $/kg</th><th class="num">Valor</th></tr></thead>
        <tbody>${filas}</tbody>
      </table></div>
      <p class="resumen-captura" id="resumen-arranque"></p>
      <div class="caja caja-alerta oculto" id="confirmar-arranque"></div>
      <button class="boton boton-primario" type="submit">${nuevo ? 'Revisar y guardar' : 'Guardar cambios'}</button>
    </form>`;

  const form = zona.querySelector('#form-arranque');
  const leer = () => [...form.querySelectorAll('tbody tr[data-id]')].map((tr) => ({
    tr,
    materia_prima_id: Number(tr.dataset.id),
    nombre: tr.cells[0].textContent,
    kg: numero(tr.querySelector('[name=kg]').value),
    costo_kg: numero(tr.querySelector('[name=costo]').value),
  }));
  const actualizar = () => {
    let kg = 0, valor = 0, n = 0;
    for (const f of leer()) {
      const v = (f.kg ?? 0) * (f.costo_kg ?? 0);
      f.tr.querySelector('.valor').textContent = f.kg == null ? '—' : fmt.dinero(v);
      if (f.kg != null) { n += 1; kg += f.kg; valor += v; }
    }
    form.querySelector('#resumen-arranque').textContent = `${n} materias primas · ${fmt.t(kg)} · ${fmt.dinero(valor)}`;
    form.querySelector('#confirmar-arranque').classList.add('oculto');
    if (nuevo) form.querySelector('button[type=submit]').textContent = 'Revisar y guardar';
  };
  form.addEventListener('input', (ev) => {
    if (ev.target.name === 'buscar') {
      const t = ev.target.value.trim().toLowerCase();
      form.querySelectorAll('tbody tr').forEach((tr) => {
        tr.classList.toggle('oculto', !!t && (!tr.dataset.nombre || !tr.dataset.nombre.includes(t)));
      });
      return;
    }
    actualizar();
  });
  actualizar();

  let confirmado = false;
  form.addEventListener('input', () => { confirmado = false; });
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const items = leer().filter((f) => f.kg != null);
    if (!items.length) return aviso('Captura al menos una materia prima.', 'error');
    const sinCosto = items.filter((f) => f.kg > 0 && !f.costo_kg);
    const caja = form.querySelector('#confirmar-arranque');
    if (nuevo && !confirmado) {
      const kg = items.reduce((s, f) => s + f.kg, 0);
      const valor = items.reduce((s, f) => s + f.kg * (f.costo_kg ?? 0), 0);
      caja.innerHTML = `
        <p><b>Revisa antes de guardar:</b> ${items.length} materias primas, ${fmt.t(kg)}, valor ${fmt.dinero(valor)}, con fecha ${fmt.fecha(form.fecha.value)}.</p>
        ${sinCosto.length ? `<p>Sin costo: ${sinCosto.map((f) => esc(f.nombre)).join(', ')}. Se valuarán en $0.</p>` : ''}
        <p>Si todo está bien, presiona <b>Confirmar y guardar</b>.</p>`;
      caja.classList.remove('oculto');
      form.querySelector('button[type=submit]').textContent = 'Confirmar y guardar';
      confirmado = true;
      return;
    }
    const boton = form.querySelector('button[type=submit]');
    boton.disabled = true; boton.textContent = 'Guardando…';
    try {
      const n = await api.guardarInventarioInicial(form.fecha.value,
        items.map(({ materia_prima_id, kg, costo_kg }) => ({ materia_prima_id, kg, costo_kg: costo_kg ?? 0 })));
      aviso(`Inventario de arranque guardado: ${n} materias primas.`);
      alGuardar();
    } catch (e) {
      aviso(e.message, 'error');
      boton.disabled = false; boton.textContent = 'Confirmar y guardar';
    }
  });
}

function tablaArranqueLectura(materias, porId) {
  const filas = materias.filter((m) => porId.has(m.id)).map((m) => {
    const p = porId.get(m.id);
    return `<tr><td>${esc(m.nombre)}</td><td class="num">${fmt.kg(p.kg)}</td><td class="num">${fmt.precio(p.costo_kg)}</td><td class="num">${fmt.dinero(p.kg * p.costo_kg)}</td></tr>`;
  }).join('');
  return `<div class="tabla-scroll"><table>
    <thead><tr><th>Materia prima</th><th class="num">Kg</th><th class="num">Costo</th><th class="num">Valor</th></tr></thead>
    <tbody>${filas}</tbody></table></div>`;
}

// ---------- Conteo físico ----------

function formularioConteo(zona, materias, alGuardar) {
  let categoriaActual = null;
  const filas = materias.map((m) => {
    const encabezado = m.categoria !== categoriaActual
      ? `<tr class="fila-grupo"><td colspan="4">${esc(NOMBRE_CATEGORIA[m.categoria] || m.categoria)}</td></tr>` : '';
    categoriaActual = m.categoria;
    return `${encabezado}
      <tr data-id="${m.id}" data-sistema="${Number(m.existencia_kg)}" data-nombre="${esc(m.nombre.toLowerCase())}">
        <td>${esc(m.nombre)}</td>
        <td class="num">${fmt.kg(m.existencia_kg)}</td>
        <td class="num"><input type="number" class="celda-num" name="fisico" min="0" step="0.01" inputmode="decimal" aria-label="Kg contados de ${esc(m.nombre)}"></td>
        <td class="num diferencia">—</td>
      </tr>`;
  }).join('');

  zona.innerHTML = `
    <form class="tarjeta formulario" id="form-conteo">
      <h2>Conteo físico</h2>
      <p class="nota">Captura solo lo que contaste. Si no coincide con el sistema, se registra un ajuste por la diferencia y la existencia queda igual a lo contado.
      Haz el conteo al cierre del día, después de capturar las llegadas y la producción.</p>
      <div class="filtros">
        <label>Fecha del conteo<input type="date" name="fecha" value="${hoy()}" max="${hoy()}" required></label>
        <label>Buscar<input type="search" name="buscar" placeholder="Nombre de la materia prima"></label>
      </div>
      <div class="tabla-scroll"><table class="tabla-captura">
        <thead><tr><th>Materia prima</th><th class="num">Sistema hoy</th><th class="num">Kg contados</th><th class="num">Diferencia</th></tr></thead>
        <tbody>${filas}</tbody>
      </table></div>
      <p class="resumen-captura" id="resumen-conteo"></p>
      <button class="boton boton-primario" type="submit">Guardar conteo</button>
    </form>`;

  const form = zona.querySelector('#form-conteo');
  const leer = () => [...form.querySelectorAll('tbody tr[data-id]')]
    .map((tr) => ({ tr, materia_prima_id: Number(tr.dataset.id), sistema: Number(tr.dataset.sistema), fisico: numero(tr.querySelector('[name=fisico]').value) }));
  const actualizar = () => {
    let n = 0, conDif = 0;
    for (const f of leer()) {
      const celda = f.tr.querySelector('.diferencia');
      celda.classList.remove('dif-menos', 'dif-mas');
      if (f.fisico == null) { celda.textContent = '—'; continue; }
      n += 1;
      const d = f.fisico - f.sistema;
      if (Math.abs(d) >= 0.01) conDif += 1;
      celda.textContent = `${d > 0 ? '+' : ''}${fmt.kg(d)}`;
      if (d < -0.005) celda.classList.add('dif-menos');
      if (d > 0.005) celda.classList.add('dif-mas');
    }
    form.querySelector('#resumen-conteo').textContent = n ? `${n} materias contadas · ${conDif} con diferencia` : '';
  };
  form.addEventListener('input', (ev) => {
    if (ev.target.name === 'buscar') {
      const t = ev.target.value.trim().toLowerCase();
      form.querySelectorAll('tbody tr').forEach((tr) => tr.classList.toggle('oculto', !!t && (!tr.dataset.nombre || !tr.dataset.nombre.includes(t))));
      return;
    }
    actualizar();
  });

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const items = leer().filter((f) => f.fisico != null).map(({ materia_prima_id, fisico }) => ({ materia_prima_id, kg_fisicos: fisico }));
    if (!items.length) return aviso('Captura al menos un conteo.', 'error');
    const boton = form.querySelector('button[type=submit]');
    boton.disabled = true; boton.textContent = 'Guardando…';
    try {
      const res = await api.registrarConteo(form.fecha.value, items);
      const dif = res.filter((r) => Number(r.diferencia) !== 0);
      aviso(dif.length
        ? `Conteo guardado. Ajustes: ${dif.map((r) => `${r.materia} ${Number(r.diferencia) > 0 ? '+' : ''}${fmt.kg(r.diferencia)}`).join(', ')}.`
        : `Conteo guardado: ${res.length} materias, todo cuadra.`);
      alGuardar();
    } catch (e) {
      aviso(e.message, 'error');
      boton.disabled = false; boton.textContent = 'Guardar conteo';
    }
  });
}

async function historialConteos(zona) {
  cargando(zona);
  try {
    const filas = await api.conteos({ desde: hoy(-90) });
    if (!filas.length) { zona.innerHTML = '<p class="vacio">Aún no hay conteos.</p>'; return; }
    zona.innerHTML = `
      <div class="tabla-scroll"><table>
        <thead><tr><th>Fecha</th><th>Materia prima</th><th class="num">Sistema</th><th class="num">Contado</th><th class="num">Diferencia</th><th>Capturó</th></tr></thead>
        <tbody>${filas.map((c) => {
          const d = Number(c.diferencia);
          return `<tr>
            <td>${fmt.fecha(c.fecha)}</td><td>${esc(c.materia_prima)}</td>
            <td class="num">${fmt.kg(c.kg_sistema)}</td><td class="num">${fmt.kg(c.kg_fisicos)}</td>
            <td class="num ${d < 0 ? 'dif-menos' : d > 0 ? 'dif-mas' : ''}">${d > 0 ? '+' : ''}${fmt.kg(d)}</td>
            <td>${esc(c.capturado_por || '—')}</td></tr>`;
        }).join('')}</tbody>
      </table></div>`;
  } catch (e) { errorEn(zona, e); }
}
