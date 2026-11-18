// Utilidades de interfaz: formato de números y fechas, avisos.

const num = (d) => new Intl.NumberFormat('es-MX', { minimumFractionDigits: d, maximumFractionDigits: d });
const n0 = num(0), n1 = num(1), n2 = num(2);

export function esc(v) {
  return String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

export const fmt = {
  kg: (v) => `${n0.format(Number(v) || 0)} kg`,
  // Toneladas con un decimal; para cantidades grandes de planta.
  t: (kg) => `${n1.format((Number(kg) || 0) / 1000)} t`,
  dinero: (v) => `$${n2.format(Number(v) || 0)}`,
  precio: (v) => `$${n2.format(Number(v) || 0)}/kg`,
  pct: (v) => (v == null ? '—' : `${n1.format(v)} %`),
  fecha: (iso) => {
    if (!iso) return '';
    const [a, m, d] = String(iso).slice(0, 10).split('-');
    const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return `${Number(d)} ${meses.at(Number(m) - 1)} ${a}`;
  },
  hora: (ts) => (ts ? new Date(ts).toLocaleString('es-MX', { dateStyle: 'short', timeStyle: 'short' }) : ''),
};

// Fecha local de hoy en formato AAAA-MM-DD (no UTC: en México la noche ya es "mañana" en UTC).
export function hoy(desplazamientoDias = 0) {
  const d = new Date();
  d.setDate(d.getDate() + desplazamientoDias);
  const p = (x) => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export function aviso(texto, tipo = 'ok') {
  const zona = document.getElementById('avisos');
  const div = document.createElement('div');
  div.className = `aviso aviso-${tipo}`;
  div.setAttribute('role', tipo === 'error' ? 'alert' : 'status');
  div.textContent = texto;
  zona.append(div);
  setTimeout(() => div.remove(), tipo === 'error' ? 7000 : 4000);
}

export function cargando(contenedor, texto = 'Cargando…') {
  contenedor.innerHTML = `<p class="cargando">${esc(texto)}</p>`;
}

export function errorEn(contenedor, e) {
  contenedor.innerHTML = `<div class="caja caja-error">No se pudo cargar: ${esc(e.message)}</div>`;
}
