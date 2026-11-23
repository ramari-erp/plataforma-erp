// Llegadas → Nota con varios productos (encostalados): una nota, un renglón por producto.
// Cada producto se guarda como su propia llegada ligada a la nota.
import { api } from './api.js';
import { esc, fmt, hoy, aviso } from './ui.js';
import { miniFormularioMateria } from './materias.js';

const numero = (v) => (v === '' || v == null ? null : Number(v));

export function formularioNota(caja, { materias, provs, grupos, alGuardar }) {
  const NUEVA_MP = '__nueva_mp__';
  caja.innerHTML = `
    <form class="tarjeta formulario" id="form-nota" autocomplete="off">
      <h2>Nota con varios productos</h2>
      <p class="nota">Para entregas encostaladas: una sola nota y una sola pesada. Se usan los kg que dice la nota; cada producto queda como su propia llegada.</p>
      <div class="rejilla">
        <label>Fecha<input type="date" name="fecha" value="${hoy()}" required></label>
        <label class="ancho2">Proveedor<select name="proveedor_id" required><option value="">Elige…</option>${provs.map((p) => `<option value="${p.id}">${esc(p.nombre)}</option>`).join('')}</select></label>
        <label>Folio de la nota / boleta<input name="folio" maxlength="60"><small class="ayuda" id="ayuda-folio-nota"></small></label>
        <label>Factura<input name="factura" maxlength="60"></label>
        <label>Total báscula (kg, opcional)<input type="number" name="kg_bascula" min="0.01" step="0.01" inputmode="decimal"></label>
        <label class="casilla ancho2"><input type="checkbox" name="ajustar"> Ajustar los kg a la báscula (en proporción)</label>
      </div>
      <div class="tabla-scroll"><table class="tabla-captura">
        <thead><tr><th>Producto</th><th class="num">Kg según nota</th><th class="num">Precio $/kg</th><th class="num">Importe</th><th></th></tr></thead>
        <tbody id="renglones-nota"></tbody>
        <tfoot><tr><td><b>Total</b></td><td class="num" id="nota-kg"></td><td></td><td class="num" id="nota-importe"></td><td></td></tr></tfoot>
      </table></div>
      <button type="button" class="boton boton-chico" id="btn-renglon">+ Agregar producto</button>
      <div class="caja caja-info oculto" id="nota-nueva-mp"></div>
      <p class="resumen-captura" id="nota-resumen"></p>
      <label class="casilla"><input type="checkbox" name="precio_provisional"> Precio <b>provisional</b> (aún no se paga; se corrige después)</label>
      <label class="ancho-total">Notas<input name="notas" maxlength="300"></label>
      <button class="boton boton-primario" type="submit">Guardar nota</button>
    </form>`;
  const form = caja.querySelector('#form-nota');
  const cuerpo = form.querySelector('#renglones-nota');
  const opcionesMp = () => `<option value="">Elige…</option>${materias.map((m) => `<option value="${m.id}">${esc(m.nombre)}</option>`).join('')}<option value="${NUEVA_MP}">+ Agregar materia prima nueva…</option>`;
  const renglon = () => `<tr>
      <td><select name="mp" aria-label="Producto">${opcionesMp()}</select></td>
      <td class="num"><input type="number" class="celda-num" name="kg" min="0.01" step="0.01" inputmode="decimal" aria-label="Kg según nota"></td>
      <td class="num"><input type="number" class="celda-num" name="precio" min="0" step="0.0001" inputmode="decimal" aria-label="Precio por kg"></td>
      <td class="num importe">—</td>
      <td><button type="button" class="boton boton-chico" data-quitar-renglon aria-label="Quitar producto">Quitar</button></td>
    </tr>`;
  cuerpo.innerHTML = renglon() + renglon();

  const leer = () => [...cuerpo.querySelectorAll('tr')].map((tr) => ({
    tr, materia_prima_id: numero(tr.querySelector('[name=mp]').value), kg: numero(tr.querySelector('[name=kg]').value),
    precio_kg: numero(tr.querySelector('[name=precio]').value),
  }));
  const actualizar = () => {
    const lineas = leer();
    let kg = 0, importe = 0;
    for (const l of lineas) {
      const imp = (l.kg || 0) * (l.precio_kg || 0);
      l.tr.querySelector('.importe').textContent = l.kg && l.precio_kg != null ? fmt.dinero(imp) : '—';
      kg += l.kg || 0; importe += imp;
    }
    form.querySelector('#nota-kg').textContent = fmt.kg(kg);
    form.querySelector('#nota-importe').textContent = fmt.dinero(importe);
    const bascula = numero(form.kg_bascula.value);
    const dif = bascula && kg ? bascula - kg : null;
    form.querySelector('#nota-resumen').textContent = dif == null ? ''
      : `Báscula ${fmt.kg(bascula)} vs. nota ${fmt.kg(kg)}: diferencia ${dif > 0 ? '+' : ''}${fmt.kg(dif)} (${fmt.pct(100 * dif / kg)}). ${form.ajustar.checked ? 'Los kg de cada producto se ajustarán en proporción.' : 'Se guardarán los kg de la nota.'}`;
  };
  form.addEventListener('input', actualizar);
  form.addEventListener('change', actualizar);

  form.querySelector('#btn-renglon').addEventListener('click', () => {
    cuerpo.insertAdjacentHTML('beforeend', renglon());
    cuerpo.lastElementChild.querySelector('select').focus();
  });
  cuerpo.addEventListener('click', (ev) => {
    if (!ev.target.closest('[data-quitar-renglon]')) return;
    if (cuerpo.children.length > 1) ev.target.closest('tr').remove(); else aviso('La nota necesita al menos un producto.', 'error');
    actualizar();
  });

  // Materia prima nueva desde un renglón
  const cajaMp = form.querySelector('#nota-nueva-mp');
  cuerpo.addEventListener('change', (ev) => {
    const sel = ev.target.closest('[name=mp]');
    if (!sel || sel.value !== NUEVA_MP) return;
    cajaMp.classList.remove('oculto');
    const cerrar = (id) => {
      cajaMp.classList.add('oculto'); cajaMp.innerHTML = '';
      cuerpo.querySelectorAll('[name=mp]').forEach((s) => { const v = s === sel ? (id ? String(id) : '') : s.value; s.innerHTML = opcionesMp(); s.value = v; });
    };
    miniFormularioMateria(cajaMp, materias, grupos, {
      alCrear: (m) => { materias.push(m); materias.sort((a, b) => a.nombre.localeCompare(b.nombre)); cerrar(m.id); },
      alElegir: (id) => cerrar(id),
      alCancelar: () => cerrar(null),
    });
  });

  // Folio repetido
  let folioRepetido = false, espera = null;
  const revisarFolio = async () => {
    const f = form.folio.value.trim();
    folioRepetido = false;
    if (f) {
      try {
        const [porBoleta, porNota] = await Promise.all([api.buscarLlegadaPor('boleta', f), api.buscarLlegadaPor('nota_folio', f)]);
        folioRepetido = f === form.folio.value.trim() && (porBoleta.length + porNota.length) > 0;
      } catch { /* la base de datos lo valida al guardar */ }
    }
    const ayuda = form.querySelector('#ayuda-folio-nota');
    ayuda.textContent = folioRepetido ? 'Este folio ya está registrado. No puede repetirse.' : '';
    ayuda.classList.toggle('ayuda-error', folioRepetido);
  };
  form.folio.addEventListener('input', () => { clearTimeout(espera); espera = setTimeout(revisarFolio, 350); });

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const lineas = leer().filter((l) => l.materia_prima_id || l.kg || l.precio_kg != null);
    if (!lineas.length) return aviso('Captura al menos un producto.', 'error');
    if (lineas.some((l) => !l.materia_prima_id || l.materia_prima_id === NUEVA_MP)) return aviso('Elige el producto de cada renglón.', 'error');
    if (lineas.some((l) => !l.kg)) return aviso('Captura los kg de cada producto.', 'error');
    if (lineas.some((l) => l.precio_kg == null)) return aviso('Captura el precio de cada producto (si no es el definitivo, marca "provisional").', 'error');
    const bascula = numero(form.kg_bascula.value);
    if (form.ajustar.checked && !bascula) return aviso('Para ajustar a la báscula captura el total pesado.', 'error');
    if (form.folio.value.trim()) { await revisarFolio(); if (folioRepetido) return aviso('El folio de la nota ya está registrado.', 'error'); }
    const boton = form.querySelector('button[type=submit]');
    boton.disabled = true;
    try {
      await api.crearNotaEntrada({
        fecha: form.fecha.value, proveedorId: Number(form.proveedor_id.value), folio: form.folio.value.trim() || null,
        factura: form.factura.value.trim() || null, kgBascula: bascula, ajustar: form.ajustar.checked,
        precioProvisional: form.precio_provisional.checked, notas: form.notas.value.trim() || null,
        lineas: lineas.map(({ materia_prima_id, kg, precio_kg }) => ({ materia_prima_id, kg, precio_kg })),
      });
      const kg = lineas.reduce((s, l) => s + l.kg, 0);
      aviso(`Nota guardada: ${lineas.length} productos, ${fmt.kg(form.ajustar.checked ? bascula : kg)}.${form.factura.value.trim() ? '' : ' Queda pendiente la factura.'}`);
      const fecha = form.fecha.value;
      form.reset(); form.fecha.value = fecha;
      cuerpo.innerHTML = renglon() + renglon();
      actualizar();
      alGuardar();
    } catch (e) { aviso(e.message, 'error'); } finally { boton.disabled = false; }
  });
  actualizar();
}
