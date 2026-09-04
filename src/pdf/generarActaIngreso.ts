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
import { ActivoDetalleLinea, IngresoCabecera } from '../repositorios/actasRepo';

export function generarActaIngreso(
  cabecera: IngresoCabecera,
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

    dibujarEncabezado(doc, cabecera, 'ACTA DE INGRESO A ALMACEN', `ACTA DE INGRESO No. ${cabecera.consecutivo}`);

    doc.font('Helvetica').fontSize(9);
    doc.text(`Tipo de ingreso: ${cabecera.desc_tipo_movimiento}`);
    doc.text(`Fecha de ingreso: ${fmtFecha(cabecera.fecha_ingreso)}`);
    doc.text(`Documento soporte: ${cabecera.tipo_doc_soporte} ${cabecera.numero_doc_soporte} (${fmtFecha(cabecera.fecha_doc_soporte)})`);
    const proveedor = nombreValido(cabecera.nombre_proveedor);
    if (proveedor) doc.text(`Proveedor: ${proveedor}`);
    doc.moveDown(0.4);
    const entrega = nombreValido(cabecera.nombre_entrega);
    const depEntrega = nombreValido(cabecera.nombre_dep_entrega);
    const recibe = nombreValido(cabecera.nombre_recibe);
    const depRecibe = nombreValido(cabecera.nombre_dep_recibe);
    doc.text(`Entrega: ${entrega ?? '-'}${depEntrega ? ' (' + depEntrega + ')' : ''}`);
    doc.text(`Recibe: ${recibe ?? '-'}${depRecibe ? ' (' + depRecibe + ')' : ''}`);
    if (cabecera.observaciones) doc.text(`Observaciones: ${cabecera.observaciones}`);
    doc.moveDown(0.8);

    dibujarTabla(doc, [
      { titulo: 'Placa', ancho: 45, valor: (f: ActivoDetalleLinea) => String(f.numero_placa) },
      { titulo: 'Descripcion', ancho: 175, valor: (f: ActivoDetalleLinea) => f.descripcion },
      { titulo: 'Marca/Modelo', ancho: 110, valor: (f: ActivoDetalleLinea) => [f.marca, f.modelo].filter(Boolean).join(' / ') || '-' },
      { titulo: 'Serial', ancho: 90, valor: (f: ActivoDetalleLinea) => f.serial ?? '-' },
      { titulo: 'Valor total', ancho: 92, align: 'right', valor: (f: ActivoDetalleLinea) => `$${fmtValor(f.valor_total)}` },
    ], detalle);

    dibujarBloqueFirmas(doc, [
      {
        etiquetaRol: 'Entrega' + (cabecera.es_almacenista_entrega ? ' (almacenista)' : ''),
        nombre: cabecera.nombre_entrega,
        dependencia: cabecera.nombre_dep_entrega,
      },
      {
        etiquetaRol: 'Recibe' + (cabecera.es_almacenista_recibe ? ' (almacenista)' : ''),
        nombre: cabecera.nombre_recibe,
        dependencia: cabecera.nombre_dep_recibe,
      },
    ]);

    dibujarPie(doc, usuarioImprime);
    doc.end();
  });
}
