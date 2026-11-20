// Planta → Contratos: contratos de materia prima, su corte con las llegadas y alertas de cobertura.
import { api } from './api.js';
import { esc, fmt, hoy, aviso, cargando, errorEn } from './ui.js';
import { sesion } from './sesion.js';

const DIAS_COBERTURA_MINIMA = 30;
const DIAS_AVISO_VENCIMIENTO = 7;

export const precioContrato = (c) => (c.moneda === 'USD' ? `${Number(c.precio).toFixed(4)} USD/kg` : fmt.precio(c.precio));

// Avisos para Resumen, Inicio y esta pestaña. Devuelve textos con HTML ya escapado.
export function alertasContratos(cobertura, contratos) {
  const a = [];
  for (const m of cobertura) {
    if (!Number(m.contratos_abiertos)) {
      a.push(`<b>${esc(m.nombre)}</b> sin contrato abierto${m.dias_existencia != null ? ` · existencia para ${m.dias_existencia} días` : ''}.`);
    } else if (m.dias_cobertura != null && Number(m.dias_cobertura) < DIAS_COBERTURA_MINIMA) {
      a.push(`<b>${esc(m.nombre)}</b>: existencia + contratos alcanzan para ${m.dias_cobertura} días (consumo ${fmt.kg(m.consumo_kg_dia)}/día).`);
    }
  }
  for (const c of contratos) {
    if (c.estado !== 'abierto' || Number(c.kg_pendientes) <= 0) continue;
    const nombre = `${esc(c.folio || `#${c.id}`)} (${esc(c.materia_prima)}, ${esc(c.proveedor)})`;
    if (c.estado_actual === 'vencido') a.push(`Contrato ${nombre} vencido el ${fmt.fecha(c.fecha_fin)} con ${fmt.t(c.kg_pendientes)} pendientes.`);
    else if (c.dias_para_vencer != null && Number(c.dias_para_vencer) <= DIAS_AVISO_VENCIMIENTO) {
      a.push(`Contrato ${nombre} vence en ${c.dias_para_vencer} días con ${fmt.t(c.kg_pendientes)} pendientes.`);
    }
  }
  return a;
}

const ESTADOS = {
  abierto: ['Abierto', 'etiqueta-ok'], surtido: ['Surtido', 'etiqueta-extra'], vencido: ['Vencido', 'etiqueta-peligro'],
  cerrado: ['Cerrado', 'etiqueta-gris'], cancelado: ['Cancelado', 'etiqueta-gris'],
};

export function seccionContratos(zona) {
  let vivo = true;
  const puede = sesion.puedeCapturar('planta') || sesion.puedeCapturar('finanzas');
  zona.innerHTML = `
    <div id="alertas-contratos"></div>
    ${puede ? '<div id="zona-contrato"></div>' : ''}
    <h2>Contratos</h2>
    <form class="filtros" id="filtros-contratos">
      <label>Mostrar<select name="ver"><option value="vigentes">Vigentes (abiertos)</option><option value="terminados">Surtidos, cerrados o cancelados</option><option value="todos">Todos</option></select></label>
      <label>Proveedor<select name="proveedor"><option value="">Todos</option></select></label>
      <label>Materia prima<select name="materia"><option value="">Todas</option></select></label>
    </form>
    <p class="nota" id="totales-contratos"></p>
    <div id="lista-contratos"></div>`;
  const lista = zona.querySelector('#lista-contratos');
  const filtros = zona.querySelector('#filtros-contratos');

  async function pintar() {
    try {
      const [todos, cobertura] = await Promise.all([api.contratos(), api.cobertura()]);
      if (!vivo) return;
      // Opciones de los filtros con los proveedores y materias que tienen contratos
      const opciones = (sel, pares, primera) => {
        const antes = sel.value;
        sel.innerHTML = `<option value="">${primera}</option>${[...new Map(pares).entries()].sort((a, b) => a[1].localeCompare(b[1])).map(([id, n]) => `<option value="${id}">${esc(n)}</option>`).join('')}`;
        sel.value = antes;
      };
      opciones(filtros.proveedor, todos.map((c) => [String(c.proveedor_id), c.proveedor]), 'Todos');
      opciones(filtros.materia, todos.map((c) => [String(c.materia_prima_id), c.materia_prima]), 'Todas');
      const ver = filtros.ver.value;
      const contratos = todos.filter((c) =>
        (ver === 'todos' || (ver === 'vigentes' ? c.estado === 'abierto' && c.estado_actual !== 'surtido' : c.estado !== 'abierto' || c.estado_actual === 'surtido'))
        && (!filtros.proveedor.value || String(c.proveedor_id) === filtros.proveedor.value)
        && (!filtros.materia.value || String(c.materia_prima_id) === filtros.materia.value));
      const suma = (k) => contratos.reduce((s, c) => s + Number(c[k] || 0), 0);
      zona.querySelector('#totales-contratos').innerHTML = contratos.length
        ? `${contratos.length} contrato${contratos.length === 1 ? '' : 's'} · contratado <b>${fmt.t(suma('kg_contratados'))}</b> · surtido <b>${fmt.t(suma('kg_surtidos'))}</b> · pendiente <b>${fmt.t(suma('kg_pendientes'))}</b>${suma('kg_excedente') ? ` · excedente ${fmt.t(suma('kg_excedente'))}` : ''}`
        : '';
      const alertas = alertasContratos(cobertura, todos);
      zona.querySelector('#alertas-contratos').innerHTML = `
        <div class="kpis">${cobertura.map((m) => `
          <div class="kpi"><span>${esc(m.nombre)}</span>
            <b>${fmt.t(m.kg_contratados_pendientes)}</b>
            <small>contratado pendiente · ${m.contratos_abiertos} contrato${Number(m.contratos_abiertos) === 1 ? '' : 's'}${m.dias_cobertura != null ? ` · cobertura ${m.dias_cobertura} días` : ''}</small></div>`).join('')}
        </div>
        ${alertas.length ? `<div class="caja caja-alerta">${alertas.map((t) => `<p>${t}</p>`).join('')}</div>` : ''}`;
      tabla(lista, contratos, pintar);
    } catch (e) { if (vivo) errorEn(lista, e); }
  }

  if (puede) {
    (async () => {
      try {
        const [materias, provs] = await Promise.all([api.existencias(), api.proveedores()]);
        if (vivo) formulario(zona.querySelector('#zona-contrato'), materias, provs, pintar);
      } catch (e) { aviso(e.message, 'error'); }
    })();
  }
  filtros.addEventListener('change', pintar);
  cargando(lista);
  pintar();
  const soltar = api.enVivo('contratos_mp', pintar);
  const soltar2 = api.enVivo('llegadas_mp', pintar);
  return () => { vivo = false; soltar(); soltar2(); };
}

function formulario(zona, materias, provs, alGuardar) {
  const NUEVO = '__nuevo__';
  const granos = materias.filter((m) => ['grano', 'pasta'].includes(m.categoria));
  const resto = materias.filter((m) => !['grano', 'pasta'].includes(m.categoria));
  const op = (l) => l.map((m) => `<option value="${m.id}">${esc(m.nombre)}</option>`).join('');
  zona.innerHTML = `
    <details class="tarjeta desplegable" id="det-contrato">
      <summary>Registrar contrato nuevo</summary>
      <form class="formulario" id="form-contrato" autocomplete="off">
        <div class="rejilla">
          <label>Folio / número<input name="folio" maxlength="40"><small class="ayuda" id="ayuda-folio"></small></label>
          <label>Fecha del contrato<input type="date" name="fecha" value="${hoy()}" required></label>
          <label class="ancho2">Proveedor<select name="proveedor_id" required></select></label>
          <label class="ancho2 oculto" id="campo-prov-contrato">Nombre del proveedor nuevo
            <span class="en-linea"><input name="nuevo_proveedor" maxlength="120"><button type="button" class="boton boton-chico" id="btn-prov-contrato">Agregar</button></span></label>
          <label class="ancho2">Materia prima<select name="materia_prima_id" required><option value="">Elige…</option>
            <optgroup label="Granos y pastas">${op(granos)}</optgroup><optgroup label="Otras">${op(resto)}</optgroup></select></label>
          <label>Toneladas contratadas<input type="number" name="toneladas" min="0.001" step="0.001" inputmode="decimal" required></label>
          <label>Moneda<select name="moneda"><option value="MXN">Pesos (MXN)</option><option value="USD">Dólares (USD)</option></select></label>
          <label>Precio por kg<input type="number" name="precio" min="0" step="0.0001" inputmode="decimal" required></label>
          <label>Surtir desde<input type="date" name="fecha_inicio"></label>
          <label>Entregar a más tardar<input type="date" name="fecha_fin"></label>
          <label class="ancho-total">Notas (condiciones, flete, base…)<input name="notas" maxlength="300"></label>
        </div>
        <p class="resumen-captura" id="resumen-contrato"></p>
        <button class="boton boton-primario" type="submit">Guardar contrato</button>
      </form>
    </details>`;
  const form = zona.querySelector('#form-contrato');
  const pintarProvs = (elegido = '') => {
    form.proveedor_id.innerHTML = `<option value="">Elige…</option>${provs.map((p) => `<option value="${p.id}">${esc(p.nombre)}</option>`).join('')}<option value="${NUEVO}">+ Agregar proveedor nuevo…</option>`;
    form.proveedor_id.value = elegido;
  };
  pintarProvs();
  form.proveedor_id.addEventListener('change', () => {
    zona.querySelector('#campo-prov-contrato').classList.toggle('oculto', form.proveedor_id.value !== NUEVO);
  });
  zona.querySelector('#btn-prov-contrato').addEventListener('click', async () => {
    const nombre = form.nuevo_proveedor.value.trim().toUpperCase();
    if (!nombre) return;
    try {
      const p = await api.crearProveedor(nombre);
      provs.push(p); provs.sort((a, b) => a.nombre.localeCompare(b.nombre));
      pintarProvs(String(p.id));
      zona.querySelector('#campo-prov-contrato').classList.add('oculto');
    } catch (e) { aviso(e.message, 'error'); }
  });
  const resumen = () => {
    const t = Number(form.toneladas.value) || 0, p = Number(form.precio.value) || 0;
    form.querySelector('#resumen-contrato').textContent = t && p
      ? `Valor del contrato: ${form.moneda.value === 'USD' ? `${(t * 1000 * p).toLocaleString('es-MX', { maximumFractionDigits: 2 })} USD` : fmt.dinero(t * 1000 * p)}` : '';
  };
  form.addEventListener('input', resumen);

  // Folio repetido: aviso mientras se escribe y bloqueo al guardar.
  let folioRepetido = null, espera = null;
  const ayudaFolio = form.querySelector('#ayuda-folio');
  const revisarFolio = async () => {
    const f = form.folio.value.trim();
    folioRepetido = null;
    if (f) {
      try {
        const r = await api.buscarFolioContrato(f);
        if (r.length && f === form.folio.value.trim()) folioRepetido = r[0];
      } catch { /* la base de datos lo valida al guardar */ }
    }
    ayudaFolio.textContent = folioRepetido ? `Ya existe: ${folioRepetido.folio} (${folioRepetido.materia_prima}, ${folioRepetido.proveedor}). El folio no puede repetirse.` : '';
    ayudaFolio.classList.toggle('ayuda-error', !!folioRepetido);
  };
  form.folio.addEventListener('input', () => { clearTimeout(espera); espera = setTimeout(revisarFolio, 350); });

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    if (form.proveedor_id.value === NUEVO) return aviso('Agrega el proveedor nuevo o elige uno.', 'error');
    await revisarFolio();
    if (folioRepetido) { form.folio.focus(); return aviso(`El folio ${folioRepetido.folio} ya existe. Usa otro folio.`, 'error'); }
    if (form.fecha_inicio.value && form.fecha_fin.value && form.fecha_fin.value < form.fecha_inicio.value) {
      return aviso('La fecha de entrega no puede ser anterior al inicio.', 'error');
    }
    const boton = form.querySelector('button[type=submit]');
    boton.disabled = true;
    try {
      await api.crearContrato({
        folio: form.folio.value.trim() || null,
        fecha: form.fecha.value,
        proveedor_id: Number(form.proveedor_id.value),
        materia_prima_id: Number(form.materia_prima_id.value),
        kg_contratados: Math.round(Number(form.toneladas.value) * 1000 * 100) / 100,
        moneda: form.moneda.value,
        precio: Number(form.precio.value),
        fecha_inicio: form.fecha_inicio.value || null,
        fecha_fin: form.fecha_fin.value || null,
        notas: form.notas.value.trim() || null,
      });
      aviso('Contrato guardado.');
      form.reset(); form.fecha.value = hoy(); resumen();
      zona.querySelector('#det-contrato').open = false;
      alGuardar();
    } catch (e) { aviso(e.message, 'error'); } finally { boton.disabled = false; }
  });
}

function tabla(zona, contratos, alCambiar) {
  if (!contratos.length) { zona.innerHTML = '<p class="vacio">No hay contratos.</p>'; return; }
  const puede = sesion.puedeCapturar('planta') || sesion.puedeCapturar('finanzas');
  zona.innerHTML = `
    <div class="tabla-scroll"><table>
      <thead><tr><th>Contrato</th><th>Materia prima</th><th class="num">Contratado</th><th>Surtido</th><th class="num">Pendiente</th><th class="num">Precio</th><th>Entrega</th><th>Estado</th><th></th></tr></thead>
      <tbody>${contratos.map((c) => {
        const [estado, clase] = ESTADOS[c.estado_actual] || [c.estado_actual, ''];
        const pct = Math.min(100, Number(c.pct_surtido));
        return `<tr>
          <td>${esc(c.folio || `#${c.id}`)}<small>${esc(c.proveedor)} · ${fmt.fecha(c.fecha)}</small></td>
          <td>${esc(c.materia_prima)}</td>
          <td class="num">${fmt.t(c.kg_contratados)}</td>
          <td class="celda-progreso"><div class="barra-cap" role="meter" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${pct}" aria-label="Surtido de ${esc(c.folio || c.id)}"><div style="width:${pct}%"></div></div>
            <small>${fmt.t(c.kg_surtidos)} · ${fmt.pct(c.pct_surtido)} · ${c.llegadas} llegada${Number(c.llegadas) === 1 ? '' : 's'}</small>${Number(c.kg_excedente) > 0 ? `<small class="dif-mas">excedente ${fmt.t(c.kg_excedente)}</small>` : ''}</td>
          <td class="num">${fmt.t(c.kg_pendientes)}</td>
          <td class="num">${precioContrato(c)}</td>
          <td>${c.fecha_fin ? fmt.fecha(c.fecha_fin) : '—'}${c.estado === 'abierto' && c.dias_para_vencer != null && Number(c.kg_pendientes) > 0 ? `<small>${Number(c.dias_para_vencer) >= 0 ? `faltan ${c.dias_para_vencer} días` : `hace ${-c.dias_para_vencer} días`}</small>` : ''}</td>
          <td><span class="etiqueta ${clase}">${estado}</span></td>
          <td class="acciones">
            <button type="button" class="boton boton-chico" data-llegadas="${c.id}" aria-expanded="false">Llegadas</button>
            ${puede && c.estado === 'abierto' ? `<button type="button" class="boton boton-chico" data-cerrar="${c.id}">Cerrar</button>` : ''}
            ${puede && c.estado === 'cerrado' ? `<button type="button" class="boton boton-chico" data-reabrir="${c.id}">Reabrir</button>` : ''}
          </td></tr>`;
      }).join('')}</tbody>
    </table></div>
    <p class="nota">"Cerrar" da por terminado un contrato aunque tenga pendiente (por ejemplo, si el proveedor ya no surtirá el resto).</p>`;

  zona.querySelector('tbody').addEventListener('click', async (ev) => {
    const ver = ev.target.closest('[data-llegadas]');
    const cerrar = ev.target.closest('[data-cerrar]');
    const reabrir = ev.target.closest('[data-reabrir]');
    if (ver) {
      const tr = ver.closest('tr');
      if (tr.nextElementSibling?.classList.contains('detalle')) { tr.nextElementSibling.remove(); ver.setAttribute('aria-expanded', 'false'); return; }
      ver.setAttribute('aria-expanded', 'true');
      tr.insertAdjacentHTML('afterend', '<tr class="detalle"><td colspan="9"><p class="cargando">Cargando…</p></td></tr>');
      const celda = tr.nextElementSibling.firstElementChild;
      try {
        const ll = await api.llegadas({ contrato: ver.dataset.llegadas });
        celda.innerHTML = ll.length ? `<table class="tabla-detalle">
          <thead><tr><th>Fecha</th><th class="num">Kg neto</th><th class="num">Precio</th><th>Factura / boleta</th><th>Capturó</th></tr></thead>
          <tbody>${ll.map((l) => `<tr><td>${fmt.fecha(l.fecha)}</td><td class="num">${fmt.kg(l.kg_neto)}</td>
            <td class="num">${fmt.precio(l.precio_kg)}${l.tipo_cambio ? `<small>TC ${Number(l.tipo_cambio).toFixed(4)}</small>` : ''}</td>
            <td>${esc([l.factura, l.boleta].filter(Boolean).join(' / ') || '—')}</td><td>${esc(l.capturado_por || '—')}</td></tr>`).join('')}</tbody></table>`
          : '<p class="vacio">Este contrato aún no tiene llegadas.</p>';
      } catch (e) { celda.innerHTML = `<span class="caja-error">${esc(e.message)}</span>`; }
    }
    const boton = cerrar || reabrir;
    if (boton) {
      if (cerrar && boton.dataset.confirmar !== 'si') { boton.dataset.confirmar = 'si'; boton.textContent = 'Confirmar cierre'; return; }
      boton.disabled = true;
      try {
        await api.cambiarEstadoContrato(Number(boton.dataset.cerrar || boton.dataset.reabrir), cerrar ? 'cerrado' : 'abierto');
        aviso(cerrar ? 'Contrato cerrado.' : 'Contrato reabierto.');
        alCambiar();
      } catch (e) { aviso(e.message, 'error'); boton.disabled = false; }
    }
  });
}
