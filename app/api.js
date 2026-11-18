// Única puerta a la base de datos. Las pantallas solo usan `api`.
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.110.1/+esm';
import { SUPABASE_URL, SUPABASE_KEY } from './config.js';

const sb = createClient(SUPABASE_URL, SUPABASE_KEY);

function traducir(error) {
  const m = `${error.message || ''} ${error.code || ''}`;
  if (/Invalid login credentials/i.test(m)) return 'Correo o contraseña incorrectos.';
  if (/Email not confirmed/i.test(m)) return 'El correo no está confirmado. Pide al administrador que lo confirme en Supabase.';
  if (/row-level security|42501/i.test(m)) return 'No tienes permiso para capturar en este módulo.';
  if (/duplicate key|23505/i.test(m)) return 'Ese registro ya existe.';
  if (/check constraint|23514/i.test(m)) return 'Hay un dato fuera de rango (revisa kilos y precio).';
  if (/Failed to fetch|NetworkError/i.test(m)) return 'Sin conexión a internet. Intenta de nuevo.';
  return error.message || 'Ocurrió un error.';
}

function ok({ data, error }) {
  if (error) throw new Error(traducir(error));
  return data;
}

export const api = {
  // Sesión
  async sesion() { return (await sb.auth.getSession()).data.session; },
  async entrar(email, password) { return ok(await sb.auth.signInWithPassword({ email, password })); },
  async salir() { await sb.auth.signOut(); },
  alCambiarSesion(cb) { sb.auth.onAuthStateChange((_evento, sesion) => cb(sesion)); },
  async miPerfil() { return (ok(await sb.rpc('mi_perfil')) || [])[0] || null; },

  // Catálogos
  async modulos() { return ok(await sb.from('modulos').select('codigo,nombre,orden').order('orden')); },
  async materias() {
    return ok(await sb.from('materias_primas').select('id,nombre,categoria').eq('activa', true).order('nombre'));
  },
  async proveedores() {
    return ok(await sb.from('proveedores').select('id,nombre').eq('activo', true).order('nombre'));
  },
  async crearProveedor(nombre) {
    return ok(await sb.from('proveedores').insert({ nombre }).select('id,nombre').single());
  },

  // Planta
  async capacidad() { return ok(await sb.from('v_capacidad_planta').select('*').order('orden')); },
  async existencias() { return ok(await sb.from('v_existencias_mp').select('*').order('nombre')); },
  async llegadas({ desde, hasta, materia } = {}) {
    let q = sb.from('v_llegadas').select('*')
      .order('fecha', { ascending: false }).order('id', { ascending: false }).limit(500);
    if (desde) q = q.gte('fecha', desde);
    if (hasta) q = q.lte('fecha', hasta);
    if (materia) q = q.eq('materia_prima_id', materia);
    return ok(await q);
  },
  async crearLlegada(datos) {
    return ok(await sb.from('llegadas_mp').insert(datos).select('id').single());
  },
  async inventarioInicial() {
    return ok(await sb.from('inventario_inicial').select('materia_prima_id,fecha,kg,costo_kg'));
  },
  // items: [{ materia_prima_id, kg, costo_kg }]
  async guardarInventarioInicial(fecha, items) {
    return ok(await sb.rpc('guardar_inventario_inicial', { p_fecha: fecha, p_items: items }));
  },
  // items: [{ materia_prima_id, kg_fisicos }] → devuelve [{ materia, kg_sistema, kg_fisicos, diferencia }]
  async registrarConteo(fecha, items) {
    return ok(await sb.rpc('registrar_conteo', { p_fecha: fecha, p_items: items }));
  },
  async conteos({ desde } = {}) {
    let q = sb.from('v_conteos').select('*').order('fecha', { ascending: false }).order('materia_prima').limit(500);
    if (desde) q = q.gte('fecha', desde);
    return ok(await q);
  },

  // Usuarios (solo administrador)
  async usuarios() { return ok(await sb.rpc('listar_usuarios')); },
  async guardarUsuario({ email, nombre, rol, modulos, activo }) {
    return ok(await sb.rpc('guardar_perfil', {
      p_email: email, p_nombre: nombre, p_rol: rol, p_modulos: modulos, p_activo: activo,
    }));
  },

  // Actualización en vivo: llama a `cb` cuando cambia la tabla. Devuelve la función para dejar de escuchar.
  enVivo(tabla, cb) {
    const canal = sb.channel(`vivo-${tabla}-${Date.now()}-${Math.random().toString(36).slice(2)}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: tabla }, cb)
      .subscribe();
    return () => sb.removeChannel(canal);
  },
};
