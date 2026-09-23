// ------------------------------------------------------------
// Acceso a datos de las 4 actas de ALM (Ingreso, Egreso, Traslado,
// Devolucion) via ORDS -- MISMO modulo 'acf.actas' que actasRepo.ts
// (ver migrations/04_ords_actas.sql, seccion "ALM INGRESO/EGRESO/
// TRASLADO/DEVOLUCION"), reutilizando el mismo ordsClient/OAuth2 que ya
// usa acf-backend. A diferencia de ACF (activos con placa), el detalle
// de ALM son lineas de catalogo de consumibles (cantidad/unidad, sin
// placa ni serial).
// ------------------------------------------------------------

import { ordsGetCollection } from '../http/ordsClient';
import { EntidadInfo } from './actasRepo';

export interface AlmIngresoCabecera extends EntidadInfo {
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
  es_almacenista_entrega: number;
  funcionario_recibe_id: number | null;
  nombre_recibe: string | null;
  nombre_dep_recibe: string | null;
  es_almacenista_recibe: number;
}

export interface AlmIngresoDetalleLinea {
  detalle_id: number;
  descripcion: string;
  cantidad: number;
  unidad_medida: string;
  valor_unitario: number | null;
  valor_total: number | null;
}

export interface AlmEgresoCabecera extends EntidadInfo {
  id: number;
  consecutivo: number;
  estado: 'ELABORADO' | 'APROBADO' | 'ANULADO';
  fecha_egreso: string;
  fecha_aprobacion: string | null;
  usuario_aprobacion: string | null;
  fecha_creacion: string | null;
  fecha_modificacion: string | null;
  observaciones: string | null;
  desc_tipo_movimiento: string;
  nombre_dep_destino: string | null;
  funcionario_destino_id: number | null;
  nombre_destino: string | null;
  es_almacenista_destino: number;
}

export interface AlmEgresoDetalleLinea {
  detalle_id: number;
  descripcion: string;
  cantidad_solicitada: number;
  cantidad_entregada: number | null;
  unidad_medida: string;
  valor_unitario: number | null;
  valor_total: number | null;
}

export interface AlmTrasladoCabecera extends EntidadInfo {
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
  nombre_dep_origen: string | null;
  nombre_dep_destino: string | null;
}

export interface AlmTrasladoDetalleLinea {
  detalle_id: number;
  descripcion: string;
  cantidad: number;
  unidad_medida: string;
}

export interface AlmDevolucionCabecera extends EntidadInfo {
  id: number;
  consecutivo: number;
  estado: 'ELABORADO' | 'APROBADO' | 'ANULADO';
  fecha_devolucion: string;
  fecha_aprobacion: string | null;
  usuario_aprobacion: string | null;
  fecha_creacion: string | null;
  fecha_modificacion: string | null;
  observaciones: string | null;
  motivo: 'SOBRANTE' | 'DEFECTUOSO' | 'OTRO';
  desc_tipo_movimiento: string;
  nombre_dep_origen: string | null;
}

export interface AlmDevolucionDetalleLinea {
  detalle_id: number;
  descripcion: string;
  cantidad: number;
  unidad_medida: string;
}

async function unico<T>(path: string, params: Record<string, string>, contexto: string): Promise<T> {
  const items = await ordsGetCollection<T>(path, params);
  if (items.length === 0) {
    throw new Error(`${contexto}: no se encontro ningun registro para ${JSON.stringify(params)}`);
  }
  return items[0];
}

export async function buscarAlmIngreso(id: string): Promise<{
  cabecera: AlmIngresoCabecera;
  detalle: AlmIngresoDetalleLinea[];
}> {
  const [cabecera, detalle] = await Promise.all([
    unico<AlmIngresoCabecera>('/alm_ingreso-cabecera', { id }, 'Acta de Ingreso (Almacen)'),
    ordsGetCollection<AlmIngresoDetalleLinea>('/alm_ingreso-detalle', { id }),
  ]);
  return { cabecera, detalle };
}

export async function buscarAlmEgreso(id: string): Promise<{
  cabecera: AlmEgresoCabecera;
  detalle: AlmEgresoDetalleLinea[];
}> {
  const [cabecera, detalle] = await Promise.all([
    unico<AlmEgresoCabecera>('/alm_egreso-cabecera', { id }, 'Acta de Egreso (Almacen)'),
    ordsGetCollection<AlmEgresoDetalleLinea>('/alm_egreso-detalle', { id }),
  ]);
  return { cabecera, detalle };
}

export async function buscarAlmTraslado(id: string): Promise<{
  cabecera: AlmTrasladoCabecera;
  detalle: AlmTrasladoDetalleLinea[];
}> {
  const [cabecera, detalle] = await Promise.all([
    unico<AlmTrasladoCabecera>('/alm_traslado-cabecera', { id }, 'Acta de Traslado (Almacen)'),
    ordsGetCollection<AlmTrasladoDetalleLinea>('/alm_traslado-detalle', { id }),
  ]);
  return { cabecera, detalle };
}

export async function buscarAlmDevolucion(id: string): Promise<{
  cabecera: AlmDevolucionCabecera;
  detalle: AlmDevolucionDetalleLinea[];
}> {
  const [cabecera, detalle] = await Promise.all([
    unico<AlmDevolucionCabecera>('/alm_devolucion-cabecera', { id }, 'Acta de Devolucion (Almacen)'),
    ordsGetCollection<AlmDevolucionDetalleLinea>('/alm_devolucion-detalle', { id }),
  ]);
  return { cabecera, detalle };
}
