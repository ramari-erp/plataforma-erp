// Ventas: huevo, cerdo, ganado, borregos, berries y generales (abono, gallina a rastro, productos extraordinarios).
// Cada venta = encabezado + renglones. Cobranza (pagos y saldos de clientes) en cobranza.js.
import { api } from './api.js';
import { esc, hoy, aviso, cargando } from './ui.js';
import { sesion } from './sesion.js';
import { normalizar } from './materias.js';
import { pantallaCobranza } from './cobranza.js';
import { TIPOS } from './ventas_tipos.js';
import { formulario } from './ventas_formulario.js';
import { historial } from './ventas_historial.js';

export { dinero } from './ventas_tipos.js';

export function pantallaVentas(cont, seccion) {
  // Solo las pestañas que el usuario tiene permiso de ver.
  const permitidas = [...Object.keys(TIPOS).filter((k) => sesion.puedeVer(`ventas_${k}`)), ...(sesion.puedeVer('cobranza') ? ['cobranza'] : [])];
  if (!permitidas.includes(seccion)) seccion = permitidas[0];
  if (!seccion) { cont.innerHTML = '<h1>Ventas</h1><div class="caja caja-info">No tienes permiso para ver ventas. Pídelo al administrador.</div>'; return () => {}; }
  const pestanas = permitidas.length > 1 ? `<nav class="pestanas" aria-label="Tipo de venta">
      ${permitidas.map((k) => `<a href="#/ventas/${k}" class="${k === seccion ? 'activo' : ''}">${k === 'cobranza' ? 'Cobranza y saldos' : TIPOS[k].nombre}</a>`).join('')}
    </nav>` : '';
  if (seccion === 'cobranza') return pantallaCobranza(cont, pestanas);
  const especie = seccion;
  const t = TIPOS[especie];
  let vivo = true;
  const puede = sesion.puedeCapturar(`ventas_${especie}`);
  cont.innerHTML = `
    <h1>Ventas</h1>
    ${pestanas}
    ${especie === 'general' ? '<p class="nota">Abono, gallina de desecho a rastro y cualquier otro producto que se venda. Si el producto no está en la lista, agrégalo desde el renglón.</p>' : ''}
    ${puede ? '<div id="zona-venta"></div>' : '<div class="caja caja-info">Puedes consultar las ventas. Para capturarlas pide el permiso al administrador.</div>'}
    <h2>Historial de ventas ${especie === 'general' ? 'generales' : `de ${t.nombre.toLowerCase()}`}</h2>
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
  const pintar = () => historial(hist, especie, filtros, () => vivo, (v) => editor?.editar(v));

  (async () => {
    try {
      const [clientes, empresas, calidades, granjas, granjaAreas, previas, presentaciones, productos, cuentas] = await Promise.all([
        api.clientes(), api.empresasFactura(), api.calidadesVenta(especie), api.granjas(), api.granjaAreas(),
        api.ventas({ especie, desde: hoy(-365) }),
        t.presentacion ? api.presentacionesVenta(especie) : [], t.producto ? api.productosVenta() : [], api.cuentasBancarias().catch(() => []),
      ]);
      if (!vivo) return;
      filtros.cliente.insertAdjacentHTML('beforeend', clientes.map((c) => `<option value="${c.id}">${esc(c.nombre)}</option>`).join(''));
      if (puede) {
        const ids = new Set(granjaAreas.filter((x) => x.area === t.area).map((x) => x.granja_id));
        const granjasArea = granjas.filter((g) => ids.has(g.id) && g.activa);
        // Calidades y presentaciones libres: sugerencias del catálogo más las ya usadas.
        const separar = (k) => previas.flatMap((v) => (v[k] || '').split(', ').filter(Boolean));
        const sugCalidad = [...new Set([...calidades.map((c) => c.nombre), ...separar('calidades')])];
        const nombresPres = new Set(presentaciones.map((p) => p.nombre));
        const sugPres = [...presentaciones, ...[...new Set(separar('presentaciones'))].filter((p) => !nombresPres.has(p)).map((nombre) => ({ nombre }))];
        // Destinos ya usados (previas viene de la más reciente a la más vieja): ciudad + estado → último aumento.
        const destinos = new Map();
        for (const v of previas) {
          if (!v.destino_ciudad) continue;
          const k = normalizar(`${v.destino_ciudad}|${v.destino_estado || ''}`);
          if (!destinos.has(k)) destinos.set(k, { ciudad: v.destino_ciudad, estado: v.destino_estado, aumento: v.aumento_centavos_kg, colonias: new Set() });
          if (v.destino_colonia) destinos.get(k).colonias.add(v.destino_colonia);
        }
        editor = formulario(cont.querySelector('#zona-venta'), especie, {
          clientes, destinos, cuentas, empresas, calidades: calidades.map((c) => c.nombre), sugCalidad, presentaciones: sugPres, productos,
          granjas: granjasArea.length ? granjasArea : granjas.filter((g) => g.activa),
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

