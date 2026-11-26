// Usuario que está dentro y lo que puede ver y capturar.
// perfil.modulos = permisos para ver; perfil.captura = permisos para capturar (capturar incluye ver).
let perfil = null;

export const TIPOS_VENTA = ['huevo', 'cerdo', 'ganado', 'borrego', 'berries', 'general'];

export const sesion = {
  get perfil() { return perfil; },
  fijar(p) { perfil = p; },
  esAdmin() { return perfil?.rol === 'administrador'; },
  puedeVer(modulo) {
    if (perfil && !('captura' in perfil)) return true;   // base sin la migración 0026: todos veían todo
    return !!perfil && (['administrador', 'director'].includes(perfil.rol) || (perfil.modulos || []).includes(modulo));
  },
  puedeCapturar(modulo) {
    if (!perfil) return false;
    if (perfil.rol === 'administrador') return true;
    if (!('captura' in perfil)) {   // base sin la migración 0026: la lista era de captura y 'ventas' cubría todo
      const m = /^ventas_|^cobranza$/.test(modulo) ? 'ventas' : modulo;
      return (perfil.modulos || []).includes(m);
    }
    return (perfil.captura || []).includes(modulo);
  },
  // Ventas: algún tipo de venta o cobranza.
  veVentas() { return TIPOS_VENTA.some((t) => this.puedeVer(`ventas_${t}`)) || this.puedeVer('cobranza') || this.puedeVer('ventas'); },
};
