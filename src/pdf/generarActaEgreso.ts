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
import { ActivoDetalleLinea, EgresoCabecera } from '../repositorios/actasRepo';

// Unica firma: RESPONSABLE_ID de ACF_EGRESO (confirmado por Sergio --
// no hay pareja entrega/recibe como en Ingreso/Traslado).
export function generarActaEgreso(
  cabecera: EgresoCabecera,
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

    const tituloActa = `ACTA DE EGRESO - ${cabecera.desc_tipo_movimiento.toUpperCase()}`;
    dibujarEncabezado(doc, cabecera, tituloActa, `ACTA DE EGRESO No. ${cabecera.consecutivo}`);

    doc.font('Helvetica').fontSize(9);
    doc.text(`Fecha de egreso: ${fmtFecha(cabecera.fecha_egreso)}`);
    const responsable = nombreValido(cabecera.nombre_responsable);
    if (responsable) doc.text(`Responsable: ${responsable}`);
    if (cabecera.valor_a_resarcir != null) doc.text(`Valor a resarcir: $${fmtValor(cabecera.valor_a_resarcir)}`);
    if (cabecera.observaciones) doc.text(`Observaciones: ${cabecera.observaciones}`);
    doc.moveDown(0.8);

    dibujarTabla(doc, [
      { titulo: 'Placa', ancho: 45, valor: (f: ActivoDetalleLinea) => String(f.numero_placa) },
      { titulo: 'Descripcion', ancho: 195, valor: (f: ActivoDetalleLinea) => f.descripcion },
      { titulo: 'Marca/Modelo', ancho: 120, valor: (f: ActivoDetalleLinea) => [f.marca, f.modelo].filter(Boolean).join(' / ') || '-' },
      { titulo: 'Valor', ancho: 76, align: 'right', valor: (f: ActivoDetalleLinea) => `$${fmtValor(f.valor)}` },
      { titulo: 'Val. Deprec.', ancho: 76, align: 'right', valor: (f: ActivoDetalleLinea) => `$${fmtValor(f.valor_depreciado)}` },
    ], detalle);

    dibujarBloqueFirmas(doc, [
      {
        etiquetaRol: 'Responsable del egreso' + (cabecera.es_almacenista_responsable ? ' (almacenista)' : ''),
        nombre: cabecera.nombre_responsable,
        identificacion: undefined,
      },
    ]);

    dibujarPie(doc, usuarioImprime);
    doc.end();
  });
}
