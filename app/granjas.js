// Granjas y casetas: catálogo de casetas, capacidades y tolvas por granja y área.
import { api } from './api.js';
import { esc, fmt, cargando, errorEn } from './ui.js';

const AREAS = { cerdos: 'Cerdos', aves: 'Aves', ganado: 'Ganado', borregos: 'Borregos', berries: 'Berries' };
const n0 = new Intl.NumberFormat('es-MX', { maximumFractionDigits: 0 });

export function pantallaGranjas(cont, granjaElegida) {
  let vivo = true;
  cont.innerHTML = `
    <h1>Granjas y casetas</h1>
    <p class="nota">Capacidad de cada caseta y sus tolvas. Los datos vienen del archivo de capacidades; para corregirlos, avisa al administrador.</p>
    <div id="resumen-granjas"></div>
    <div id="detalle-granja"></div>`;
  const zona = cont.querySelector('#resumen-granjas');
  cargando(zona);
  (async () => {
    try {
      const [granjas, casetas] = await Promise.all([api.granjas(), api.casetas()]);
      if (!vivo) return;
      const porGranja = new Map(granjas.map((g) => [g.nombre, []]));
      casetas.forEach((c) => porGranja.get(c.granja)?.push(c));
      zona.innerHTML = `<div class="accesos">${granjas.map((g) => {
        const cs = porGranja.get(g.nombre) || [];
        const areas = [...new Set(cs.map((c) => AREAS[c.area] || c.area))];
        const tolvas = cs.reduce((s, c) => s + Number(c.tolvas), 0);
        const ton = cs.reduce((s, c) => s + Number(c.capacidad_tolvas_kg), 0);
        return `<a class="tarjeta acceso ${granjaElegida === String(g.id) ? 'activo' : ''}" href="#/granjas/${g.id}">
          <b>${esc(g.nombre)}${g.activa ? '' : ' <span class="etiqueta etiqueta-gris">En construcción</span>'}</b>
          <span>${cs.length ? `${areas.join(' · ')} · ${cs.length} casetas · ${tolvas} tolvas (${fmt.t(ton)})`
            : g.superficie_ha ? `${esc(g.notas || 'Berries')} · ${n0.format(g.superficie_ha)} hectáreas` : 'Sin casetas capturadas'}</span></a>`;
      }).join('')}</div>`;
      const g = granjas.find((x) => String(x.id) === granjaElegida);
      if (g) detalle(cont.querySelector('#detalle-granja'), g, porGranja.get(g.nombre) || []);
    } catch (e) { if (vivo) errorEn(zona, e); }
  })();
  return () => { vivo = false; };
}

function detalle(zona, granja, casetas) {
  if (!casetas.length) { zona.innerHTML = `<h2>${esc(granja.nombre)}</h2><p class="vacio">Sin casetas capturadas todavía.</p>`; return; }
  const grupos = [];
  for (const c of casetas) {
    const clave = `${c.area}|${c.seccion || ''}`;
    let gr = grupos.find((x) => x.clave === clave);
    if (!gr) grupos.push(gr = { clave, area: c.area, seccion: c.seccion, filas: [] });
    gr.filas.push(c);
  }
  zona.innerHTML = `<h2>${esc(granja.nombre)}</h2>
    <div class="tabla-scroll"><table>
      <thead><tr><th>Caseta</th><th>Uso</th><th class="num">Capacidad</th><th class="num">Tolvas</th><th class="num">Capacidad tolvas</th><th>Notas</th></tr></thead>
      <tbody>${grupos.map((gr) => `
        <tr class="fila-grupo"><td colspan="6">${esc(AREAS[gr.area] || gr.area)}${gr.seccion ? ` · ${esc(gr.seccion)}` : ''}</td></tr>
        ${gr.filas.map((c) => `<tr>
          <td>${esc(c.nombre)}</td><td>${esc(c.uso || '—')}</td>
          <td class="num">${c.capacidad == null ? '—' : `${n0.format(c.capacidad)} ${esc(c.unidad_capacidad)}`}</td>
          <td class="num">${c.tolvas || '—'}</td>
          <td class="num">${Number(c.capacidad_tolvas_kg) ? fmt.t(c.capacidad_tolvas_kg) : '—'}</td>
          <td class="notas-celda">${esc(c.notas || '')}</td></tr>`).join('')}`).join('')}
      </tbody>
    </table></div>`;
}
