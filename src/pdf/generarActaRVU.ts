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
import { RVUCabecera, RVUDetalleLinea, Firmante } from '../repositorios/actasRepo';

const MESES = [
  '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

const ROL_LABEL: Record<Firmante['rol'], string> = {
  CONTADOR: 'Contador',
  ALMACENISTA: 'Almacenista',
  // 'OTRO' no deberia salir en la practica (rvu-firmantes restringe ROL
  // IN ('CONTADOR','ALMACENISTA'), confirmado por Sergio 2026-09-07 --
  // mismo criterio que Depreciacion/Deterioro), pero el tipo TS
  // Firmante['rol'] es compartido con Comite de Bajas y hay que cubrir
  // el caso igual para que compile.
  OTRO: 'Miembro del comite',
};

// Dias transcurridos/ajustados: se formatean con separador de miles
// es-CO pero SIN decimales (a diferencia de fmtValor, pensado para
// dinero) -- son conteos de dias, nunca centavos.
function fmtDias(n: number): string {
  return n.toLocaleString('es-CO', { maximumFractionDigits: 0 });
}

// AJUSTE_DIAS puede ser positivo (extiende la vida util) o negativo (la
// reduce) -- se antepone "+" al positivo para que la direccion del
// ajuste sea inequivoca en el impreso (toLocaleString ya antepone "-"
// al negativo por si solo).
function fmtAjuste(n: number): string {
  return n > 0 ? `+${fmtDias(n)}` : fmtDias(n);
}

/**
 * Acta de Recalculo de Vida Util -- landscape/margenes estrechos, mismo
 * criterio que la acta de Deterioro (src/pdf/generarActaDeterioro.ts):
 * son muchos campos numericos (antes/despues de vida util ajustada,
 * vida util restante y valor residual, mas el insumo de ajuste en dias
 * y el porcentaje de valor residual) para que quepan en una tabla
 * portrait de 512pt utiles. No hay entrega/recibe (es una evaluacion
 * tecnica de un solo evaluador, igual que Deterioro) -- el bloque de
 * firmas es CONTADOR/ALMACENISTA via ACF_FIRMANTE
 * (TIPO_DOCUMENTO='RECALCULO_VIDA_UTIL', confirmado por Sergio
 * 2026-09-07).
 */
export function generarActaRVU(
  cabecera: RVUCabecera,
  detalle: RVUDetalleLinea[],
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
      'ACTA DE RECALCULO DE VIDA UTIL',
      `ACTA DE RECALCULO DE VIDA UTIL No. ${cabecera.consecutivo}`
    );

    doc.font('Helvetica').fontSize(9);
    doc.text(`Tipo de movimiento: ${cabecera.desc_tipo_movimiento}`);
    doc.text(`Periodo: ${MESES[cabecera.mes]} ${cabecera.anio}`);
    doc.text(`Fecha de generacion: ${fmtFecha(cabecera.fecha_generacion)}`);
    // FECHA_GENERACION (cuando se elaboro el acta) y FECHA_APROBACION
    // (el tramite administrativo) son campos distintos y pueden no
    // coincidir -- mismo criterio ya usado en Comite de Bajas/Deterioro.
    if (cabecera.fecha_aprobacion) {
      doc.text(
        `Fecha de aprobacion: ${fmtFecha(cabecera.fecha_aprobacion)}` +
          (cabecera.usuario_aprobacion ? ` (${cabecera.usuario_aprobacion})` : '')
      );
    }
    if (cabecera.numero_documento_soporte) {
      doc.text(`Documento soporte: ${cabecera.numero_documento_soporte} (${fmtFecha(cabecera.fecha_documento_soporte)})`);
    }
    if (cabecera.observaciones) doc.text(`Observaciones: ${cabecera.observaciones}`);
    doc.moveDown(0.8);

    // Nota aclaratoria: un recalculo de vida util (NIC 8, cambio de
    // estimado) es prospectivo y NO genera ningun movimiento contable --
    // se deja explicito en el impreso, mismo mensaje que ya ve el
    // usuario en el NATIVE_CONFIRM de la Pagina 40 al aprobar.
    doc.font('Helvetica-Oblique').fontSize(8).fillColor('gray');
    doc.text('Cambio de estimado contable (NIC 8) -- aplicacion prospectiva, no genera movimiento contable.');
    doc.fillColor('black').font('Helvetica').fontSize(9);
    doc.moveDown(0.4);

    // Anchos pensados para LETTER landscape (792pt) con margen 36 a cada
    // lado -> ancho util = 720pt. Suma de columnas = 720. VALOR_SALVAMENTO
    // se deja fuera de la tabla impresa (concepto fiscal informativo,
    // sin antes/despues -- ver migrations/04_ords_actas.sql) para que
    // quepan los pares antes/despues que si son el objeto del acta.
    dibujarTabla(doc, [
      { titulo: 'Placa', ancho: 35, valor: (f: RVUDetalleLinea) => String(f.numero_placa) },
      { titulo: 'Descripcion', ancho: 90, valor: (f: RVUDetalleLinea) => f.descripcion },
      { titulo: 'Causa', ancho: 85, valor: (f: RVUDetalleLinea) => f.causa },
      { titulo: 'Justificacion', ancho: 90, valor: (f: RVUDetalleLinea) => f.justificacion },
      { titulo: 'Ajuste\n(dias)', ancho: 45, align: 'right', valor: (f: RVUDetalleLinea) => fmtAjuste(f.ajuste_dias) },
      { titulo: 'Valor en libros', ancho: 75, align: 'right', valor: (f: RVUDetalleLinea) => `$${fmtValor(f.valor_libros_antes)}` },
      {
        titulo: 'Vida util ajustada\n(antes -> despues)',
        ancho: 80,
        align: 'right',
        valor: (f: RVUDetalleLinea) => `${fmtDias(f.vida_util_ajustada_antes)} -> ${fmtDias(f.vida_util_ajustada_despues)}`,
      },
      {
        titulo: 'Vida util restante\n(antes -> despues)',
        ancho: 80,
        align: 'right',
        valor: (f: RVUDetalleLinea) => `${fmtDias(f.vida_util_restante_antes)} -> ${fmtDias(f.vida_util_restante_despues)}`,
      },
      { titulo: '% Val. residual', ancho: 50, align: 'right', valor: (f: RVUDetalleLinea) => `${f.porcentaje_valor_residual.toFixed(2)}%` },
      {
        titulo: 'Valor residual\n(antes -> despues)',
        ancho: 90,
        align: 'right',
        valor: (f: RVUDetalleLinea) => `$${fmtValor(f.valor_residual_antes)} -> $${fmtValor(f.valor_residual_despues)}`,
      },
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
