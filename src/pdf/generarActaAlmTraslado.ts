import {
  PDFDocument,
  dibujarEncabezado,
  dibujarMarcaDeAgua,
  dibujarBloqueFirmas,
  dibujarPie,
  dibujarTabla,
  fechaDelEstado,
  fmtFecha,
  nombreValido,
} from './actaHelpers';
import { AlmTrasladoCabecera, AlmTrasladoDetalleLinea } from '../repositorios/almActasRepo';

export function generarActaAlmTraslado(
  cabecera: AlmTrasladoCabecera,
  detalle: AlmTrasladoDetalleLinea[],
  usuarioImprime: string
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'LETTER', margin: 50 });
    const chunks: Buffer[] = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    dibujarMarcaDeAgua(doc, cabecera.estado, fechaDelEstado(cabecera));

    dibujarEncabezado(doc, cabecera, 'ACTA DE TRASLADO DE ALMACEN', `ACTA DE TRASLADO No. ${cabecera.consecutivo}`);

    doc.font('Helvetica').fontSize(9);
    doc.text(`Tipo de traslado: ${cabecera.desc_tipo_movimiento}`);
    doc.text(`Fecha de traslado: ${fmtFecha(cabecera.fecha_traslado)}`);
    doc.text(`Dependencia origen: ${nombreValido(cabecera.nombre_dep_origen) ?? '-'}`);
    doc.text(`Dependencia destino: ${nombreValido(cabecera.nombre_dep_destino) ?? '-'}`);
    if (cabecera.observaciones) doc.text(`Observaciones: ${cabecera.observaciones}`);
    doc.moveDown(0.8);

    dibujarTabla(doc, [
      { titulo: 'Elemento', ancho: 320, valor: (f: AlmTrasladoDetalleLinea) => f.descripcion },
      { titulo: 'Cantidad', ancho: 100, align: 'right', valor: (f: AlmTrasladoDetalleLinea) => String(f.cantidad) },
      { titulo: 'Unidad', ancho: 92, valor: (f: AlmTrasladoDetalleLinea) => f.unidad_medida },
    ], detalle);

    dibujarBloqueFirmas(doc, [
      { etiquetaRol: 'Entrega', nombre: null, dependencia: cabecera.nombre_dep_origen },
      { etiquetaRol: 'Recibe', nombre: null, dependencia: cabecera.nombre_dep_destino },
    ]);

    dibujarPie(doc, usuarioImprime);
    doc.end();
  });
}
