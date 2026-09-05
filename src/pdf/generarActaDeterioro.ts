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
import { DeterioroCabecera, DeterioroDetalleLinea, Firmante } from '../repositorios/actasRepo';

const ROL_LABEL: Record<Firmante['rol'], string> = {
  CONTADOR: 'Contador',
  ALMACENISTA: 'Almacenista',
  // 'OTRO' no deberia salir en la practica (deterioro-firmantes
  // restringe ROL IN ('CONTADOR','ALMACENISTA'), ver *** SUPUESTO A
  // VALIDAR #1 en migrations/04_ords_actas.sql), pero el tipo TS
  // Firmante['rol'] es compartido con Comite de Bajas y hay que
  // cubrir el caso igual para que compile.
  OTRO: 'Miembro del comite',
};

/**
 * Acta de Deterioro -- UNICA de las 6 actas en orientacion horizontal
 * (landscape) con margenes estrechos, a pedido explicito de Sergio:
 * "Como son bastantes campos se debe generar un reporte con
 * orientacion horizontal y con margenes estrechos". Esto es lo que
 * motivo la OCTAVA ADICION en actaHelpers.ts (dibujarEncabezado/
 * dibujarMarcaDeAgua/dibujarBloqueFirmas/dibujarTabla/dibujarPie ya no
 * dependen de las constantes MARGEN/ANCHO_UTIL hardcodeadas para
 * portrait -- leen el margen/ancho util real de `doc.page`), por lo
 * que este generador puede usar esas mismas funciones compartidas sin
 * ningun cambio adicional, solo construyendo el PDFDocument distinto.
 */
export function generarActaDeterioro(
  cabecera: DeterioroCabecera,
  detalle: DeterioroDetalleLinea[],
  firmantes: Firmante[],
  usuarioImprime: string
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: 'LETTER',
      layout: 'landscape',
      margins: { top: 36, bottom: 36, left: 36, right: 36 },
    });
    const chunks: Buffer[] = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    dibujarMarcaDeAgua(doc, cabecera.estado, fechaDelEstado(cabecera));

    dibujarEncabezado(
      doc,
      cabecera,
      'ACTA DE DETERIORO DE ACTIVOS FIJOS',
      `ACTA DE DETERIORO No. ${cabecera.numero_acta ?? cabecera.consecutivo} -- VIGENCIA ${cabecera.vigencia}`
    );

    doc.font('Helvetica').fontSize(9);
    doc.text(`Tipo de movimiento: ${cabecera.desc_tipo_movimiento}`);
    doc.text(`Fecha del deterioro: ${fmtFecha(cabecera.fecha_deterioro)}`);
    const dependencia = nombreValido(cabecera.nombre_dependencia);
    if (dependencia) doc.text(`Dependencia: ${dependencia}`);
    // FECHA_DETERIORO (el dia real de la evaluacion) y FECHA_APROBACION
    // (el tramite administrativo) son campos distintos y pueden no
    // coincidir -- mismo criterio ya usado en Comite de Bajas.
    if (cabecera.fecha_aprobacion) {
      doc.text(
        `Fecha de aprobacion: ${fmtFecha(cabecera.fecha_aprobacion)}` +
          (cabecera.usuario_aprobacion ? ` (${cabecera.usuario_aprobacion})` : '')
      );
    }
    doc.text(`Consecutivo: ${cabecera.consecutivo}`);
    if (cabecera.observaciones) doc.text(`Observaciones: ${cabecera.observaciones}`);
    doc.moveDown(0.8);

    // Anchos pensados para LETTER landscape (792pt) con margen 36 a
    // cada lado -> ancho util = 720pt. Suma de columnas = 720.
    // Campos y orden tal como los priorizo Sergio para el reporte
    // impreso (placa, descripcion, valor en libros, importe
    // recuperable, diagnostico, indicio, aplica deterioro,
    // observaciones) -- la columna Descripcion se agrego a pedido
    // explicito de Sergio (2026-09-05), reduciendo el resto de los
    // anchos para que sigan sumando 720.
    dibujarTabla(doc, [
      { titulo: 'Placa', ancho: 40, valor: (f: DeterioroDetalleLinea) => String(f.numero_placa) },
      { titulo: 'Descripcion', ancho: 110, valor: (f: DeterioroDetalleLinea) => f.descripcion },
      { titulo: 'Valor en libros', ancho: 75, align: 'right', valor: (f: DeterioroDetalleLinea) => `$${fmtValor(f.valor_en_libros)}` },
      { titulo: 'Importe recuperable', ancho: 80, align: 'right', valor: (f: DeterioroDetalleLinea) => `$${fmtValor(f.importe_recuperable)}` },
      { titulo: 'Diagnostico', ancho: 130, valor: (f: DeterioroDetalleLinea) => f.diagnostico ?? '-' },
      { titulo: 'Indicio de deterioro', ancho: 115, valor: (f: DeterioroDetalleLinea) => f.indicio },
      { titulo: 'Aplica deterioro', ancho: 55, align: 'center', valor: (f: DeterioroDetalleLinea) => f.aplica_deterioro === 'S' ? 'Si' : 'No' },
      { titulo: 'Observaciones', ancho: 115, valor: (f: DeterioroDetalleLinea) => f.observaciones ?? '-' },
    ], detalle);

    const firmas = firmantes.length > 0
      ? firmantes.map((f) => ({
          etiquetaRol: ROL_LABEL[f.rol] ?? f.rol,
          nombre: nombreValido(f.nombre_firmante),
          identificacion: f.cedula,
          matricula: f.matricula_profesional,
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
