// Planta → Fórmulas: catálogo con ingredientes; el administrador revisa las nuevas.
import { api } from './api.js';
import { esc, fmt, aviso, cargando, errorEn } from './ui.js';
import { sesion } from './sesion.js';
import { normalizar } from './materias.js';

const ESPECIES = { cerdos: 'Cerdos', aves: 'Aves', ganado: 'Ganado', borregos: 'Borregos', otro: 'Otros' };

export function seccionFormulas(zona) {
  let vivo = true;
  const admin = sesion.esAdmin();
  zona.innerHTML = `
    <p class="nota">${admin ? 'Revisa las fórmulas nuevas: corrige nombre, área y etapa, y márcalas como revisadas. Los ingredientes base se cambian desde una orden de producción con la casilla “Guardar como nueva fórmula base”.' : 'Fórmulas con sus ingredientes por tonelada. Las correcciones las hace el administrador.'}</p>
    <form class="filtros" id="filtros-f">
      <label>Mostrar<select name="ver"><option value="activas">Activas</option><option value="revisar">Por revisar</option><option value="inactivas">Inactivas</option></select></label>
      <label>Área<select name="area"><option value="">Todas</option>${Object.entries(ESPECIES).map(([v, t]) => `<option value="${v}">${t}</option>`).join('')}</select></label>
      <label>Buscar<input type="search" name="buscar" placeholder="Nombre"></label>
    </form>
    <div id="lista-f"></div>`;
  const lista = zona.querySelector('#lista-f');
  const filtros = zona.querySelector('#filtros-f');
  let formulas = [];

  function pintar() {
    const t = normalizar(filtros.buscar.value), ver = filtros.ver.value, area = filtros.area.value;
    const filas = formulas.filter((f) => (ver === 'inactivas' ? !f.activa : f.activa) && (ver !== 'revisar' || !f.revisada)
      && (!area || f.especie === area) && (!t || normalizar(f.nombre).includes(t)));
    if (!filas.length) { lista.innerHTML = '<p class="vacio">No hay fórmulas con ese filtro.</p>'; return; }
    const opEsp = (sel) => Object.entries(ESPECIES).map(([v, tx]) => `<option value="${v}" ${v === sel ? 'selected' : ''}>${tx}</option>`).join('');
    lista.innerHTML = `<div class="tabla-scroll"><table class="tabla-captura">
      <thead><tr><th>Fórmula</th><th>Área</th><th>Etapa</th><th class="num">Ingredientes</th><th class="num">Kg/t</th><th class="num">Órdenes</th><th>Estado</th><th></th></tr></thead>
      <tbody>${filas.map((f) => {
        const suma = Number(f.kg_por_tonelada);
        const sumaMal = Number(f.ingredientes) && Math.abs(suma - 1000) > 1;
        return `<tr data-id="${f.id}" class="${f.revisada ? '' : 'fila-alerta'}">
          <td>${admin ? `<input name="nombre" value="${esc(f.nombre)}" maxlength="120" aria-label="Nombre">` : esc(f.nombre)}
            ${f.creada_por ? `<small>Agregó ${esc(f.creada_por)} · ${esc(fmt.hora(f.creada_en))}${f.copiada_de ? ` · copiada de ${esc(f.copiada_de)}` : ''}</small>` : ''}</td>
          <td>${admin ? `<select name="especie" aria-label="Área">${opEsp(f.especie)}</select>` : esc(ESPECIES[f.especie] || f.especie)}</td>
          <td>${admin ? `<input name="etapa" value="${esc(f.etapa || '')}" maxlength="60" aria-label="Etapa">` : esc(f.etapa || '—')}</td>
          <td class="num">${f.ingredientes}</td>
          <td class="num ${sumaMal ? 'dif-menos' : ''}">${Number(f.ingredientes) ? fmt.kg(suma) : '—'}</td>
          <td class="num">${f.ordenes}${f.ultima_orden ? `<small>última ${fmt.fecha(f.ultima_orden)}</small>` : ''}</td>
          <td>${f.revisada ? (f.activa ? '<span class="etiqueta etiqueta-ok">Revisada</span>' : '<span class="etiqueta etiqueta-gris">Inactiva</span>') : '<span class="etiqueta">Por revisar</span>'}</td>
          <td class="acciones"><button type="button" class="boton boton-chico" data-ver aria-expanded="false">Ingredientes</button>${admin ? `
            <button type="button" class="boton boton-chico boton-primario" data-guardar>${f.revisada ? 'Guardar' : 'Guardar y marcar revisada'}</button>
            <button type="button" class="boton boton-chico" data-activa>${f.activa ? 'Desactivar' : 'Activar'}</button>` : ''}</td>
        </tr>`;
      }).join('')}</tbody>
    </table></div>`;
  }

  lista.addEventListener('click', async (ev) => {
    const tr = ev.target.closest('tr[data-id]');
    if (!tr) return;
    const f = formulas.find((x) => String(x.id) === tr.dataset.id);
    const ver = ev.target.closest('[data-ver]');
    if (ver) {
      if (tr.nextElementSibling?.classList.contains('detalle')) { tr.nextElementSibling.remove(); ver.setAttribute('aria-expanded', 'false'); return; }
      ver.setAttribute('aria-expanded', 'true');
      tr.insertAdjacentHTML('afterend', '<tr class="detalle"><td colspan="8"><p class="cargando">Cargando…</p></td></tr>');
      const celda = tr.nextElementSibling.firstElementChild;
      try {
        const ing = await api.ingredientesFormula(f.id);
        const costo = ing.reduce((s, i) => s + Number(i.kg_por_tonelada) * Number(i.costo_promedio), 0) / 1000;
        celda.innerHTML = ing.length ? `<table class="tabla-detalle">
          <thead><tr><th>Ingrediente</th><th class="num">Kg por tonelada</th><th class="num">%</th><th class="num">Costo promedio</th></tr></thead>
          <tbody>${ing.map((i) => `<tr><td>${esc(i.materia_prima)}</td><td class="num">${Number(i.kg_por_tonelada).toLocaleString('es-MX', { maximumFractionDigits: 3 })}</td>
            <td class="num">${fmt.pct(Number(i.kg_por_tonelada) / 10)}</td><td class="num">${fmt.precio(i.costo_promedio)}</td></tr>`).join('')}</tbody>
        </table><p class="nota">Costo de materia prima con los costos promedio de hoy: <b>${fmt.precio(costo)}</b></p>`
          : '<p class="vacio">Sin ingredientes todavía: se llenan con su primera orden de producción.</p>';
      } catch (e) { celda.innerHTML = `<span class="caja-error">${esc(e.message)}</span>`; }
      return;
    }
    let campos = null;
    const v = (n) => tr.querySelector(`[name=${n}]`);
    if (ev.target.closest('[data-guardar]')) {
      const nombre = v('nombre').value.trim().toUpperCase().replace(/\s+/g, ' ');
      if (!nombre) return aviso('El nombre no puede quedar vacío.', 'error');
      const otra = formulas.find((x) => x.id !== f.id && normalizar(x.nombre) === normalizar(nombre));
      if (otra) return aviso(`Ya existe otra fórmula llamada ${otra.nombre}.`, 'error');
      campos = { nombre, especie: v('especie').value, etapa: v('etapa').value.trim() || null, revisada: true };
    } else if (ev.target.closest('[data-activa]')) {
      campos = { activa: !f.activa, revisada: true };
    }
    if (!campos) return;
    try {
      await api.actualizarFormula(f.id, campos);
      Object.assign(f, campos);
      aviso(`${f.nombre} guardada.`);
      pintar();
    } catch (e) { aviso(e.message, 'error'); }
  });
  filtros.addEventListener('input', pintar);

  cargando(lista);
  (async () => {
    try {
      formulas = await api.formulasCatalogo();
      if (!vivo) return;
      if (formulas.some((f) => !f.revisada)) filtros.ver.value = 'revisar';
      pintar();
    } catch (e) { if (vivo) errorEn(lista, e); }
  })();
  return () => { vivo = false; };
}
