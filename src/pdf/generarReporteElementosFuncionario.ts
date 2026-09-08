import {
  PDFDocument,
  dibujarEncabezado,
  dibujarPie,
  dibujarTabla,
  fmtFecha,
  nombreValido,
} from './actaHelpers';
import { ElementoAsignadoLinea, ElementosFuncionarioCabecera } from '../repositorios/actasRepo';

/**
 * Reporte de Elementos Asignados a un Funcionario (Pagina 42, ver
 * Objetos_BD_ACF.txt "PAGINAS 42/43"). A diferencia de las 7 actas
 * existentes, no representa un documento transaccional (sin ESTADO,
 * sin firmantes) -- es un listado informativo, asi que no lleva marca
 * de agua ni bloque de firmas, solo encabezado + tabla + pie.
 */
export function generarReporteElementosFuncionario(
  cabecera: ElementosFuncionarioCabecera,
  detalle: ElementoAsignadoLinea[],
  usuarioImprime: string
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'LETTER', margin: 50 });
    const chunks: Buffer[] = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    dibujarEncabezado(
      doc,
      cabecera,
      'REPORTE DE ELEMENTOS ASIGNADOS A UN FUNCIONARIO',
      `FUNCIONARIO: ${nombreValido(cabecera.nombre_funcionario) ?? '(sin nombre)'}`
    );

    doc.font('Helvetica').fontSize(9);
    const dependenciaFuncionario = nombreValido(cabecera.nombre_dependencia_funcionario);
    if (dependenciaFuncionario) doc.text(`Dependencia del funcionario: ${dependenciaFuncionario}`);
    doc.text(`Total de elementos: ${detalle.length}`);
    doc.moveDown(0.8);

    dibujarTabla(doc, [
      { titulo: 'Placa', ancho: 60, valor: (f: ElementoAsignadoLinea) => String(f.numero_placa) },
      { titulo: 'Descripcion del Elemento', ancho: 232, valor: (f: ElementoAsignadoLinea) => f.descripcion },
      { titulo: 'Fecha de Asignacion', ancho: 100, align: 'center', valor: (f: ElementoAsignadoLinea) => fmtFecha(f.fecha_asignacion) },
      { titulo: 'Dependencia', ancho: 120, valor: (f: ElementoAsignadoLinea) => nombreValido(f.nombre_dependencia) ?? '-' },
    ], detalle);

    dibujarPie(doc, usuarioImprime);
    doc.end();
  });
}
