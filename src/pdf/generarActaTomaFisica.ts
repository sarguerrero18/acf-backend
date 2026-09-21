import {
  PDFDocument,
  dibujarEncabezado,
  dibujarMarcaDeAgua,
  dibujarBloqueFirmas,
  dibujarPie,
  dibujarTabla,
  fmtFecha,
  nombreValido,
} from './actaHelpers';
import { TomaFisicaCabecera, TomaFisicaDetalleLinea } from '../repositorios/actasRepo';

const ALCANCE_LABEL: Record<TomaFisicaCabecera['alcance_tipo'], string> = {
  TODA_ENTIDAD: 'Toda la entidad',
  DEPENDENCIA: 'Dependencia',
  BODEGA: 'Bodega',
};

const RESULTADO_LABEL: Record<TomaFisicaDetalleLinea['resultado'], string> = {
  ENCONTRADO_UBICACION_ESPERADA: 'Encontrado (ubic. esperada)',
  ENCONTRADO_OTRA_UBICACION: 'Encontrado (otra ubicacion)',
  NO_ENCONTRADO: 'No encontrado',
  ENCONTRADO_NOVEDAD_ESTADO: 'Encontrado (novedad estado)',
};

/**
 * Toma Fisica NO tiene el ciclo ELABORADO/APROBADO/ANULADO de las
 * demas actas (ACF_TF.ESTADO solo admite EN_PROCESO/CERRADA, ver
 * header VERSION 90 de PKG_ACF -- no genera contabilizacion) -- la
 * fechaDelEstado() compartida de actaHelpers.ts no cubre este caso
 * (solo conoce APROBADO/ANULADO/default-a-creacion), asi que se
 * resuelve aca mismo en vez de tocar el helper compartido por las
 * otras 6 actas.
 */
function fechaDelEstadoTF(cab: TomaFisicaCabecera): string {
  if (cab.estado === 'CERRADA' && cab.fecha_cierre) return fmtFecha(cab.fecha_cierre);
  return fmtFecha(cab.fecha_creacion);
}

/**
 * Informe de Toma Fisica -- orientacion horizontal (landscape) con
 * margenes estrechos, mismo criterio que el acta de Deterioro (Sergio,
 * 2026-09-21: "puedes usar de ejemplo el reporte de deterioro ya que
 * se debe configurar de tal forma que salga de forma horizontal") --
 * el detalle tiene 10 columnas, no cabria legible en portrait.
 *
 * Firma: unicamente el almacenista ACTIVO de ACF_ALMACENISTA (Sergio,
 * 2026-09-21: "por ahora no se requiere otra firma sino solo la del
 * almacenista") -- ya viene resuelto en cabecera.nombre_almacenista,
 * sin llamado aparte a un endpoint de firmantes (a diferencia de
 * Deterioro/RVU/Comite/Depreciacion, que usan ACF_FIRMANTE).
 */
export function generarActaTomaFisica(
  cabecera: TomaFisicaCabecera,
  detalle: TomaFisicaDetalleLinea[],
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

    dibujarMarcaDeAgua(doc, cabecera.estado, fechaDelEstadoTF(cabecera));

    dibujarEncabezado(
      doc,
      cabecera,
      'INFORME DE TOMA FISICA DE ACTIVOS FIJOS',
      `TOMA FISICA No. ${cabecera.consecutivo}`
    );

    doc.font('Helvetica').fontSize(9);
    doc.text(`Descripcion: ${cabecera.descripcion}`);
    doc.text(
      `Periodo: ${fmtFecha(cabecera.fecha_inicio)} a ${cabecera.fecha_fin ? fmtFecha(cabecera.fecha_fin) : '(en curso)'}`
    );
    doc.text(`Alcance: ${ALCANCE_LABEL[cabecera.alcance_tipo] ?? cabecera.alcance_tipo}`);
    const depResponsable = nombreValido(cabecera.nombre_dep_responsable);
    if (depResponsable) doc.text(`Dependencia: ${depResponsable}`);
    if (cabecera.bodega) doc.text(`Bodega: ${cabecera.bodega}`);
    doc.text(`Estado: ${cabecera.estado === 'CERRADA' ? 'Cerrada' : 'En proceso'}`);
    if (cabecera.estado === 'CERRADA' && cabecera.fecha_cierre) {
      doc.text(
        `Fecha de cierre: ${fmtFecha(cabecera.fecha_cierre)}` +
          (cabecera.usuario_cierre ? ` (${cabecera.usuario_cierre})` : '')
      );
    }
    if (cabecera.observaciones) doc.text(`Observaciones: ${cabecera.observaciones}`);
    doc.moveDown(0.8);

    // Anchos pensados para LETTER landscape (792pt) con margen 36 a
    // cada lado -> ancho util = 720pt. Suma de columnas = 720. 10
    // columnas confirmadas por Sergio (Placa/Ubicacion Esperada/
    // Ubicacion Encontrada/Estado Esperado/Estado Encontrado/
    // Resultado/Dependencia Esperada/Dependencia Encontrada/
    // Observaciones), mas Descripcion del activo (mismo criterio que
    // las otras 6 actas, que siempre la incluyen junto a la placa).
    dibujarTabla(doc, [
      { titulo: 'Placa', ancho: 35, valor: (f: TomaFisicaDetalleLinea) => String(f.numero_placa) },
      { titulo: 'Descripcion', ancho: 90, valor: (f: TomaFisicaDetalleLinea) => f.descripcion },
      { titulo: 'Ubic. esperada', ancho: 55, valor: (f: TomaFisicaDetalleLinea) => f.ubicacion_esperada ?? '-' },
      { titulo: 'Ubic. encontrada', ancho: 55, valor: (f: TomaFisicaDetalleLinea) => f.ubicacion_encontrada ?? '-' },
      { titulo: 'Estado esperado', ancho: 60, valor: (f: TomaFisicaDetalleLinea) => f.estado_esperado ?? '-' },
      { titulo: 'Estado encontrado', ancho: 60, valor: (f: TomaFisicaDetalleLinea) => f.estado_encontrado ?? '-' },
      { titulo: 'Resultado', ancho: 85, valor: (f: TomaFisicaDetalleLinea) => RESULTADO_LABEL[f.resultado] ?? f.resultado },
      { titulo: 'Dependencia esperada', ancho: 85, valor: (f: TomaFisicaDetalleLinea) => nombreValido(f.nombre_dependencia_esperada) ?? '-' },
      { titulo: 'Dependencia encontrada', ancho: 85, valor: (f: TomaFisicaDetalleLinea) => nombreValido(f.nombre_dependencia_encontrada) ?? '-' },
      { titulo: 'Observaciones', ancho: 110, valor: (f: TomaFisicaDetalleLinea) => f.observaciones ?? '-' },
    ], detalle);

    dibujarBloqueFirmas(doc, [
      { etiquetaRol: 'Almacenista', nombre: nombreValido(cabecera.nombre_almacenista) },
    ]);

    dibujarPie(doc, usuarioImprime);
    doc.end();
  });
}
