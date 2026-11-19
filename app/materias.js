// Materias primas: alta rápida desde la captura y catálogo para revisión del administrador.
import { api } from './api.js';
import { esc, fmt, aviso, cargando, errorEn } from './ui.js';
import { sesion } from './sesion.js';

export const CATEGORIAS = {
  grano: 'Grano', pasta: 'Pasta', ingrediente: 'Ingrediente', nucleo: 'Núcleo', aminoacido: 'Aminoácido',
  mineral: 'Mineral', medicamento: 'Medicamento o aditivo', alimento_comprado: 'Alimento comprado', otro: 'Otro',
};

// Sin acentos, mayúsculas, un solo espacio: para comparar nombres.
export const normalizar = (t) => String(t || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase().replace(/\s+/g, ' ').trim();

// Materias existentes parecidas a lo que se escribe (para no duplicar).
export function parecidas(texto, materias) {
  const t = normalizar(texto);
  if (t.length < 3) return [];
  const palabras = t.split(' ').filter((p) => p.length >= 4 && !['PARA', 'CON'].includes(p));
  return materias.filter((m) => {
    const n = normalizar(m.nombre);
    return n.includes(t) || t.includes(n) || palabras.some((p) => n.includes(p.slice(0, Math.max(4, p.length - 1))));
  }).slice(0, 6);
}

// Mini formulario dentro de otro formulario. `alCrear(materia)` recibe { id, nombre }; `alElegir(id)` si eligen una existente.
export function miniFormularioMateria(caja, materias, grupos, { alCrear, alElegir, alCancelar }) {
  caja.innerHTML = `
    <p><b>Materia prima nueva</b> — quedará por revisar por el administrador.</p>
    <div class="rejilla">
      <label class="ancho2">Nombre<input name="mp_nombre" maxlength="120" autocomplete="off"></label>
      <label>Categoría<select name="mp_categoria">${Object.entries(CATEGORIAS).map(([v, t]) => `<option value="${v}" ${v === 'ingrediente' ? 'selected' : ''}>${t}</option>`).join('')}</select></label>
      <label>Presentación<input name="mp_presentacion" maxlength="60" placeholder="Granel, saco 25 kg…"></label>
      <label class="ancho2">Grupo de almacén (capacidad)<select name="mp_grupo"><option value="">Ninguno (racks)</option>${grupos.map((g) => `<option value="${g.id}">${esc(g.nombre)}</option>`).join('')}</select></label>
    </div>
    <div class="parecidas oculto" id="mp-parecidas"></div>
    <button type="button" class="boton boton-chico boton-primario" id="mp-guardar">Agregar materia prima</button>
    <button type="button" class="boton boton-chico" id="mp-cancelar">Cancelar</button>`;
  const $ = (s) => caja.querySelector(s);
  const nombre = $('[name=mp_nombre]');
  nombre.focus();
  nombre.addEventListener('input', () => {
    const lista = parecidas(nombre.value, materias);
    $('#mp-parecidas').classList.toggle('oculto', !lista.length);
    $('#mp-parecidas').innerHTML = lista.length ? `<span>¿Es alguna de estas? </span>${lista.map((m) => `<button type="button" class="chip" data-elegir="${m.id}">${esc(m.nombre)}</button>`).join('')}` : '';
  });
  $('#mp-parecidas').addEventListener('click', (ev) => {
    const b = ev.target.closest('[data-elegir]');
    if (b) alElegir(Number(b.dataset.elegir));
  });
  $('#mp-cancelar').addEventListener('click', alCancelar);
  // Enter dentro del mini formulario agrega la materia (no envía el formulario de la llegada).
  caja.onkeydown = (ev) => { if (ev.key === 'Enter' && $('#mp-guardar')) { ev.preventDefault(); $('#mp-guardar').click(); } };
  $('#mp-guardar').addEventListener('click', async () => {
    const texto = nombre.value.trim();
    if (!texto) return nombre.focus();
    const exacta = materias.find((m) => normalizar(m.nombre) === normalizar(texto));
    if (exacta) { aviso(`Ya existe: ${exacta.nombre}. Se eligió la existente.`); return alElegir(exacta.id); }
    const boton = $('#mp-guardar');
    boton.disabled = true;
    try {
      const m = await api.crearMateriaPrima({
        nombre: texto, categoria: $('[name=mp_categoria]').value,
        presentacion: $('[name=mp_presentacion]').value.trim(), grupoId: Number($('[name=mp_grupo]').value) || null,
      });
      aviso(`Materia prima ${m.nombre} agregada${sesion.esAdmin() ? '' : ' (queda por revisar)'}.`);
      alCrear(m);
    } catch (e) { aviso(e.message, 'error'); boton.disabled = false; }
  });
}

// ---------- Pestaña Planta → Materias primas ----------

export function seccionMaterias(zona) {
  let vivo = true;
  const admin = sesion.esAdmin();
  zona.innerHTML = `
    <p class="nota">${admin ? 'Revisa las materias primas nuevas que agregan los capturistas: corrige nombre y categoría, pon mínimo y grupo, y márcalas como revisadas.' : 'Catálogo de materias primas. Las correcciones las hace el administrador.'}</p>
    <form class="filtros" id="filtros-mp">
      <label>Mostrar<select name="ver"><option value="todas">Activas</option><option value="revisar">Por revisar</option><option value="inactivas">Inactivas</option></select></label>
      <label>Buscar<input type="search" name="buscar" placeholder="Nombre"></label>
    </form>
    <div id="lista-mp"></div>`;
  const lista = zona.querySelector('#lista-mp');
  const filtros = zona.querySelector('#filtros-mp');
  let materias = [], grupos = [];

  function pintar() {
    const t = normalizar(filtros.buscar.value);
    const ver = filtros.ver.value;
    const filas = materias.filter((m) => (ver === 'inactivas' ? !m.activa : m.activa) && (ver !== 'revisar' || !m.revisada)
      && (!t || normalizar(m.nombre).includes(t)));
    if (!filas.length) { lista.innerHTML = '<p class="vacio">No hay materias primas con ese filtro.</p>'; return; }
    const opGrupo = (sel) => `<option value="">—</option>${grupos.map((g) => `<option value="${g.id}" ${String(sel) === String(g.id) ? 'selected' : ''}>${esc(g.nombre)}</option>`).join('')}`;
    const opCat = (sel) => Object.entries(CATEGORIAS).map(([v, tx]) => `<option value="${v}" ${v === sel ? 'selected' : ''}>${tx}</option>`).join('');
    lista.innerHTML = `<div class="tabla-scroll"><table class="tabla-captura">
      <thead><tr><th>Materia prima</th><th>Categoría</th><th>Presentación</th><th>Grupo de almacén</th><th class="num">Mínimo (kg)</th><th>Contrato</th><th class="num">Existencia</th><th>Estado</th>${admin ? '<th></th>' : ''}</tr></thead>
      <tbody>${filas.map((m) => admin ? `
        <tr data-id="${m.id}" class="${m.revisada ? '' : 'fila-alerta'}">
          <td><input name="nombre" value="${esc(m.nombre)}" maxlength="120" aria-label="Nombre">${m.creada_por ? `<small>Agregó ${esc(m.creada_por)} · ${esc(fmt.hora(m.creada_en))}</small>` : ''}</td>
          <td><select name="categoria" aria-label="Categoría">${opCat(m.categoria)}</select></td>
          <td><input name="presentacion" value="${esc(m.presentacion || '')}" maxlength="60" aria-label="Presentación"></td>
          <td><select name="grupo" aria-label="Grupo de almacén">${opGrupo(m.grupo_almacen_id)}</select></td>
          <td class="num"><input type="number" class="celda-num" name="minimo" min="0" step="1" value="${m.stock_minimo_kg ?? ''}" aria-label="Mínimo"></td>
          <td><label class="casilla"><input type="checkbox" name="contrato" ${m.requiere_contrato ? 'checked' : ''}> Requiere</label></td>
          <td class="num">${fmt.kg(m.existencia_kg)}</td>
          <td>${m.revisada ? (m.activa ? '<span class="etiqueta etiqueta-ok">Revisada</span>' : '<span class="etiqueta etiqueta-gris">Inactiva</span>') : '<span class="etiqueta">Por revisar</span>'}</td>
          <td class="acciones"><button type="button" class="boton boton-chico boton-primario" data-guardar>${m.revisada ? 'Guardar' : 'Guardar y marcar revisada'}</button>
            <button type="button" class="boton boton-chico" data-activa>${m.activa ? 'Desactivar' : 'Activar'}</button></td>
        </tr>` : `
        <tr class="${m.revisada ? '' : 'fila-alerta'}"><td>${esc(m.nombre)}</td><td>${esc(CATEGORIAS[m.categoria] || m.categoria)}</td><td>${esc(m.presentacion || '—')}</td>
          <td>${esc(m.grupo_almacen || '—')}</td><td class="num">${m.stock_minimo_kg == null ? '—' : fmt.kg(m.stock_minimo_kg)}</td>
          <td>${m.requiere_contrato ? 'Sí' : '—'}</td><td class="num">${fmt.kg(m.existencia_kg)}</td>
          <td>${m.revisada ? '' : '<span class="etiqueta">Por revisar</span>'}</td></tr>`).join('')}</tbody>
    </table></div>`;
  }

  lista.addEventListener('click', async (ev) => {
    const tr = ev.target.closest('tr[data-id]');
    if (!tr) return;
    const m = materias.find((x) => String(x.id) === tr.dataset.id);
    const v = (n) => tr.querySelector(`[name=${n}]`);
    let campos = null;
    if (ev.target.closest('[data-guardar]')) {
      const nombre = v('nombre').value.trim().toUpperCase().replace(/\s+/g, ' ');
      if (!nombre) return aviso('El nombre no puede quedar vacío.', 'error');
      const otra = materias.find((x) => x.id !== m.id && normalizar(x.nombre) === normalizar(nombre));
      if (otra) return aviso(`Ya existe otra materia prima llamada ${otra.nombre}.`, 'error');
      campos = {
        nombre, categoria: v('categoria').value, presentacion: v('presentacion').value.trim() || null,
        grupo_almacen_id: Number(v('grupo').value) || null, stock_minimo_kg: v('minimo').value === '' ? null : Number(v('minimo').value),
        requiere_contrato: v('contrato').checked, revisada: true,
      };
    } else if (ev.target.closest('[data-activa]')) {
      campos = { activa: !m.activa, revisada: true };
    }
    if (!campos) return;
    try {
      await api.actualizarMateria(m.id, campos);
      Object.assign(m, campos);
      if ('grupo_almacen_id' in campos) m.grupo_almacen = grupos.find((g) => g.id === campos.grupo_almacen_id)?.nombre || null;
      aviso(`${m.nombre} guardada.`);
      pintar();
    } catch (e) { aviso(e.message, 'error'); }
  });
  filtros.addEventListener('input', pintar);

  cargando(lista);
  (async () => {
    try {
      [materias, grupos] = await Promise.all([api.materiasCatalogo(), api.gruposAlmacen()]);
      if (!vivo) return;
      if (materias.some((m) => !m.revisada)) filtros.ver.value = 'revisar';
      pintar();
    } catch (e) { if (vivo) errorEn(lista, e); }
  })();
  return () => { vivo = false; };
}
