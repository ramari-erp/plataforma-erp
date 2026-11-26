// Portada: avisos que necesitan atención en todas las áreas construidas.
import { api } from './api.js';
import { esc, fmt, hoy, cargando, errorEn } from './ui.js';
import { sesion, TIPOS_VENTA } from './sesion.js';
import { alertasContratos } from './contratos.js';

const NOMBRES_VENTA = { huevo: 'huevo', cerdo: 'cerdo', ganado: 'ganado', borrego: 'borregos', berries: 'berries', general: 'productos generales' };

export function pantallaInicio(cont) {
  let vivo = true;
  // Avisos: permiso aparte; dentro, cada aviso solo si también puede ver su módulo.
  const verAvisos = sesion.puedeVer('avisos');
  const verPlanta = sesion.puedeVer('planta');
  const tiposVenta = TIPOS_VENTA.filter((t) => sesion.puedeVer(`ventas_${t}`));
  cont.innerHTML = `
    <h1>Hola, ${esc(sesion.perfil.nombre)}</h1>
    ${verAvisos ? '<h2>Avisos</h2><div id="avisos-inicio"></div>' : ''}
    <h2>Módulos</h2>
    <div class="accesos">
      ${verPlanta ? '<a class="tarjeta acceso" href="#/planta/resumen"><b>Planta de alimentos</b><span>Capacidad, existencias y llegadas de materia prima</span></a>' : ''}
      ${sesion.puedeCapturar('planta') ? '<a class="tarjeta acceso" href="#/planta/llegadas"><b>Registrar llegada</b><span>Captura una descarga de materia prima</span></a>' : ''}
      ${tiposVenta.map((t) => `<a class="tarjeta acceso" href="#/ventas/${t}"><b>Ventas de ${NOMBRES_VENTA[t]}</b><span>${sesion.puedeCapturar(`ventas_${t}`) ? 'Registrar y consultar' : 'Consultar'}</span></a>`).join('')}
      ${sesion.puedeVer('cobranza') ? '<a class="tarjeta acceso" href="#/ventas/cobranza"><b>Cobranza y saldos</b><span>Pagos de clientes y depósitos por cuenta</span></a>' : ''}
      ${sesion.esAdmin() ? '<a class="tarjeta acceso" href="#/usuarios"><b>Usuarios</b><span>Altas, roles y permisos</span></a>' : ''}
    </div>`;
  const zona = cont.querySelector('#avisos-inicio');
  if (!verAvisos) return () => { vivo = false; };
  cargando(zona);
  (async () => {
    try {
      const P = (cond, f) => (cond ? f().catch(() => []) : Promise.resolve([]));
      const [cap, exis, cob, contr, sinPesada, catalogo, catFormulas, llegPend, saldos] = await Promise.all([P(verPlanta, api.capacidad), P(verPlanta, api.existencias), P(verPlanta, api.cobertura), P(verPlanta, () => api.contratos({ soloVigentes: true })), P(verPlanta, () => api.ordenes({ pendientesPesada: true, hasta: hoy(-1) })), P(sesion.esAdmin(), api.materiasCatalogo), P(sesion.esAdmin(), api.formulasCatalogo), P(verPlanta, () => api.llegadas({ pendientes: true, desde: hoy(-90) })), P(sesion.puedeVer('cobranza'), api.saldosClientes)]);
      if (!vivo) return;
      const avisos = [
        ...cap.filter((g) => Number(g.ocupacion_pct) >= 90)
          .map((g) => `Planta: <b>${esc(g.nombre)}</b> al ${fmt.pct(g.ocupacion_pct)} de su capacidad (libre ${fmt.t(g.espacio_libre_kg)}).`),
        ...exis.filter((x) => x.bajo_minimo && Number(x.existencia_kg) >= 0)
          .map((x) => `Planta: <b>${esc(x.nombre)}</b> bajo el mínimo (${fmt.kg(x.existencia_kg)}).`),
      ];
      avisos.push(...alertasContratos(cob, contr).map((t) => `Contratos: ${t}`));
      const porRevisar = catalogo.filter((m) => !m.revisada).length;
      if (porRevisar) avisos.push(`Planta: <b>${porRevisar}</b> materia${porRevisar > 1 ? 's' : ''} prima${porRevisar > 1 ? 's' : ''} nueva${porRevisar > 1 ? 's' : ''} por revisar. <a href="#/planta/materias">Revisar</a>`);
      const formulasRevisar = catFormulas.filter((f) => !f.revisada).length;
      if (formulasRevisar) avisos.push(`Planta: <b>${formulasRevisar}</b> fórmula${formulasRevisar > 1 ? 's' : ''} nueva${formulasRevisar > 1 ? 's' : ''} por revisar. <a href="#/planta/formulas">Revisar</a>`);
      if (llegPend.length) avisos.push(`Planta: <b>${llegPend.length}</b> llegada${llegPend.length > 1 ? 's' : ''} con información pendiente (factura o precio provisional). <a href="#/planta/llegadas/pendientes">Completar</a>`);
      if (sinPesada.length) avisos.push(`Planta: <b>${sinPesada.length}</b> órdenes de días anteriores sin pesada real. <a href="#/planta/produccion">Capturar</a>`);
      const vencidos = saldos.filter((s) => Number(s.saldo) > 0 && s.venta_mas_antigua && s.venta_mas_antigua < hoy(-30));
      if (vencidos.length) avisos.push(`Ventas: <b>${vencidos.length}</b> cliente${vencidos.length > 1 ? 's' : ''} con saldo de ventas de hace más de 30 días (${vencidos.slice(0, 3).map((s) => esc(s.cliente)).join(', ')}${vencidos.length > 3 ? '…' : ''}). <a href="#/ventas/cobranza">Ver cobranza</a>`);
      const negativas = exis.filter((x) => Number(x.existencia_kg) < 0).length;
      if (negativas) avisos.push(`Planta: <b>${negativas}</b> materias primas con existencia negativa; falta el inventario de arranque o alguna llegada.`);
      zona.innerHTML = avisos.length
        ? `<ul class="lista-avisos">${avisos.map((a) => `<li>${a}</li>`).join('')}</ul>`
        : '<p class="vacio">Sin avisos por ahora.</p>';
    } catch (e) { if (vivo) errorEn(zona, e); }
  })();
  return () => { vivo = false; };
}
