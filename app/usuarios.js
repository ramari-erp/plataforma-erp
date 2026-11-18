// Administración de usuarios: nombre, rol y módulos que puede capturar.
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
        <li>Aquí, escribe el mismo correo, su nombre, su rol y los módulos que puede capturar.</li>
      </ol>
      <p>Todos los usuarios activos pueden <b>ver</b> toda la información; los módulos marcados son los que pueden <b>capturar</b>.</p>
    </div>
    <form class="tarjeta formulario" id="form-usuario">
      <h2>Alta o cambio</h2>
      <div class="rejilla">
        <label class="ancho2">Correo<input type="email" name="email" required></label>
        <label class="ancho2">Nombre<input name="nombre" required maxlength="80"></label>
        <label>Rol<select name="rol">${ROLES.map(([v, t]) => `<option value="${v}">${t}</option>`).join('')}</select></label>
        <label class="casilla"><input type="checkbox" name="activo" checked> Activo</label>
        <fieldset class="ancho-total"><legend>Puede capturar en</legend><div id="casillas-modulos" class="casillas"></div></fieldset>
      </div>
      <button class="boton boton-primario" type="submit">Guardar usuario</button>
    </form>
    <h2>Usuarios registrados</h2>
    <div id="lista-usuarios"></div>`;

  const form = cont.querySelector('#form-usuario');
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
          <thead><tr><th>Nombre</th><th>Correo</th><th>Rol</th><th>Captura en</th><th>Estado</th><th></th></tr></thead>
          <tbody>${usuarios.map((u, i) => `
            <tr>
              <td>${esc(u.nombre)}</td><td>${esc(u.email)}</td><td>${esc(nombreRol[u.rol] || u.rol)}</td>
              <td>${u.rol === 'administrador' ? 'Todo' : esc((u.modulos || []).map((m) => nombreMod[m] || m).join(', ') || '—')}</td>
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
    form.querySelectorAll('[name=modulo]').forEach((c) => { c.checked = (u.modulos || []).includes(c.value); });
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
        modulos: [...form.querySelectorAll('[name=modulo]:checked')].map((c) => c.value),
      });
      aviso(`Usuario ${form.nombre.value.trim()} guardado.`);
      form.reset();
      form.activo.checked = true;
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
      cont.querySelector('#casillas-modulos').innerHTML = modulos.map((m) => `
        <label class="casilla"><input type="checkbox" name="modulo" value="${esc(m.codigo)}"> ${esc(m.nombre)}</label>`).join('');
      pintarLista();
    } catch (e) { errorEn(lista, e); }
  })();
  return () => { vivo = false; };
}
