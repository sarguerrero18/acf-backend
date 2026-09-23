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
import { AlmDevolucionCabecera, AlmDevolucionDetalleLinea } from '../repositorios/almActasRepo';

export function generarActaAlmDevolucion(
  cabecera: AlmDevolucionCabecera,
  detalle: AlmDevolucionDetalleLinea[],
  usuarioImprime: string
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'LETTER', margin: 50 });
    const chunks: Buffer[] = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    dibujarMarcaDeAgua(doc, cabecera.estado, fechaDelEstado(cabecera));

    dibujarEncabezado(doc, cabecera, 'ACTA DE DEVOLUCION A ALMACEN', `ACTA DE DEVOLUCION No. ${cabecera.consecutivo}`);

    doc.font('Helvetica').fontSize(9);
    doc.text(`Tipo de devolucion: ${cabecera.desc_tipo_movimiento}`);
    doc.text(`Fecha de devolucion: ${fmtFecha(cabecera.fecha_devolucion)}`);
    doc.text(`Dependencia que devuelve: ${nombreValido(cabecera.nombre_dep_origen) ?? '-'}`);
    doc.text(`Motivo: ${cabecera.motivo}`);
    if (cabecera.observaciones) doc.text(`Observaciones: ${cabecera.observaciones}`);
    doc.moveDown(0.8);

    dibujarTabla(doc, [
      { titulo: 'Elemento', ancho: 320, valor: (f: AlmDevolucionDetalleLinea) => f.descripcion },
      { titulo: 'Cantidad', ancho: 100, align: 'right', valor: (f: AlmDevolucionDetalleLinea) => String(f.cantidad) },
      { titulo: 'Unidad', ancho: 92, valor: (f: AlmDevolucionDetalleLinea) => f.unidad_medida },
    ], detalle);

    dibujarBloqueFirmas(doc, [
      { etiquetaRol: 'Entrega', nombre: null, dependencia: cabecera.nombre_dep_origen },
      { etiquetaRol: 'Recibe (almacenista)', nombre: null, dependencia: null },
    ]);

    dibujarPie(doc, usuarioImprime);
    doc.end();
  });
}
