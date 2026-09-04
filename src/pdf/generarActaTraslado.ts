import {
  PDFDocument,
  dibujarEncabezado,
  dibujarMarcaDeAgua,
  dibujarBloqueFirmas,
  dibujarPie,
  dibujarTabla,
  fechaDelEstado,
  fmtFecha,
  fmtValor,
  nombreValido,
} from './actaHelpers';
import { ActivoDetalleLinea, TrasladoCabecera } from '../repositorios/actasRepo';

export function generarActaTraslado(
  cabecera: TrasladoCabecera,
  detalle: ActivoDetalleLinea[],
  usuarioImprime: string
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'LETTER', margin: 50 });
    const chunks: Buffer[] = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    dibujarMarcaDeAgua(doc, cabecera.estado, fechaDelEstado(cabecera));

    const tituloActa = `ACTA DE TRASLADO - ${cabecera.desc_tipo_movimiento.toUpperCase()}`;
    dibujarEncabezado(doc, cabecera, tituloActa, `ACTA DE TRASLADO No. ${cabecera.consecutivo}`);

    doc.font('Helvetica').fontSize(9);
    doc.text(`Fecha de traslado: ${fmtFecha(cabecera.fecha_traslado)}`);
    doc.moveDown(0.4);
    const origen = nombreValido(cabecera.nombre_origen);
    const depOrigen = nombreValido(cabecera.nombre_dep_origen);
    const destino = nombreValido(cabecera.nombre_destino);
    const depDestino = nombreValido(cabecera.nombre_dep_destino);
    const comodatario = nombreValido(cabecera.nombre_tercero_comodato);
    doc.text(`Origen (${cabecera.ubicacion_origen}): ${origen ?? '-'}` + (depOrigen ? ` (${depOrigen})` : ''));
    doc.text(`Destino (${cabecera.ubicacion_destino}): ${destino ?? '-'}` + (depDestino ? ` (${depDestino})` : ''));
    if (comodatario) doc.text(`Comodatario: ${comodatario}`);
    if (cabecera.observaciones) doc.text(`Observaciones: ${cabecera.observaciones}`);
    doc.moveDown(0.8);

    dibujarTabla(doc, [
      { titulo: 'Placa', ancho: 45, valor: (f: ActivoDetalleLinea) => String(f.numero_placa) },
      { titulo: 'Descripcion', ancho: 195, valor: (f: ActivoDetalleLinea) => f.descripcion },
      { titulo: 'Marca/Modelo', ancho: 120, valor: (f: ActivoDetalleLinea) => [f.marca, f.modelo].filter(Boolean).join(' / ') || '-' },
      { titulo: 'Serial', ancho: 90, valor: (f: ActivoDetalleLinea) => f.serial ?? '-' },
      { titulo: 'Valor', ancho: 62, align: 'right', valor: (f: ActivoDetalleLinea) => `$${fmtValor(f.valor)}` },
    ], detalle);

    dibujarBloqueFirmas(doc, [
      {
        etiquetaRol: 'Entrega (origen)' + (cabecera.es_almacenista_origen ? ' - Almacenista' : ''),
        nombre: cabecera.nombre_origen,
        dependencia: cabecera.nombre_dep_origen,
      },
      {
        etiquetaRol: 'Recibe (destino)' + (cabecera.es_almacenista_destino ? ' - Almacenista' : ''),
        nombre: cabecera.nombre_destino,
        dependencia: cabecera.nombre_dep_destino,
      },
    ]);

    dibujarPie(doc, usuarioImprime);
    doc.end();
  });
}
