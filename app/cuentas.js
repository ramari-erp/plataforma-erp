// Selector de cuenta de depósito (bancos y caja) con alta en línea de una cuenta nueva.
// Lo usan Ventas (cobro de contado / anticipo) y Cobranza (pagos de clientes).
import { api } from './api.js';
import { esc, aviso } from './ui.js';
import { normalizar } from './materias.js';

const NUEVA = '__nueva__';

// cont: elemento donde se pinta. cuentas: lista compartida (se le agregan las nuevas). empresas: razones sociales.
export function selectorCuenta(cont, cuentas, empresas, { etiqueta = 'Se depositó en', alCambiar = () => {} } = {}) {
  cont.innerHTML = `
    <label>${esc(etiqueta)}<select name="cuenta_id"></select><small class="ayuda">Cuenta de banco o caja que recibió el dinero</small></label>
    <div class="caja caja-info oculto margen-arriba nueva-cuenta">
      <div class="rejilla">
        <label class="ancho2">Nombre de la cuenta<input name="nb_nombre" maxlength="60" placeholder="Ej. BBVA PECUARIA 1234"></label>
        <label>Banco<input name="nb_banco" maxlength="40"></label>
        <label>Terminación o CLABE<input name="nb_numero" maxlength="20"></label>
        <label>Razón social<select name="nb_empresa"><option value="">—</option>${empresas.map((e) => `<option value="${e.id}">${esc(e.nombre)}</option>`).join('')}</select></label>
        <label>Moneda<select name="nb_moneda"><option value="MXN">Pesos</option><option value="USD">Dólares</option></select></label>
        <div class="en-linea"><button type="button" class="boton boton-chico boton-primario" data-nb-guardar>Agregar cuenta</button>
          <button type="button" class="boton boton-chico" data-nb-cancelar>Cancelar</button></div>
      </div>
    </div>`;
  const sel = cont.querySelector('[name=cuenta_id]');
  const caja = cont.querySelector('.nueva-cuenta');
  const q = (n) => cont.querySelector(`[name=${n}]`);
  const pintar = (valor = '') => {
    sel.innerHTML = `<option value="">Sin indicar</option>${cuentas.filter((c) => c.activa !== false).map((c) => `<option value="${c.id}">${esc(c.nombre)}${c.moneda === 'USD' ? ' (USD)' : ''}</option>`).join('')}<option value="${NUEVA}">+ Cuenta nueva…</option>`;
    sel.value = String(valor ?? '');
  };
  sel.addEventListener('change', () => {
    const nueva = sel.value === NUEVA;
    caja.classList.toggle('oculto', !nueva);
    if (nueva) q('nb_nombre').focus(); else alCambiar();
  });
  cont.querySelector('[data-nb-cancelar]').addEventListener('click', () => { caja.classList.add('oculto'); pintar(''); });
  cont.querySelector('[data-nb-guardar]').addEventListener('click', async () => {
    const nombre = q('nb_nombre').value.trim().toUpperCase().replace(/\s+/g, ' ');
    if (!nombre) return q('nb_nombre').focus();
    const existe = cuentas.find((c) => normalizar(c.nombre) === normalizar(nombre));
    if (existe) { aviso(`Ya existe: ${existe.nombre}.`); caja.classList.add('oculto'); return pintar(existe.id); }
    try {
      const c = await api.crearCuentaBancaria({ nombre, banco: q('nb_banco').value.trim(), numero: q('nb_numero').value.trim(),
        empresa_factura_id: q('nb_empresa').value || null, moneda: q('nb_moneda').value });
      cuentas.push(c); cuentas.sort((a, b) => a.nombre.localeCompare(b.nombre));
      caja.classList.add('oculto');
      ['nb_nombre', 'nb_banco', 'nb_numero'].forEach((n) => { q(n).value = ''; });
      pintar(c.id); alCambiar();
      aviso(`Cuenta ${c.nombre} agregada.`);
    } catch (e) { aviso(e.message, 'error'); }
  });
  q('nb_nombre').addEventListener('keydown', (ev) => { if (ev.key === 'Enter') { ev.preventDefault(); cont.querySelector('[data-nb-guardar]').click(); } });
  pintar();
  return {
    valor: () => (sel.value === NUEVA ? '' : sel.value),
    fijar: (id) => { caja.classList.add('oculto'); pintar(id ?? ''); },
  };
}
