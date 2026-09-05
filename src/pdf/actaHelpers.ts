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

// Mantenidos como constantes exportadas por compatibilidad (nada fuera
// de este archivo las usa hoy, ver busqueda previa a la OCTAVA
// ADICION), pero las funciones de dibujo YA NO las usan directo --
// ver nota de OCTAVA ADICION mas abajo.
export const MARGEN = 50;
export const ANCHO_UTIL = 512; // LETTER (612pt) - 2*50

// OCTAVA ADICION (acta de Deterioro, landscape + margenes estrechos):
// hasta aca, dibujarEncabezado/dibujarMarcaDeAgua/dibujarBloqueFirmas/
// dibujarTabla/dibujarPie usaban las constantes MARGEN=50/ANCHO_UTIL=512
// hardcodeadas -- validas solo para LETTER portrait con margen 50. La
// acta de Deterioro pidio orientacion horizontal ("landscape") con
// margenes estrechos (Sergio: "Como son bastantes campos se debe
// generar un reporte con orientacion horizontal y con margenes
// estrechos"), lo que rompia esas dos constantes. En vez de duplicar
// las 5 funciones para un segundo layout, se cambiaron para leer el
// margen/ancho util DIRECTO del objeto `doc` (doc.page.margins.*,
// doc.page.width/height), que pdfkit ya conoce (se configura al crear
// el PDFDocument con size/layout/margins). Para las 5 actas existentes
// (portrait LETTER, margin:50) esto da EXACTAMENTE los mismos valores
// que las constantes hardcodeadas (612-2*50=512), o sea CERO cambio de
// comportamiento -- confirmado antes de aplicar el cambio. Las
// constantes MARGEN/ANCHO_UTIL se dejan exportadas por si algo externo
// las usaba, pero ya no son la fuente de verdad dentro de este archivo.
function margenIzquierdo(doc: PDFKit.PDFDocument): number {
  return doc.page.margins.left;
}
function anchoUtilDoc(doc: PDFKit.PDFDocument): number {
  return doc.page.width - doc.page.margins.left - doc.page.margins.right;
}

// Espacio en blanco entre columnas de dibujarTabla -- sin esto, dos
// columnas seguidas (ej. "No. Egreso" y "Observaciones") podian quedar
// pegadas visualmente cuando el contenido de la primera llega justo al
// borde de su ancho asignado.
const PADDING_COL = 6;

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
  const margen = margenIzquierdo(doc);
  const anchoUtil = anchoUtilDoc(doc);
  const yInicial = doc.y;

  if (entidad.logo_entidad) {
    try {
      const buffer = Buffer.from(entidad.logo_entidad, 'base64');
      doc.image(buffer, margen, yInicial, { width: 60, height: 60, fit: [60, 60] });
    } catch {
      // Logo corrupto o formato no reconocido por pdfkit -- se omite sin
      // romper la generacion del acta.
    }
  }

  const xTitulo = margen + 75;
  const anchoTitulo = anchoUtil - 75;

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

  doc.font('Helvetica-Bold').fontSize(10).text(numeroDocumento, margen, doc.y, {
    width: anchoUtil,
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

  // Origen de rotacion = centro exacto de la pagina actual. Para
  // portrait LETTER (612x792) esto da [306, 396] -- el mismo valor
  // hardcodeado que tenia esta funcion antes de la OCTAVA ADICION --
  // asi que no hay cambio de comportamiento en las 5 actas existentes.
  // Para landscape (ej. 792x612, acta de Deterioro) da [396, 306], que
  // es lo correcto para esa orientacion.
  doc.save();
  doc.rotate(-45, { origin: [doc.page.width / 2, doc.page.height / 2] });
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
  matricula?: string | null; // tarjeta/matricula profesional (contador)
  dependencia?: string | null;
}

/**
 * Bloques de firma lado a lado (1 o 2 firmas), con linea y datos debajo.
 */
export function dibujarBloqueFirmas(doc: PDFKit.PDFDocument, firmas: DatosFirma[]): void {
  const anchoUtil = anchoUtilDoc(doc);
  const margen = margenIzquierdo(doc);
  doc.moveDown(3);
  const y = doc.y;
  const anchoBloque = anchoUtil / firmas.length;

  firmas.forEach((firma, i) => {
    const x = margen + i * anchoBloque;
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
    if (firma.matricula) {
      doc.text(`T.P. ${firma.matricula}`, x + 10, doc.y, { width: anchoTexto, align: 'center' });
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
  const margen = margenIzquierdo(doc);
  const anchoUtil = anchoUtilDoc(doc);
  // doc.text() con x/y explicitos NO actualiza doc.y en funcion de la
  // columna mas alta -- lo deja en donde termino la ULTIMA columna
  // escrita. Si una columna anterior se envuelve a 2-3 lineas (ej.
  // "Tipo egreso sugerido" o "No. Egreso" en un ancho angosto) pero la
  // ultima columna de la fila es de una sola linea, doc.moveDown()
  // avanzaba muy poco y la linea separadora (o la fila siguiente)
  // quedaba montada sobre el texto envuelto. Se mide la altura real de
  // cada columna con doc.heightOfString() (requiere el font/fontSize ya
  // aplicado) y se usa la mas alta para avanzar el cursor.
  const alturaFila = (textos: string[]): number => {
    let maxAltura = 0;
    columnas.forEach((col, i) => {
      const h = doc.heightOfString(textos[i], { width: col.ancho - PADDING_COL });
      if (h > maxAltura) maxAltura = h;
    });
    return maxAltura;
  };

  const dibujarEncabezadoTabla = () => {
    const y = doc.y;
    let x = margen;
    doc.font('Helvetica-Bold').fontSize(8);
    const titulos = columnas.map((col) => col.titulo);
    const altura = alturaFila(titulos);
    for (const col of columnas) {
      doc.text(col.titulo, x, y, { width: col.ancho - PADDING_COL, align: col.align ?? 'left' });
      x += col.ancho;
    }
    doc.y = y + altura + 3;
    doc.moveTo(margen, doc.y).lineTo(margen + anchoUtil, doc.y).stroke();
    doc.moveDown(0.2);
  };

  dibujarEncabezadoTabla();

  doc.font('Helvetica').fontSize(8);
  for (const fila of filas) {
    // Antes se comparaba contra `MARGEN` (hardcodeado en 50) como proxy
    // del margen inferior -- funcionaba porque las 5 actas existentes
    // usan margen uniforme de 50pt en los 4 lados. Con margenes
    // estrechos/asimetricos (acta de Deterioro) hay que usar el margen
    // inferior real de la pagina, no el izquierdo.
    if (doc.y > doc.page.height - doc.page.margins.bottom - 80) {
      doc.addPage();
      dibujarEncabezadoTabla();
      doc.font('Helvetica').fontSize(8);
    }
    const y = doc.y;
    let x = margen;
    const valores = columnas.map((col) => col.valor(fila));
    const altura = alturaFila(valores);
    for (const col of columnas) {
      doc.text(col.valor(fila), x, y, { width: col.ancho - PADDING_COL, align: col.align ?? 'left' });
      x += col.ancho;
    }
    doc.y = y + altura + 4;
  }
}

/**
 * Pie de pagina fijo: fecha de impresion + usuario que imprime. Se
 * dibuja al final, anclado a la parte baja de la pagina actual.
 */
export function dibujarPie(doc: PDFKit.PDFDocument, usuarioImprime: string): void {
  const margen = margenIzquierdo(doc);
  const anchoUtil = anchoUtilDoc(doc);
  // yPie cae DENTRO del margen inferior (page.height - margenInferior +
  // 10 > page.height - margenInferior), a proposito, para que el pie
  // quede pegado al borde de la hoja. Pero pdfkit calcula su limite de
  // contenido como page.height - margins.bottom, y si el y solicitado
  // lo supera, dispara un salto de pagina automatico ANTES de escribir
  // -- por eso el pie terminaba solo en una hoja nueva. Se baja el
  // margen inferior a 0 momentaneamente (pdfkit ya no ve motivo para
  // paginar) y se restaura enseguida despues de escribir.
  const margenInferiorOriginal = doc.page.margins.bottom;
  const yPie = doc.page.height - margenInferiorOriginal + 10;
  const fechaImpresion = new Date().toISOString().slice(0, 19).replace('T', ' ');

  doc.page.margins.bottom = 0;

  doc
    .font('Helvetica')
    .fontSize(7)
    .fillColor('gray')
    .text(`Impreso el ${fechaImpresion} por ${usuarioImprime}`, margen, yPie, {
      width: anchoUtil,
      align: 'center',
    });

  doc.page.margins.bottom = margenInferiorOriginal;
  doc.fillColor('black');
}

export { PDFDocument };
