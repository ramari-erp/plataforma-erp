// Portada: avisos que necesitan atención en todas las áreas construidas.
import { api } from './api.js';
import { esc, fmt, hoy, cargando, errorEn } from './ui.js';
import { sesion } from './sesion.js';
import { alertasContratos } from './contratos.js';

export function pantallaInicio(cont) {
  let vivo = true;
  cont.innerHTML = `
    <h1>Hola, ${esc(sesion.perfil.nombre)}</h1>
    <h2>Avisos</h2>
    <div id="avisos-inicio"></div>
    <h2>Módulos</h2>
    <div class="accesos">
      <a class="tarjeta acceso" href="#/planta/resumen"><b>Planta de alimentos</b><span>Capacidad, existencias y llegadas de materia prima</span></a>
      ${sesion.puedeCapturar('planta') ? '<a class="tarjeta acceso" href="#/planta/llegadas"><b>Registrar llegada</b><span>Captura una descarga de materia prima</span></a>' : ''}
      ${sesion.esAdmin() ? '<a class="tarjeta acceso" href="#/usuarios"><b>Usuarios</b><span>Altas, roles y permisos</span></a>' : ''}
    </div>`;
  const zona = cont.querySelector('#avisos-inicio');
  cargando(zona);
  (async () => {
    try {
      const [cap, exis, cob, contr, sinPesada, catalogo] = await Promise.all([api.capacidad(), api.existencias(), api.cobertura(), api.contratos({ soloVigentes: true }), api.ordenes({ pendientesPesada: true, hasta: hoy(-1) }), sesion.esAdmin() ? api.materiasCatalogo() : []]);
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
      if (sinPesada.length) avisos.push(`Planta: <b>${sinPesada.length}</b> órdenes de días anteriores sin pesada real. <a href="#/planta/produccion">Capturar</a>`);
      const negativas = exis.filter((x) => Number(x.existencia_kg) < 0).length;
      if (negativas) avisos.push(`Planta: <b>${negativas}</b> materias primas con existencia negativa; falta el inventario de arranque o alguna llegada.`);
      zona.innerHTML = avisos.length
        ? `<ul class="lista-avisos">${avisos.map((a) => `<li>${a}</li>`).join('')}</ul>`
        : '<p class="vacio">Sin avisos por ahora.</p>';
    } catch (e) { if (vivo) errorEn(zona, e); }
  })();
  return () => { vivo = false; };
}
