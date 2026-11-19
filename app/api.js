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
  async granjas() {
    return ok(await sb.from('granjas').select('id,nombre,activa,superficie_ha,notas').order('nombre'));
  },
  async casetas() {
    return ok(await sb.from('v_casetas').select('*').order('granja').order('area').order('orden'));
  },
  async tolvas() {
    return ok(await sb.from('tolvas').select('id,caseta_id,nombre,capacidad_kg,activa').order('nombre'));
  },
  async granjaAreas() {
    return ok(await sb.from('v_granja_areas').select('granja_id,granja,activa,area').order('granja'));
  },
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
  async llegadas({ desde, hasta, materia, contrato } = {}) {
    let q = sb.from('v_llegadas').select('*')
      .order('fecha', { ascending: false }).order('id', { ascending: false }).limit(500);
    if (desde) q = q.gte('fecha', desde);
    if (hasta) q = q.lte('fecha', hasta);
    if (materia) q = q.eq('materia_prima_id', materia);
    if (contrato) q = q.eq('contrato_id', contrato);
    return ok(await q);
  },

  // Contratos
  async contratos({ soloVigentes = false, materia } = {}) {
    let q = sb.from('v_contratos').select('*').order('fecha_fin', { ascending: true, nullsFirst: false }).order('id').limit(500);
    if (soloVigentes) q = q.eq('estado', 'abierto');
    if (materia) q = q.eq('materia_prima_id', materia);
    return ok(await q);
  },
  async crearContrato(datos) {
    return ok(await sb.from('contratos_mp').insert(datos).select('id').single());
  },
  async cambiarEstadoContrato(id, estado) {
    return ok(await sb.from('contratos_mp').update({ estado }).eq('id', id));
  },
  async cobertura() { return ok(await sb.from('v_cobertura_mp').select('*').order('nombre')); },
  async crearLlegada(datos) {
    return ok(await sb.from('llegadas_mp').insert(datos).select('id').single());
  },
  async formulas() {
    return ok(await sb.from('formulas').select('id,nombre,especie').eq('activa', true).order('nombre'));
  },
  async formulaIngredientes(formulaId) {
    return ok(await sb.from('formula_ingredientes')
      .select('materia_prima_id,kg_por_tonelada').eq('formula_id', formulaId));
  },
  // { fecha, formulaId, kg, ingredientes: [{materia_prima_id, kg_por_tonelada}], extras: [{materia_prima_id, cantidad, unidad, nota}], notas, actualizarFormula }
  async guardarOrden(o) {
    return ok(await sb.rpc('guardar_orden', {
      p_fecha: o.fecha, p_formula_id: o.formulaId, p_kg: o.kg,
      p_ingredientes: o.ingredientes, p_extras: o.extras, p_notas: o.notas,
      p_actualizar_formula: !!o.actualizarFormula, p_orden_id: o.ordenId ?? null,
      p_granja_id: o.granjaId ?? null, p_area: o.area || null, p_kg_reales: o.kgReales ?? null,
    }));
  },
  async ordenes({ desde, hasta, granja, area, pendientesPesada } = {}) {
    let q = sb.from('v_ordenes').select('*').order('fecha', { ascending: false }).order('id', { ascending: false }).limit(500);
    if (desde) q = q.gte('fecha', desde);
    if (hasta) q = q.lte('fecha', hasta);
    if (area) q = q.eq('area', area);
    if (pendientesPesada) q = q.eq('pendiente_pesada', true);
    if (granja === 'ninguna') q = q.is('granja_id', null);
    else if (granja) q = q.eq('granja_id', granja);
    return ok(await q);
  },
  async consumosOrden(ordenId) {
    return ok(await sb.from('v_orden_consumos').select('*').eq('orden_id', ordenId).order('es_extra').order('materia_prima'));
  },
  async extrasOrden(ordenId) {
    return ok(await sb.from('orden_extras').select('materia_prima_id,cantidad,unidad,nota').eq('orden_id', ordenId));
  },
  async ingredientesOrden(ordenId) {
    return ok(await sb.from('v_orden_ingredientes').select('materia_prima_id,kg_por_tonelada').eq('orden_id', ordenId));
  },
  async registrarPesada(ordenId, kgReales) {
    return ok(await sb.rpc('registrar_pesada', { p_orden_id: ordenId, p_kg_reales: kgReales }));
  },
  async eliminarOrden(ordenId) {
    return ok(await sb.from('ordenes_produccion').delete().eq('id', ordenId));
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
