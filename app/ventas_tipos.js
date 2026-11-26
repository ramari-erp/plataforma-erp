// Ventas: configuración de cada tipo y utilidades compartidas (formulario, historial y cobranza).
import { fmt } from './ui.js';


// calidad: 'catalogo' = lista cerrada; 'libre' = texto con sugerencias; null = sin calidad.
export const TIPOS = {
  huevo:   { nombre: 'Huevo',     unidad: 'Cajas',    area: 'aves',     calidad: 'catalogo', obligaCalidad: true, destino: true, merma: 2, pesadaUnica: true },
  cerdo:   { nombre: 'Cerdo',     unidad: 'Cerdos',   area: 'cerdos',   calidad: 'catalogo', obligaCalidad: true, muertos: true },
  ganado:  { nombre: 'Ganado',    unidad: 'Cabezas',  area: 'ganado',   calidad: 'catalogo', obligaCalidad: true },
  borrego: { nombre: 'Borregos',  unidad: 'Cabezas',  area: 'borregos', calidad: 'libre', obligaCalidad: true },
  berries: { nombre: 'Berries',   unidad: 'Cajas',    area: 'berries',  calidad: 'libre', presentacion: true, mermaRenglon: true,
             precioPor: [['kg', 'Por kg'], ['unidad', 'Por caja']], moneda: true, folioExterno: true, credito: true },
  general: { nombre: 'Generales', unidad: 'Cantidad', area: null,       calidad: null, producto: true,
             precioPor: [['unidad', 'Por unidad'], ['kg', 'Por kg']], moneda: true },
};
export const ESTADOS = ['Aguascalientes', 'Baja California', 'Baja California Sur', 'Campeche', 'Chiapas', 'Chihuahua', 'Ciudad de México', 'Coahuila',
  'Colima', 'Durango', 'Estado de México', 'Guanajuato', 'Guerrero', 'Hidalgo', 'Jalisco', 'Michoacán', 'Morelos', 'Nayarit', 'Nuevo León', 'Oaxaca',
  'Puebla', 'Querétaro', 'Quintana Roo', 'San Luis Potosí', 'Sinaloa', 'Sonora', 'Tabasco', 'Tamaulipas', 'Tlaxcala', 'Veracruz', 'Yucatán', 'Zacatecas'];
export const UNIDADES_PRODUCTO = ['pieza', 'kg', 'tonelada', 'costal', 'caja', 'viaje', 'servicio', 'lote'];
export const AREAS = ['aves', 'cerdos', 'ganado', 'borregos', 'berries', 'planta', 'otro'];
export const numero = (v) => (v === '' || v == null ? null : Number(v));
export const n2 = new Intl.NumberFormat('es-MX', { maximumFractionDigits: 2 });
export const dinero = (v, moneda) => (moneda === 'USD' ? `US$${n2.format(Number(v) || 0)}` : fmt.dinero(v));

