// ------------------------------------------------------------
// Piezas compartidas por los 4 generadores de acta (Ingreso,
// Traslado, Egreso, Depreciacion) -- logo, titulo de 3 lineas,
// marca de agua por estado, bloque de firma y pie de pagina.
//
// Convenciones tomadas de formula-engine/src/pdf/generarComprobantePdf.ts
// (LETTER, margin 50, formateo es-CO), pero factorizadas aca porque
// las 4 actas comparten exactamente esta cabecera/pie.
// ------------------------------------------------------------

import PDFDocument from 'pdfkit';

export const MARGEN = 50;
export const ANCHO_UTIL = 512; // LETTER (612pt) - 2*50

export function fmtValor(valor: number | null | undefined): string {
  if (valor === null || valor === undefined) return '-';
  return valor.toLocaleString('es-CO', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export function fmtFecha(fecha: string | null | undefined): string {
  if (!fecha) return '-';
  // Los timestamps que devuelve ORDS vienen como ISO -- solo interesa la fecha.
  return fecha.slice(0, 10);
}

/**
 * Fecha asociada al ESTADO actual del movimiento -- ver nota de
 * "SUPUESTO A VALIDAR" en migrations/04_ords_actas.sql: se resuelve
 * con las columnas del propio encabezado (no hay historico disponible
 * todavia con estructura confirmada).
 */
export function fechaDelEstado(cab: {
  estado: string;
  fecha_creacion: string | null;
  fecha_aprobacion: string | null;
  fecha_modificacion: string | null;
}): string {
  if (cab.estado === 'APROBADO' && cab.fecha_aprobacion) return fmtFecha(cab.fecha_aprobacion);
  if (cab.estado === 'ANULADO' && cab.fecha_modificacion) return fmtFecha(cab.fecha_modificacion);
  return fmtFecha(cab.fecha_creacion);
}

export interface EntidadHeader {
  nombre_cliente: string | null;
  nombre_entidad: string | null;
  logo_entidad: string | null; // base64 (ORDS serializa BLOB asi)
  logo_mime_type: string | null;
}

/**
 * Logo (si existe) + titulo de 3 lineas: cliente / entidad / nombre del acta.
 * Devuelve el `y` donde puede empezar el resto del contenido.
 */
export function dibujarEncabezado(
  doc: PDFKit.PDFDocument,
  entidad: EntidadHeader,
  tituloActa: string,
  numeroDocumento: string
): number {
  const yInicial = doc.y;

  if (entidad.logo_entidad) {
    try {
      const buffer = Buffer.from(entidad.logo_entidad, 'base64');
      doc.image(buffer, MARGEN, yInicial, { width: 60, height: 60, fit: [60, 60] });
    } catch {
      // Logo corrupto o formato no reconocido por pdfkit -- se omite sin
      // romper la generacion del acta.
    }
  }

  const xTitulo = MARGEN + 75;
  const anchoTitulo = ANCHO_UTIL - 75;

  doc.font('Helvetica-Bold').fontSize(13).text(entidad.nombre_cliente ?? '', xTitulo, yInicial, {
    width: anchoTitulo,
    align: 'center',
  });
  doc.font('Helvetica').fontSize(11).text(entidad.nombre_entidad ?? '', xTitulo, doc.y, {
    width: anchoTitulo,
    align: 'center',
  });
  doc.font('Helvetica-Bold').fontSize(12).text(tituloActa, xTitulo, doc.y + 2, {
    width: anchoTitulo,
    align: 'center',
  });

  const yDespuesLogo = yInicial + 65;
  const yDespuesTitulo = doc.y + 10;
  doc.y = Math.max(yDespuesLogo, yDespuesTitulo);

  doc.font('Helvetica-Bold').fontSize(10).text(numeroDocumento, MARGEN, doc.y, {
    width: ANCHO_UTIL,
    align: 'center',
  });
  doc.moveDown(1);

  return doc.y;
}

/**
 * Marca de agua diagonal con el ESTADO y su fecha, sobre TODA la
 * pagina actual. Se dibuja antes del contenido para que quede debajo
 * (pdfkit no tiene z-index -- el orden de dibujo es el z-order).
 */
export function dibujarMarcaDeAgua(doc: PDFKit.PDFDocument, estado: string, fecha: string): void {
  // doc.save()/doc.restore() solo cubren el estado grafico (rotacion,
  // opacidad, color, etc.) -- NO restauran doc.x/doc.y (el cursor de
  // texto), que pdfkit mueve con cada doc.text(). Sin guardar/restaurar
  // el cursor a mano aca, dibujarEncabezado() (llamado justo despues)
  // arrancaria desde donde quedo el cursor tras dibujar la marca de
  // agua -- muy abajo en la pagina -- en vez de la esquina superior.
  const xOriginal = doc.x;
  const yOriginal = doc.y;

  doc.save();
  doc.rotate(-45, { origin: [306, 396] });
  doc.opacity(0.12);
  doc.font('Helvetica-Bold').fontSize(58).fillColor('gray');
  doc.text(estado, 6, 350, { width: 900, align: 'center' });
  doc.opacity(0.12).fontSize(16);
  doc.text(fecha, 6, 430, { width: 900, align: 'center' });
  doc.opacity(1);
  doc.restore();

  doc.x = xOriginal;
  doc.y = yOriginal;
}

/**
 * PK_GENERAL.fn_nombre_tercero/fn_nombre_dependencia NO devuelven NULL
 * cuando el id no resuelve a una persona/dependencia real -- devuelven
 * un string descriptivo (ej. "Error: Persona no ha sido creada."),
 * confirmado probando contra datos reales (Traslado id=44,
 * nombre_tercero_comodato). Sin este filtro esos textos se mostrarian
 * en el acta como si fueran un nombre valido. Se trata como "sin dato"
 * cualquier valor que empiece por "Error" (sin distinguir mayusculas).
 */
export function nombreValido(valor: string | null | undefined): string | null {
  if (!valor) return null;
  const limpio = valor.trim();
  if (limpio === '' || limpio.toUpperCase().startsWith('ERROR')) return null;
  return limpio;
}

export interface DatosFirma {
  etiquetaRol: string; // "Quien entrega", "Contador", etc.
  nombre: string | null;
  identificacion?: string | null; // cedula (depreciacion) o vacio
  dependencia?: string | null;
}

/**
 * Bloques de firma lado a lado (1 o 2 firmas), con linea y datos debajo.
 */
export function dibujarBloqueFirmas(doc: PDFKit.PDFDocument, firmas: DatosFirma[]): void {
  doc.moveDown(3);
  const y = doc.y;
  const anchoBloque = ANCHO_UTIL / firmas.length;

  firmas.forEach((firma, i) => {
    const x = MARGEN + i * anchoBloque;
    const anchoTexto = anchoBloque - 20;
    const nombre = nombreValido(firma.nombre);
    const dependencia = nombreValido(firma.dependencia);

    doc.moveTo(x + 10, y).lineTo(x + anchoTexto, y).stroke();
    doc.font('Helvetica-Bold').fontSize(9).text(nombre ?? '(sin asignar)', x + 10, y + 4, {
      width: anchoTexto,
      align: 'center',
    });
    doc.font('Helvetica').fontSize(9).text(firma.etiquetaRol, x + 10, doc.y, {
      width: anchoTexto,
      align: 'center',
    });
    if (firma.identificacion) {
      doc.text(`C.C. ${firma.identificacion}`, x + 10, doc.y, { width: anchoTexto, align: 'center' });
    }
    if (dependencia) {
      doc.text(dependencia, x + 10, doc.y, { width: anchoTexto, align: 'center' });
    }
  });
}

export interface ColumnaTabla<T> {
  titulo: string;
  ancho: number;
  align?: PDFKit.Mixins.TextOptions['align'];
  valor: (fila: T) => string;
}

/**
 * Tabla simple de detalle (placas/activos) con encabezado repetido si
 * hace falta salto de pagina. pdfkit no tiene tablas nativas -- mismo
 * criterio manual de columnas fijas ya usado en generarComprobantePdf.ts.
 */
export function dibujarTabla<T>(doc: PDFKit.PDFDocument, columnas: ColumnaTabla<T>[], filas: T[]): void {
  const dibujarEncabezadoTabla = () => {
    const y = doc.y;
    let x = MARGEN;
    doc.font('Helvetica-Bold').fontSize(8);
    for (const col of columnas) {
      doc.text(col.titulo, x, y, { width: col.ancho, align: col.align ?? 'left' });
      x += col.ancho;
    }
    doc.moveDown(0.3);
    doc.moveTo(MARGEN, doc.y).lineTo(MARGEN + ANCHO_UTIL, doc.y).stroke();
    doc.moveDown(0.2);
  };

  dibujarEncabezadoTabla();

  doc.font('Helvetica').fontSize(8);
  for (const fila of filas) {
    if (doc.y > doc.page.height - MARGEN - 80) {
      doc.addPage();
      dibujarEncabezadoTabla();
      doc.font('Helvetica').fontSize(8);
    }
    const y = doc.y;
    let x = MARGEN;
    for (const col of columnas) {
      doc.text(col.valor(fila), x, y, { width: col.ancho, align: col.align ?? 'left' });
      x += col.ancho;
    }
    doc.moveDown(0.4);
  }
}

/**
 * Pie de pagina fijo: fecha de impresion + usuario que imprime. Se
 * dibuja al final, anclado a la parte baja de la pagina actual.
 */
export function dibujarPie(doc: PDFKit.PDFDocument, usuarioImprime: string): void {
  const yPie = doc.page.height - MARGEN + 10;
  const fechaImpresion = new Date().toISOString().slice(0, 19).replace('T', ' ');

  // yPie cae DENTRO del margen inferior (page.height - MARGEN + 10 >
  // page.height - MARGEN), a proposito, para que el pie quede pegado al
  // borde de la hoja. Pero pdfkit calcula su limite de contenido como
  // page.height - margins.bottom, y si el y solicitado lo supera,
  // dispara un salto de pagina automatico ANTES de escribir -- por eso
  // el pie terminaba solo en una hoja nueva. Se baja el margen inferior
  // a 0 momentaneamente (pdfkit ya no ve motivo para paginar) y se
  // restaura enseguida despues de escribir.
  const margenInferiorOriginal = doc.page.margins.bottom;
  doc.page.margins.bottom = 0;

  doc
    .font('Helvetica')
    .fontSize(7)
    .fillColor('gray')
    .text(`Impreso el ${fechaImpresion} por ${usuarioImprime}`, MARGEN, yPie, {
      width: ANCHO_UTIL,
      align: 'center',
    });

  doc.page.margins.bottom = margenInferiorOriginal;
  doc.fillColor('black');
}

export { PDFDocument };
