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
import { ComiteBajaCabecera, ComiteBajaDetalleLinea, Firmante } from '../repositorios/actasRepo';

const ROL_LABEL: Record<Firmante['rol'], string> = {
  CONTADOR: 'Contador',
  ALMACENISTA: 'Almacenista',
  OTRO: 'Miembro del comite',
};

export function generarActaComiteBaja(
  cabecera: ComiteBajaCabecera,
  detalle: ComiteBajaDetalleLinea[],
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

    dibujarEncabezado(
      doc,
      cabecera,
      'ACTA DE COMITE DE BAJAS',
      `ACTA No. ${cabecera.numero_acta ?? cabecera.consecutivo} -- VIGENCIA ${cabecera.vigencia}`
    );

    doc.font('Helvetica').fontSize(9);
    doc.text(`Fecha del comite: ${fmtFecha(cabecera.fecha_comite)}`);
    // FECHA_COMITE (el dia real del comite) y FECHA_APROBACION (el
    // tramite administrativo) son campos distintos y pueden no
    // coincidir -- se muestran ambas cuando la aprobacion ya existe.
    if (cabecera.fecha_aprobacion) {
      doc.text(
        `Fecha de aprobacion: ${fmtFecha(cabecera.fecha_aprobacion)}` +
          (cabecera.usuario_aprobacion ? ` (${cabecera.usuario_aprobacion})` : '')
      );
    }
    doc.text(`Consecutivo: ${cabecera.consecutivo}`);
    if (cabecera.observaciones) doc.text(`Observaciones: ${cabecera.observaciones}`);
    doc.moveDown(0.8);

    dibujarTabla(doc, [
      { titulo: 'Placa', ancho: 35, valor: (f: ComiteBajaDetalleLinea) => String(f.numero_placa) },
      { titulo: 'Descripcion', ancho: 95, valor: (f: ComiteBajaDetalleLinea) => f.descripcion },
      { titulo: 'Diagnostico', ancho: 90, valor: (f: ComiteBajaDetalleLinea) => f.diagnostico ?? '-' },
      { titulo: 'Decision', ancho: 55, valor: (f: ComiteBajaDetalleLinea) => f.decision },
      { titulo: 'Tipo egreso sugerido', ancho: 85, valor: (f: ComiteBajaDetalleLinea) => f.tipo_egreso_sugerido ?? '-' },
      { titulo: 'No. Egreso', ancho: 42, align: 'center', valor: (f: ComiteBajaDetalleLinea) => f.numero_egreso != null ? String(f.numero_egreso) : '-' },
      { titulo: 'Observaciones', ancho: 110, valor: (f: ComiteBajaDetalleLinea) => f.observaciones ?? '-' },
    ], detalle);

    const firmas = firmantes.length > 0
      ? firmantes.map((f) => ({
          etiquetaRol: ROL_LABEL[f.rol] ?? f.rol,
          nombre: nombreValido(f.nombre_firmante),
          identificacion: f.cedula,
          matricula: f.matricula_profesional,
        }))
      : [
          { etiquetaRol: 'Almacenista', nombre: null },
          { etiquetaRol: 'Contador', nombre: null },
        ];

    dibujarBloqueFirmas(doc, firmas);

    dibujarPie(doc, usuarioImprime);
    doc.end();
  });
}
