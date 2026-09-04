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
} from './actaHelpers';
import { DepreciacionCabecera, DepreciacionDetalleLinea, Firmante } from '../repositorios/actasRepo';

const MESES = [
  '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

const ROL_LABEL: Record<Firmante['rol'], string> = {
  CONTADOR: 'Contador',
  ALMACENISTA: 'Almacenista',
};

export function generarActaDepreciacion(
  cabecera: DepreciacionCabecera,
  detalle: DepreciacionDetalleLinea[],
  firmantes: Firmante[],
  usuarioImprime: string
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'LETTER', margin: 50 });
    const chunks: Buffer[] = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    dibujarMarcaDeAgua(doc, cabecera.estado, fechaDelEstado(cabecera));

    dibujarEncabezado(doc, cabecera, 'ACTA DE DEPRECIACION', `ACTA DE DEPRECIACION No. ${cabecera.consecutivo}`);

    doc.font('Helvetica').fontSize(9);
    doc.text(`Periodo: ${MESES[cabecera.mes]} ${cabecera.anio}`);
    doc.text(`Fecha de generacion: ${fmtFecha(cabecera.fecha_generacion)}`);
    if (cabecera.numero_documento_soporte) {
      doc.text(`Documento soporte: ${cabecera.numero_documento_soporte} (${fmtFecha(cabecera.fecha_documento_soporte)})`);
    }
    if (cabecera.observaciones) doc.text(`Observaciones: ${cabecera.observaciones}`);
    doc.moveDown(0.8);

    dibujarTabla(doc, [
      { titulo: 'Placa', ancho: 40, valor: (f: DepreciacionDetalleLinea) => String(f.numero_placa) },
      { titulo: 'Descripcion', ancho: 140, valor: (f: DepreciacionDetalleLinea) => f.descripcion },
      { titulo: 'V.U. actual', ancho: 55, align: 'right', valor: (f: DepreciacionDetalleLinea) => String(f.vida_util_actual) },
      { titulo: 'V.U. nueva', ancho: 55, align: 'right', valor: (f: DepreciacionDetalleLinea) => String(f.vida_util_nueva) },
      { titulo: 'Valor depreciado', ancho: 105, align: 'right', valor: (f: DepreciacionDetalleLinea) => `$${fmtValor(f.valor_depreciado)}` },
      { titulo: 'Valor nuevo bien', ancho: 117, align: 'right', valor: (f: DepreciacionDetalleLinea) => `$${fmtValor(f.valor_nuevo_bien)}` },
    ], detalle);

    const firmas = firmantes.length > 0
      ? firmantes.map((f) => ({
          etiquetaRol: ROL_LABEL[f.rol],
          nombre: f.nombre_firmante,
          identificacion: f.cedula,
        }))
      : [
          { etiquetaRol: 'Contador', nombre: null },
          { etiquetaRol: 'Almacenista', nombre: null },
        ];

    dibujarBloqueFirmas(doc, firmas);

    dibujarPie(doc, usuarioImprime);
    doc.end();
  });
}
