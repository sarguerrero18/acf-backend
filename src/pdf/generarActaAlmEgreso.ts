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
import { AlmEgresoCabecera, AlmEgresoDetalleLinea } from '../repositorios/almActasRepo';

export function generarActaAlmEgreso(
  cabecera: AlmEgresoCabecera,
  detalle: AlmEgresoDetalleLinea[],
  usuarioImprime: string
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'LETTER', margin: 50 });
    const chunks: Buffer[] = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    dibujarMarcaDeAgua(doc, cabecera.estado, fechaDelEstado(cabecera));

    dibujarEncabezado(doc, cabecera, 'ACTA DE EGRESO DE ALMACEN', `ACTA DE EGRESO No. ${cabecera.consecutivo}`);

    doc.font('Helvetica').fontSize(9);
    doc.text(`Tipo de egreso: ${cabecera.desc_tipo_movimiento}`);
    doc.text(`Fecha de egreso: ${fmtFecha(cabecera.fecha_egreso)}`);
    const depDestino = nombreValido(cabecera.nombre_dep_destino);
    if (depDestino) doc.text(`Dependencia destino: ${depDestino}`);
    const destino = nombreValido(cabecera.nombre_destino);
    if (destino) doc.text(`Recibe: ${destino}${cabecera.es_almacenista_destino ? ' (almacenista)' : ''}`);
    if (cabecera.observaciones) doc.text(`Observaciones: ${cabecera.observaciones}`);
    doc.moveDown(0.8);

    dibujarTabla(doc, [
      { titulo: 'Elemento', ancho: 190, valor: (f: AlmEgresoDetalleLinea) => f.descripcion },
      { titulo: 'Cant. solicitada', ancho: 68, align: 'right', valor: (f: AlmEgresoDetalleLinea) => String(f.cantidad_solicitada) },
      { titulo: 'Cant. entregada', ancho: 68, align: 'right', valor: (f: AlmEgresoDetalleLinea) => f.cantidad_entregada != null ? String(f.cantidad_entregada) : '-' },
      { titulo: 'Unidad', ancho: 50, valor: (f: AlmEgresoDetalleLinea) => f.unidad_medida },
      { titulo: 'Valor unitario', ancho: 68, align: 'right', valor: (f: AlmEgresoDetalleLinea) => `$${fmtValor(f.valor_unitario)}` },
      { titulo: 'Valor total', ancho: 68, align: 'right', valor: (f: AlmEgresoDetalleLinea) => `$${fmtValor(f.valor_total)}` },
    ], detalle);

    dibujarBloqueFirmas(doc, [
      {
        etiquetaRol: 'Entrega (almacenista)',
        nombre: null,
        dependencia: null,
      },
      {
        etiquetaRol: 'Recibe' + (cabecera.es_almacenista_destino ? ' (almacenista)' : ''),
        nombre: cabecera.nombre_destino,
        dependencia: cabecera.nombre_dep_destino,
      },
    ]);

    dibujarPie(doc, usuarioImprime);
    doc.end();
  });
}
