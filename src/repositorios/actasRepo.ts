// ------------------------------------------------------------
// Acceso a datos de las 4 actas (Ingreso, Traslado, Egreso,
// Depreciacion) via ORDS (modulo 'acf.actas', ver
// migrations/04_ords_actas.sql). Mismo patron que
// formula-engine/src/repositorios/comprobanteRepo.ts: cabecera trae
// un unico registro (se toma items[0]), detalle trae varias filas.
// ------------------------------------------------------------

import { ordsGetCollection } from '../http/ordsClient';

// Campos comunes a toda cabecera de acta (logo + identificacion de
// cliente/entidad, iguales en los 4 tipos).
export interface EntidadInfo {
  cliente_id: number;
  entidad_id: number;
  nombre_cliente: string | null;
  nombre_entidad: string | null;
  // LOGO_ENTIDAD llega como BLOB -> ORDS lo serializa base64 en el JSON.
  logo_entidad: string | null;
  logo_mime_type: string | null;
  logo_filename: string | null;
}

export interface IngresoCabecera extends EntidadInfo {
  id: number;
  consecutivo: number;
  estado: 'ELABORADO' | 'APROBADO' | 'ANULADO';
  fecha_ingreso: string;
  fecha_aprobacion: string | null;
  usuario_aprobacion: string | null;
  fecha_creacion: string | null;
  fecha_modificacion: string | null;
  tipo_doc_soporte: string;
  numero_doc_soporte: string;
  fecha_doc_soporte: string;
  observaciones: string | null;
  desc_tipo_movimiento: string;
  nombre_proveedor: string | null;
  funcionario_entrega_id: number | null;
  nombre_entrega: string | null;
  nombre_dep_entrega: string | null;
  funcionario_recibe_id: number | null;
  nombre_recibe: string | null;
  nombre_dep_recibe: string | null;
}

export interface ActivoDetalleLinea {
  activo_fijo_id: number;
  numero_placa: number;
  descripcion: string;
  marca: string | null;
  referencia: string | null;
  modelo: string | null;
  serial: string | null;
  estado?: string;
  valor: number;
  valor_iva?: number;
  valor_total?: number;
  valor_depreciado?: number;
}

export interface TrasladoCabecera extends EntidadInfo {
  id: number;
  consecutivo: number;
  estado: 'ELABORADO' | 'APROBADO' | 'ANULADO';
  fecha_traslado: string;
  fecha_aprobacion: string | null;
  usuario_aprobacion: string | null;
  fecha_creacion: string | null;
  fecha_modificacion: string | null;
  observaciones: string | null;
  desc_tipo_movimiento: string;
  ubicacion_origen: string;
  funcionario_origen_id: number | null;
  nombre_origen: string | null;
  nombre_dep_origen: string | null;
  ubicacion_destino: string;
  funcionario_destino_id: number | null;
  nombre_destino: string | null;
  nombre_dep_destino: string | null;
  nombre_tercero_comodato: string | null;
}

export interface EgresoCabecera extends EntidadInfo {
  id: number;
  consecutivo: number;
  estado: 'ELABORADO' | 'APROBADO' | 'ANULADO';
  fecha_egreso: string;
  fecha_aprobacion: string | null;
  usuario_aprobacion: string | null;
  fecha_creacion: string | null;
  fecha_modificacion: string | null;
  valor_a_resarcir: number | null;
  observaciones: string | null;
  desc_tipo_movimiento: string;
  responsable_id: number | null;
  nombre_responsable: string | null;
}

export interface DepreciacionCabecera extends EntidadInfo {
  id: number;
  consecutivo: number;
  estado: 'ELABORADO' | 'APROBADO' | 'ANULADO';
  fecha_generacion: string;
  fecha_aprobacion: string | null;
  usuario_aprobacion: string | null;
  fecha_creacion: string | null;
  fecha_modificacion: string | null;
  numero_documento_soporte: string | null;
  fecha_documento_soporte: string | null;
  observaciones: string | null;
  anio: number;
  mes: number;
}

export interface DepreciacionDetalleLinea {
  numero_placa: number;
  descripcion: string;
  vida_util_actual: number;
  dias_depreciados: number;
  vida_util_nueva: number;
  valor_antes_depreciacion: number;
  valor_depreciado: number;
  valor_nuevo_bien: number;
}

export interface Firmante {
  rol: 'CONTADOR' | 'ALMACENISTA';
  cedula: string;
  matricula_profesional: string | null;
  orden_firma: number;
  nombre_firmante: string | null;
}

async function unico<T>(path: string, params: Record<string, string>, contexto: string): Promise<T> {
  const items = await ordsGetCollection<T>(path, params);
  if (items.length === 0) {
    throw new Error(`${contexto}: no se encontro ningun registro para ${JSON.stringify(params)}`);
  }
  return items[0];
}

export async function buscarIngreso(id: string): Promise<{
  cabecera: IngresoCabecera;
  detalle: ActivoDetalleLinea[];
}> {
  const [cabecera, detalle] = await Promise.all([
    unico<IngresoCabecera>('/ingreso-cabecera', { id }, 'Acta de Ingreso'),
    ordsGetCollection<ActivoDetalleLinea>('/ingreso-detalle', { id }),
  ]);
  return { cabecera, detalle };
}

export async function buscarTraslado(id: string): Promise<{
  cabecera: TrasladoCabecera;
  detalle: ActivoDetalleLinea[];
}> {
  const [cabecera, detalle] = await Promise.all([
    unico<TrasladoCabecera>('/traslado-cabecera', { id }, 'Acta de Traslado'),
    ordsGetCollection<ActivoDetalleLinea>('/traslado-detalle', { id }),
  ]);
  return { cabecera, detalle };
}

export async function buscarEgreso(id: string): Promise<{
  cabecera: EgresoCabecera;
  detalle: ActivoDetalleLinea[];
}> {
  const [cabecera, detalle] = await Promise.all([
    unico<EgresoCabecera>('/egreso-cabecera', { id }, 'Acta de Egreso'),
    ordsGetCollection<ActivoDetalleLinea>('/egreso-detalle', { id }),
  ]);
  return { cabecera, detalle };
}

export async function buscarDepreciacion(id: string): Promise<{
  cabecera: DepreciacionCabecera;
  detalle: DepreciacionDetalleLinea[];
  firmantes: Firmante[];
}> {
  const [cabecera, detalle] = await Promise.all([
    unico<DepreciacionCabecera>('/depreciacion-cabecera', { id }, 'Acta de Depreciacion'),
    ordsGetCollection<DepreciacionDetalleLinea>('/depreciacion-detalle', { id }),
  ]);
  const firmantes = await ordsGetCollection<Firmante>('/depreciacion-firmantes', {
    clienteId: String(cabecera.cliente_id),
    entidadId: String(cabecera.entidad_id),
  });
  return { cabecera, detalle, firmantes };
}
