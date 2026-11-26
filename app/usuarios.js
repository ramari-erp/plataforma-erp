// Administración de usuarios: nombre, rol y, por cada módulo, si no lo ve, solo lo ve o también captura.
import { api } from './api.js';
import { esc, aviso, cargando, errorEn } from './ui.js';

const ROLES = [
  ['capturista', 'Capturista'],
  ['encargado_granja', 'Encargado de granja'],
  ['director', 'Director'],
  ['consulta', 'Solo consulta'],
  ['administrador', 'Administrador (todo)'],
];

export function pantallaUsuarios(cont) {
  let vivo = true;
  let modulos = [];
  cont.innerHTML = `
    <h1>Usuarios</h1>
    <div class="caja caja-info">
      <p><b>Cómo dar de alta a alguien:</b></p>
      <ol>
        <li>En Supabase → Authentication → Users → <i>Add user</i>, crea su correo y contraseña y marca <i>Auto Confirm User</i>.</li>
        <li>Aquí, escribe el mismo correo, su nombre, su rol y sus permisos.</li>
      </ol>
      <p>Cada quien ve <b>solo</b> lo que le autorices aquí: <b>Ver</b> = consulta; <b>Ver y capturar</b> = también registra y corrige.
        El <b>administrador</b> ve y captura todo; el <b>director</b> ve todo y captura solo lo que le marques.
        Los avisos de Inicio son un permiso aparte y solo muestran los de los módulos que la persona puede ver.</p>
    </div>
    <form class="tarjeta formulario" id="form-usuario">
      <h2>Alta o cambio</h2>
      <div class="rejilla">
        <label class="ancho2">Correo<input type="email" name="email" required></label>
        <label class="ancho2">Nombre<input name="nombre" required maxlength="80"></label>
        <label>Rol<select name="rol">${ROLES.map(([v, t]) => `<option value="${v}">${t}</option>`).join('')}</select></label>
        <label class="casilla"><input type="checkbox" name="activo" checked> Activo</label>
        <fieldset class="ancho-total"><legend>Permisos</legend><p class="nota" id="nota-rol"></p><div id="casillas-modulos" class="permisos"></div></fieldset>
      </div>
      <button class="boton boton-primario" type="submit">Guardar usuario</button>
    </form>
    <h2>Usuarios registrados</h2>
    <div id="lista-usuarios"></div>`;

  const form = cont.querySelector('#form-usuario');
  const notaRol = () => {
    const rol = form.rol.value;
    form.querySelector('#nota-rol').textContent = rol === 'administrador' ? 'El administrador ve y captura todo; estos permisos no aplican.'
      : rol === 'director' ? 'El director ve todo. Marca "Ver y capturar" solo donde también registre.' : '';
    form.querySelectorAll('[data-permiso]').forEach((x) => { x.disabled = rol === 'administrador'; });
  };
  form.rol.addEventListener('change', notaRol);
  const lista = cont.querySelector('#lista-usuarios');
  let usuarios = [];

  async function pintarLista() {
    try {
      usuarios = await api.usuarios();
      if (!vivo) return;
      const nombreMod = Object.fromEntries(modulos.map((m) => [m.codigo, m.nombre]));
      const nombreRol = Object.fromEntries(ROLES);
      lista.innerHTML = `
        <div class="tabla-scroll"><table>
          <thead><tr><th>Nombre</th><th>Correo</th><th>Rol</th><th>Permisos</th><th>Estado</th><th></th></tr></thead>
          <tbody>${usuarios.map((u, i) => `
            <tr>
              <td>${esc(u.nombre)}</td><td>${esc(u.email)}</td><td>${esc(nombreRol[u.rol] || u.rol)}</td>
              <td>${u.rol === 'administrador' ? 'Todo' : resumenPermisos(u, nombreMod)}</td>
              <td>${u.activo ? 'Activo' : 'Inactivo'}</td>
              <td><button class="boton boton-chico" data-editar="${i}">Editar</button></td>
            </tr>`).join('')}
          </tbody>
        </table></div>`;
    } catch (e) { if (vivo) errorEn(lista, e); }
  }

  lista.addEventListener('click', (ev) => {
    const b = ev.target.closest('[data-editar]');
    if (!b) return;
    const u = usuarios[Number(b.dataset.editar)];
    form.email.value = u.email;
    form.nombre.value = u.nombre;
    form.rol.value = u.rol;
    form.activo.checked = u.activo;
    form.querySelectorAll('[data-permiso]').forEach((sel) => {
      const m = sel.dataset.permiso;
      sel.value = (u.captura || []).includes(m) ? 'capturar' : (u.modulos || []).includes(m) ? 'ver' : '';
    });
    notaRol();
    form.scrollIntoView({ behavior: 'smooth' });
  });

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const boton = form.querySelector('button[type=submit]');
    boton.disabled = true;
    try {
      await api.guardarUsuario({
        email: form.email.value.trim(),
        nombre: form.nombre.value.trim(),
        rol: form.rol.value,
        activo: form.activo.checked,
        ver: [...form.querySelectorAll('[data-permiso]')].filter((x) => x.value).map((x) => x.dataset.permiso),
        capturar: [...form.querySelectorAll('[data-permiso]')].filter((x) => x.value === 'capturar').map((x) => x.dataset.permiso),
      });
      aviso(`Usuario ${form.nombre.value.trim()} guardado.`);
      form.reset();
      form.activo.checked = true;
      notaRol();
      pintarLista();
    } catch (e) {
      aviso(e.message, 'error');
    } finally {
      boton.disabled = false;
    }
  });

  cargando(lista);
  (async () => {
    try {
      modulos = await api.modulos();
      if (!vivo) return;
      const grupos = [...new Set(modulos.map((m) => m.grupo || 'Otros'))];
      cont.querySelector('#casillas-modulos').innerHTML = grupos.map((g) => `
        <div class="grupo-permisos"><b>${esc(g)}</b>
          ${modulos.filter((m) => (m.grupo || 'Otros') === g).map((m) => `
            <label class="permiso">${esc(m.nombre)}
              <select data-permiso="${esc(m.codigo)}" aria-label="${esc(m.nombre)}">
                <option value="">Sin acceso</option><option value="ver">Ver</option><option value="capturar">Ver y capturar</option>
              </select></label>`).join('')}
        </div>`).join('');
      notaRol();
      pintarLista();
    } catch (e) { errorEn(lista, e); }
  })();
  return () => { vivo = false; };
}

function resumenPermisos(u, nombreMod) {
  const cap = new Set(u.captura || []);
  const items = (u.modulos || []).map((m) => `${esc(nombreMod[m] || m)}${cap.has(m) ? ' <small class="chip">captura</small>' : ''}`);
  return (u.rol === 'director' ? 'Ve todo' + (items.length ? '; ' : '') : '') + (items.join(', ') || (u.rol === 'director' ? '' : '—'));
}
