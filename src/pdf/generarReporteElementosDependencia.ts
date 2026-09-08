import {
  PDFDocument,
  dibujarEncabezado,
  dibujarPie,
  dibujarTabla,
  fmtFecha,
  nombreValido,
} from './actaHelpers';
import { ElementoAsignadoLinea, ElementosDependenciaCabecera } from '../repositorios/actasRepo';

/**
 * Reporte de Elementos Asignados a una Dependencia (Pagina 43, ver
 * Objetos_BD_ACF.txt "PAGINAS 42/43"). Mismo criterio que el reporte
 * por Funcionario (generarReporteElementosFuncionario.ts) -- sin marca
 * de agua ni firmantes, solo encabezado + tabla + pie. A pedido de
 * Sergio, aqui la tabla SI incluye el nombre del funcionario por fila
 * (varios funcionarios distintos pueden compartir la misma
 * dependencia), a diferencia del reporte por Funcionario donde es la
 * dependencia la que varia fila a fila.
 */
export function generarReporteElementosDependencia(
  cabecera: ElementosDependenciaCabecera,
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
      'REPORTE DE ELEMENTOS ASIGNADOS A UNA DEPENDENCIA',
      `DEPENDENCIA: ${nombreValido(cabecera.nombre_dependencia) ?? '(sin nombre)'}`
    );

    doc.font('Helvetica').fontSize(9);
    doc.text(`Total de elementos: ${detalle.length}`);
    doc.moveDown(0.8);

    dibujarTabla(doc, [
      { titulo: 'Placa', ancho: 55, valor: (f: ElementoAsignadoLinea) => String(f.numero_placa) },
      { titulo: 'Descripcion del Elemento', ancho: 190, valor: (f: ElementoAsignadoLinea) => f.descripcion },
      { titulo: 'Fecha de Asignacion', ancho: 90, align: 'center', valor: (f: ElementoAsignadoLinea) => fmtFecha(f.fecha_asignacion) },
      { titulo: 'Funcionario', ancho: 100, valor: (f: ElementoAsignadoLinea) => nombreValido(f.nombre_funcionario) ?? '-' },
      { titulo: 'Dependencia', ancho: 77, valor: () => nombreValido(cabecera.nombre_dependencia) ?? '-' },
    ], detalle);

    dibujarPie(doc, usuarioImprime);
    doc.end();
  });
}
