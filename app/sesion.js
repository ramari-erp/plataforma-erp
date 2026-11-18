// Usuario que está dentro y lo que puede hacer.
let perfil = null;

export const sesion = {
  get perfil() { return perfil; },
  fijar(p) { perfil = p; },
  esAdmin() { return perfil?.rol === 'administrador'; },
  puedeCapturar(modulo) {
    return !!perfil && (perfil.rol === 'administrador' || (perfil.modulos || []).includes(modulo));
  },
};
