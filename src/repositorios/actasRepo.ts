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
  // ORDS serializa CASE WHEN ... THEN 1 ELSE 0 END como numero (0/1),
  // no como boolean JSON -- se usa directo en condicionales (0 es
  // falsy, 1 es truthy en JS/TS). Ver migrations/04_ords_actas.sql,
  // QUINTA CORRECCION.
  es_almacenista_entrega: number;
  funcionario_recibe_id: number | null;
  nombre_recibe: string | null;
  nombre_dep_recibe: string | null;
  es_almacenista_recibe: number;
}

export interface ActivoDetalleLinea {
  activo_fijo_id: number;
  // Nullable porque ingreso-detalle puede traer filas de
  // ACF_DETALLE_INGRESO (ingreso en ELABORADO, activo fijo real
  // todavia no creado) donde NUMERO_PLACA aun no esta asignado. En
  // Traslado/Egreso siempre viene poblado (solo se puede mover/dar de
  // baja un activo que YA existe con placa real).
  numero_placa: number | null;
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
  es_almacenista_origen: number;
  ubicacion_destino: string;
  funcionario_destino_id: number | null;
  nombre_destino: string | null;
  nombre_dep_destino: string | null;
  es_almacenista_destino: number;
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
  es_almacenista_responsable: number;
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
  // 'OTRO' se agrego para comite-firmantes -- el check constraint de
  // ACF_FIRMANTE.ROL permite CONTADOR/ALMACENISTA/OTRO, y a diferencia
  // de Depreciacion, el comite de bajas no restringe por rol.
  rol: 'CONTADOR' | 'ALMACENISTA' | 'OTRO';
  cedula: string;
  matricula_profesional: string | null;
  orden_firma: number;
  nombre_firmante: string | null;
}

export interface ComiteBajaCabecera extends EntidadInfo {
  id: number;
  vigencia: number;
  consecutivo: number;
  numero_acta: string | null;
  fecha_comite: string;
  // ACF_COMITE_BAJA.ESTADO solo permite ELABORADO/APROBADO (sin
  // ANULADO, a diferencia de las otras 4 actas) -- DDL real confirmada
  // por Sergio.
  estado: 'ELABORADO' | 'APROBADO';
  observaciones: string | null;
  // Agregadas por Sergio al DDL original de ACF_COMITE_BAJA (que no
  // las traia) -- FECHA_COMITE es el dia real del comite,
  // FECHA_APROBACION es el tramite administrativo y puede ser
  // posterior (validado en PR_APROBAR_COMITE_BAJA, no aca). El acta
  // muestra ambas fechas por separado.
  fecha_aprobacion: string | null;
  usuario_aprobacion: string | null;
  fecha_creacion: string | null;
  fecha_modificacion: string | null;
}

export interface ComiteBajaDetalleLinea {
  numero_placa: number;
  descripcion: string;
  diagnostico: string | null;
  decision: 'PENDIENTE' | 'APROBADO' | 'RECHAZADO' | 'APLAZADO' | 'ANULADO';
  tipo_egreso_sugerido: string | null;
  numero_egreso: number | null;
  observaciones: string | null;
}

export interface DeterioroCabecera extends EntidadInfo {
  id: number;
  vigencia: number;
  consecutivo: number;
  numero_acta: string;
  fecha_deterioro: string;
  // ACF_DETERIORO.ESTADO solo permite ELABORADO/APROBADO (sin ANULADO,
  // igual patron que Comite de Bajas) -- DDL real confirmada por Sergio.
  estado: 'ELABORADO' | 'APROBADO';
  observaciones: string | null;
  fecha_aprobacion: string | null;
  usuario_aprobacion: string | null;
  fecha_creacion: string | null;
  fecha_modificacion: string | null;
  desc_tipo_movimiento: string;
  nombre_dependencia: string | null;
}

export interface DeterioroDetalleLinea {
  numero_placa: number;
  // Sergio pidio agregar la descripcion del activo (igual que las
  // otras 5 actas) -- ya no falta, deterioro-detalle la trae via JOIN
  // a ACF_CATALOGO.
  descripcion: string;
  // Campos priorizados por Sergio para el reporte impreso -- el modelo
  // de datos de ACF_DETALLE_DETERIORO tiene mas columnas (precio
  // estimado de venta, costo directo de venta, valor neto razonable,
  // valor en uso) que NO se muestran en el acta, solo se usan para
  // calcular estas.
  valor_en_libros: number;
  importe_recuperable: number;
  diagnostico: string | null;
  indicio: string;
  aplica_deterioro: 'S' | 'N';
  observaciones: string | null;
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

export async function buscarComiteBaja(id: string): Promise<{
  cabecera: ComiteBajaCabecera;
  detalle: ComiteBajaDetalleLinea[];
  firmantes: Firmante[];
}> {
  const [cabecera, detalle] = await Promise.all([
    unico<ComiteBajaCabecera>('/comite-cabecera', { id }, 'Acta de Comite de Bajas'),
    ordsGetCollection<ComiteBajaDetalleLinea>('/comite-detalle', { id }),
  ]);
  const firmantes = await ordsGetCollection<Firmante>('/comite-firmantes', {
    clienteId: String(cabecera.cliente_id),
    entidadId: String(cabecera.entidad_id),
  });
  return { cabecera, detalle, firmantes };
}

export async function buscarDeterioro(id: string): Promise<{
  cabecera: DeterioroCabecera;
  detalle: DeterioroDetalleLinea[];
  firmantes: Firmante[];
}> {
  const [cabecera, detalle] = await Promise.all([
    unico<DeterioroCabecera>('/deterioro-cabecera', { id }, 'Acta de Deterioro'),
    ordsGetCollection<DeterioroDetalleLinea>('/deterioro-detalle', { id }),
  ]);
  const firmantes = await ordsGetCollection<Firmante>('/deterioro-firmantes', {
    clienteId: String(cabecera.cliente_id),
    entidadId: String(cabecera.entidad_id),
  });
  return { cabecera, detalle, firmantes };
}
