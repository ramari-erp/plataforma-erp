// Ventas: historial con filtros, detalle de renglones y accesos a editar y cobrar.
import { api } from './api.js';
import { esc, fmt, errorEn } from './ui.js';
import { sesion } from './sesion.js';
import { irACobrar } from './cobranza.js';
import { TIPOS, n2, dinero } from './ventas_tipos.js';

// ---------- Historial ----------

const totalesPorMoneda = (filas, k) => {
  const m = new Map();
  for (const v of filas) m.set(v.moneda || 'MXN', (m.get(v.moneda || 'MXN') || 0) + Number(v[k] || 0));
  return [...m].filter(([, x]) => x).map(([mon, x]) => dinero(x, mon)).join(' + ') || dinero(0);
};

export async function historial(zona, especie, filtros, sigueVivo, alEditar) {
  const t = TIPOS[especie];
  const conMerma = Boolean(t.merma || t.mermaRenglon);
  try {
    const filas = await api.ventas({ especie, desde: filtros.desde.value, hasta: filtros.hasta.value, cliente: filtros.cliente.value || null, conSaldo: filtros.saldo.checked });
    if (!sigueVivo()) return;
    if (!filas.length) { zona.innerHTML = '<p class="vacio">No hay ventas con ese filtro.</p>'; return; }
    const suma = (k) => filas.reduce((s, v) => s + Number(v[k] || 0), 0);
    const kg = suma('kg_netos');
    const unaMoneda = new Set(filas.map((v) => v.moneda || 'MXN')).size === 1;
    const puede = sesion.puedeCapturar(`ventas_${especie}`);
    const cobra = sesion.puedeCapturar('cobranza');
    const porId = new Map(filas.map((v) => [String(v.id), v]));
    const describe = (v) => (t.producto ? esc(v.productos || '—') : t.presentacion ? esc([v.presentaciones, v.calidades].filter(Boolean).join(' · ') || '—') : esc(v.calidades || '—'));
    zona.innerHTML = `
      <p class="nota">${filas.length} venta${filas.length === 1 ? '' : 's'} · ${n2.format(suma('cantidad'))} ${t.unidad.toLowerCase()}${kg ? ` · ${fmt.kg(kg)}` : ''} · <b>${totalesPorMoneda(filas, 'total')}</b>${unaMoneda && kg ? ` · precio promedio ${dinero(suma('total') / kg, filas[0].moneda)}/kg` : ''}${suma('saldo') ? ` · saldo pendiente <b>${totalesPorMoneda(filas, 'saldo')}</b>` : ''}</p>
      <div class="tabla-scroll"><table>
        <thead><tr><th>Fecha</th><th>Cliente</th><th>${t.producto ? 'Producto' : t.presentacion ? 'Presentación / calidad' : 'Calidad / granja'}</th><th class="num">${t.unidad}</th><th class="num">Kg ${conMerma ? 'netos' : ''}</th><th class="num">Precio prom.</th><th class="num">Total</th><th>Pago</th><th>Capturó</th><th></th></tr></thead>
        <tbody>${filas.map((v) => `
          <tr class="${Number(v.saldo) > 0 ? 'fila-alerta' : ''}">
            <td>${fmt.fecha(v.fecha)}${v.folio ? `<small>Folio ${esc(v.folio)}</small>` : ''}${v.folio_externo ? `<small>Cliente ${esc(v.folio_externo)}</small>` : ''}</td>
            <td>${esc(v.cliente)}<small>${esc([v.rfc, v.destino].filter(Boolean).join(' · '))}</small>${v.aumento_centavos_kg != null ? `<small>Aumento al destino: ${n2.format(v.aumento_centavos_kg)} ¢/kg</small>` : ''}</td>
            <td>${describe(v)}<small>${esc(v.granjas || '')}</small></td>
            <td class="num">${n2.format(v.cantidad)}${v.peso_promedio && !t.producto ? `<small>${n2.format(v.peso_promedio)} kg prom.</small>` : ''}${Number(v.muertos) ? `<small class="dif-menos">${v.muertos} muertos</small>` : ''}</td>
            <td class="num">${Number(v.kg_netos) ? fmt.kg(v.kg_netos) : '—'}${Number(v.merma_kg) ? `<small>brutos ${fmt.kg(v.kg_brutos)} − merma ${fmt.kg(v.merma_kg)}</small>` : ''}</td>
            <td class="num">${v.precio_promedio_kg ? `${dinero(v.precio_promedio_kg, v.moneda)}/kg` : '—'}</td>
            <td class="num">${dinero(v.total, v.moneda)}${Number(v.descuento) ? `<small title="${esc(v.motivo_descuento || '')}">desc. ${dinero(v.descuento, v.moneda)}</small>` : ''}${v.moneda === 'USD' && v.tipo_cambio ? `<small>TC ${n2.format(v.tipo_cambio)}</small>` : ''}</td>
            <td>${v.tipo_pago === 'factura' ? `${Number(v.num_facturas) > 1 ? 'Facturas' : 'Factura'} ${esc(v.factura || '(sin número)')}<small>${esc(Number(v.num_facturas) > 1 ? v.facturas : v.empresa_factura || '')}</small>${v.facturado != null && Math.abs(Number(v.facturado) - Number(v.total)) > 0.5 ? `<small class="dif-menos">facturado ${dinero(v.facturado, v.moneda)}</small>` : ''}` : 'Efectivo'}
              ${v.cuenta ? `<small>Depósito: ${esc(v.cuenta)}</small>` : ''}<small>${v.forma_pago === 'contado' ? 'De contado' : Number(v.saldo) > 0 ? `Saldo ${dinero(v.saldo, v.moneda)}${Number(v.anticipo) + Number(v.pagado) ? ` (pagado ${dinero(Number(v.anticipo) + Number(v.pagado), v.moneda)})` : ''}` : 'Crédito pagado'}</small></td>
            <td>${esc(v.capturado_por || '—')}<small>${esc(fmt.hora(v.capturado_en))}</small>${v.modificado_por ? `<small>Modificó ${esc(v.modificado_por)}</small>` : ''}</td>
            <td class="acciones"><button type="button" class="boton boton-chico" data-ver-venta="${v.id}" aria-expanded="false">Ver</button>${puede ? `<button type="button" class="boton boton-chico" data-editar-venta="${v.id}">Editar</button>` : ''}${cobra && Number(v.saldo) > 0 ? `<button type="button" class="boton boton-chico" data-cobrar="${v.id}">Registrar pago</button>` : ''}</td>
          </tr>`).join('')}</tbody>
      </table></div>`;
    zona.querySelector('tbody').addEventListener('click', async (ev) => {
      const ed = ev.target.closest('[data-editar-venta]');
      if (ed) return alEditar(porId.get(ed.dataset.editarVenta));
      const co = ev.target.closest('[data-cobrar]');
      if (co) { const v = porId.get(co.dataset.cobrar); return irACobrar(v.cliente_id, v.moneda); }
      const ver = ev.target.closest('[data-ver-venta]');
      if (!ver) return;
      const tr = ver.closest('tr');
      if (tr.nextElementSibling?.classList.contains('detalle')) { tr.nextElementSibling.remove(); ver.setAttribute('aria-expanded', 'false'); return; }
      ver.setAttribute('aria-expanded', 'true');
      tr.insertAdjacentHTML('afterend', '<tr class="detalle"><td colspan="10"><p class="cargando">Cargando…</p></td></tr>');
      const celda = tr.nextElementSibling.firstElementChild;
      try {
        const v = porId.get(ver.dataset.verVenta);
        const rs = await api.renglonesVenta(v.id);
        celda.innerHTML = `<table class="tabla-detalle">
          <thead><tr>${t.producto ? '<th>Producto</th>' : ''}<th>Granja</th>${t.presentacion ? '<th>Presentación</th>' : ''}${t.calidad ? '<th>Calidad</th>' : ''}<th class="num">${t.unidad}</th><th class="num">Kg brutos</th>${conMerma ? '<th class="num">Merma</th><th class="num">Kg netos</th>' : ''}<th class="num">Precio</th><th class="num">Importe</th></tr></thead>
          <tbody>${rs.map((r) => `<tr>${t.producto ? `<td>${esc(r.producto || '—')}</td>` : ''}<td>${esc(r.granja || '—')}</td>${t.presentacion ? `<td>${esc(r.presentacion || '—')}</td>` : ''}${t.calidad ? `<td>${esc(r.calidad || '—')}</td>` : ''}
            <td class="num">${n2.format(r.cantidad)}${r.unidad ? ` ${esc(r.unidad)}` : ''}</td><td class="num">${Number(r.kg_brutos) ? fmt.kg(r.kg_brutos) : '—'}${r.peso_promedio && !t.producto ? `<small>${n2.format(r.peso_promedio)} kg prom.</small>` : ''}</td>
            ${conMerma ? `<td class="num">${fmt.kg(r.merma_kg)}</td><td class="num">${fmt.kg(r.kg_netos)}</td>` : ''}
            <td class="num">${dinero(r.precio_total_kg, v.moneda)}/${r.precio_por === 'unidad' ? esc(r.unidad || (t.presentacion ? 'caja' : 'unidad')) : 'kg'}</td><td class="num">${dinero(r.importe, v.moneda)}</td></tr>`).join('')}</tbody>
        </table>${Number(v.pagado) ? `<p class="nota">Pagos aplicados: ${dinero(v.pagado, v.moneda)}${Number(v.anticipo) ? ` · anticipo ${dinero(v.anticipo, v.moneda)}` : ''}. El detalle está en Cobranza y saldos.</p>` : ''}${v.motivo_descuento ? `<p class="nota">Descuento: ${esc(v.motivo_descuento)}</p>` : ''}${v.notas ? `<p class="nota">${esc(v.notas)}</p>` : ''}`;
      } catch (e) { celda.innerHTML = `<span class="caja-error">${esc(e.message)}</span>`; }
    });
  } catch (e) { if (sigueVivo()) errorEn(zona, e); }
}
