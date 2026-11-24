// Arranque: sesión, menú y navegación entre módulos (#/modulo/seccion).
import { api } from './api.js';
import { esc, aviso } from './ui.js';
import { pantallaPlanta } from './planta.js';
import { pantallaUsuarios } from './usuarios.js';
import { pantallaInicio } from './inicio.js';
import { pantallaGranjas } from './granjas.js';
import { pantallaVentas } from './ventas.js';
import { sesion } from './sesion.js';

// Todos los módulos del plan. `listo` = ya construido; los demás muestran qué vendrá.
const MODULOS = [
  { codigo: 'inicio',   nombre: 'Inicio',              listo: true },
  { codigo: 'planta',   nombre: 'Planta de alimentos', listo: true },
  { codigo: 'granjas',  nombre: 'Granjas y casetas',   listo: true },
  { codigo: 'ventas',   nombre: 'Ventas',              listo: true },
  { codigo: 'compras',  nombre: 'Compras',             fase: 2, contenido: 'Compras y pagos: proveedor, factura, pagado, anticipo y saldo.' },
  { codigo: 'cerdos',   nombre: 'Cerdos',              fase: 3, contenido: 'Resumen del año, sitio 1, sitio 2, sitio 3, reemplazos y gestaciones; inventario por caseta, tolvas y ventas.' },
  { codigo: 'aves',     nombre: 'Aves',                fase: 4, contenido: 'Huevo y kg vendidos, inventario por granja, 5 granjas de postura y 1 de crianza, tolvas con alarma.' },
  { codigo: 'almacen',  nombre: 'Almacén',             fase: 5, contenido: 'Medicamentos, vacunas, uniformes y herramienta; entradas, vales de salida a granja e historial.' },
  { codigo: 'ganado',   nombre: 'Ganado',              fase: 6, contenido: 'Registro y comercial: kg producidos, inventarios y vientres.' },
  { codigo: 'borregos', nombre: 'Borregos',            fase: 6, contenido: 'Kg vendidos, ventas contra costos, animales y kg por granja.' },
  { codigo: 'berries',  nombre: 'Berries',             fase: 6, contenido: 'Kg producidos, clientes, precios y calidades.' },
  { codigo: 'gastos',   nombre: 'Gastos',              fase: 7, contenido: 'Gastos diarios y semanales por concepto: nutrición, herramienta, ferretería…' },
  { codigo: 'nomina',   nombre: 'Nómina y empleados',  fase: 7, contenido: 'Nómina semanal por área y empleados por granja.' },
  { codigo: 'reportes', nombre: 'Reportes',            fase: 8, contenido: 'Reportes semanales: alimento consumido, ventas y gastos por área y granja.' },
  { codigo: 'usuarios', nombre: 'Usuarios',            listo: true, soloAdmin: true },
];

const raiz = document.getElementById('raiz');
let perfil = null;
let limpiarPantalla = null;   // cada pantalla puede devolver una función para soltar suscripciones

function pantallaEntrar(mensaje = '') {
  raiz.innerHTML = `
    <main class="entrar">
      <form class="tarjeta entrar-tarjeta" id="form-entrar">
        <p class="marca">Pecuaria Real Victoria</p>
        <h1>Entrar a la plataforma</h1>
        <label>Correo<input type="email" name="email" autocomplete="username" required></label>
        <label>Contraseña<input type="password" name="password" autocomplete="current-password" required></label>
        <p class="error-form" id="error-entrar">${esc(mensaje)}</p>
        <button class="boton boton-primario" type="submit">Entrar</button>
      </form>
    </main>`;
  const form = document.getElementById('form-entrar');
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const boton = form.querySelector('button');
    boton.disabled = true; boton.textContent = 'Entrando…';
    try {
      await api.entrar(form.email.value.trim(), form.password.value);
      await iniciar();
    } catch (e) {
      document.getElementById('error-entrar').textContent = e.message;
      boton.disabled = false; boton.textContent = 'Entrar';
    }
  });
}

function pantallaSinPerfil() {
  raiz.innerHTML = `
    <main class="entrar">
      <div class="tarjeta entrar-tarjeta">
        <h1>Tu usuario aún no tiene permisos</h1>
        <p>Pide al administrador que te dé de alta en <b>Usuarios</b> con tu correo.</p>
        <button class="boton" id="btn-salir">Salir</button>
      </div>
    </main>`;
  document.getElementById('btn-salir').onclick = () => api.salir().then(() => pantallaEntrar());
}

function pintarMarco() {
  const visibles = MODULOS.filter((m) => !m.soloAdmin || perfil.rol === 'administrador');
  const roles = { administrador: 'Administrador', director: 'Director', capturista: 'Capturista', encargado_granja: 'Encargado de granja', consulta: 'Consulta' };
  raiz.innerHTML = `
    <div class="marco">
      <header class="barra">
        <button class="boton-menu" id="btn-menu" aria-label="Abrir menú" aria-expanded="false">☰</button>
        <span class="barra-titulo">Pecuaria Real Victoria</span>
        <span class="barra-usuario">${esc(perfil.nombre)} · ${esc(roles[perfil.rol] || perfil.rol)}</span>
        <button class="boton boton-chico" id="btn-salir">Salir</button>
      </header>
      <nav class="menu" id="menu" aria-label="Módulos">
        ${visibles.map((m) => `
          <a href="#/${m.codigo}" data-modulo="${m.codigo}" class="${m.listo ? '' : 'pendiente'}">
            ${esc(m.nombre)}${m.listo ? '' : '<small>Próximamente</small>'}
          </a>`).join('')}
      </nav>
      <main class="contenido" id="contenido"></main>
    </div>`;
  document.getElementById('btn-salir').onclick = async () => { await api.salir(); perfil = null; sesion.fijar(null); pantallaEntrar(); };
  const menu = document.getElementById('menu');
  const btnMenu = document.getElementById('btn-menu');
  btnMenu.onclick = () => {
    const abierto = menu.classList.toggle('abierto');
    btnMenu.setAttribute('aria-expanded', String(abierto));
  };
  menu.addEventListener('click', (ev) => {
    if (ev.target.closest('a')) { menu.classList.remove('abierto'); btnMenu.setAttribute('aria-expanded', 'false'); }
  });
}

function navegar() {
  if (!perfil) return;
  const [codigo = 'inicio', seccion] = location.hash.replace(/^#\/?/, '').split('/');
  const mod = MODULOS.find((m) => m.codigo === codigo && (!m.soloAdmin || sesion.esAdmin())) || MODULOS[0];
  document.querySelectorAll('#menu a').forEach((a) => a.classList.toggle('activo', a.dataset.modulo === mod.codigo));
  if (limpiarPantalla) { limpiarPantalla(); limpiarPantalla = null; }
  const cont = document.getElementById('contenido');
  cont.scrollTop = 0;
  document.title = `${mod.nombre} · Pecuaria Real Victoria`;

  if (mod.codigo === 'inicio') limpiarPantalla = pantallaInicio(cont);
  else if (mod.codigo === 'planta') limpiarPantalla = pantallaPlanta(cont, seccion);
  else if (mod.codigo === 'usuarios') limpiarPantalla = pantallaUsuarios(cont);
  else if (mod.codigo === 'granjas') limpiarPantalla = pantallaGranjas(cont, seccion);
  else if (mod.codigo === 'ventas') limpiarPantalla = pantallaVentas(cont, seccion);
  else {
    cont.innerHTML = `
      <h1>${esc(mod.nombre)}</h1>
      <div class="caja caja-info">
        <p><b>Próximamente — fase ${mod.fase} del plan.</b></p>
        <p>${esc(mod.contenido)}</p>
      </div>`;
  }
}

async function iniciar() {
  try {
    const activa = await api.sesion();
    if (!activa) return pantallaEntrar();
    perfil = await api.miPerfil();
    if (!perfil || !perfil.activo) return pantallaSinPerfil();
    sesion.fijar(perfil);
    pintarMarco();
    navegar();
  } catch (e) {
    pantallaEntrar(e.message);
  }
}

window.addEventListener('hashchange', navegar);
window.addEventListener('unhandledrejection', (ev) => aviso(ev.reason?.message || 'Ocurrió un error.', 'error'));
iniciar();
