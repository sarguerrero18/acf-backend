import 'dotenv/config';
import express, { Request, Response } from 'express';
import { verificarTokenApex } from './http/verificarTokenApex';
import { buscarIngreso, buscarTraslado, buscarEgreso, buscarDepreciacion, buscarComiteBaja, buscarDeterioro, buscarRVU, buscarElementosFuncionario, buscarElementosDependencia } from './repositorios/actasRepo';
import { generarActaIngreso } from './pdf/generarActaIngreso';
import { generarActaTraslado } from './pdf/generarActaTraslado';
import { generarActaEgreso } from './pdf/generarActaEgreso';
import { generarActaDepreciacion } from './pdf/generarActaDepreciacion';
import { generarActaComiteBaja } from './pdf/generarActaComiteBaja';
import { generarActaDeterioro } from './pdf/generarActaDeterioro';
import { generarActaRVU } from './pdf/generarActaRVU';
import { generarReporteElementosFuncionario } from './pdf/generarReporteElementosFuncionario';
import { generarReporteElementosDependencia } from './pdf/generarReporteElementosDependencia';

const app = express();
const PORT = Number(process.env.PORT ?? 3001);

app.use(express.json());

/**
 * Rutas de actas de Activos Fijos, todas protegidas por Bearer token
 * (ver src/http/verificarTokenApex.ts). El "usuario que imprime" (pie
 * de pagina del acta) NO sale del token -- el token solo identifica a
 * la aplicacion (acf_apex_client), no a la persona -- APEX lo manda
 * explicito como query param ?usuario=, igual patron que formula-engine
 * (usuarioLiquida en el body de /liquidar/*).
 *
 * Estas rutas NO se llaman directo desde el navegador del usuario final
 * (son Bearer-protegidas): APEX las llama desde PL/SQL con
 * MAKE_REST_REQUEST_B (BLOB) y hace de proxy hacia el navegador. Ver
 * deploy/pkg_acf_client.sql y Objetos_BD_ACF.txt (seccion de Actas,
 * "Entrega del PDF") para el detalle del proxy.
 */

function usuarioDeQuery(req: Request): string {
  const usuario = req.query.usuario;
  return typeof usuario === 'string' && usuario.trim() !== '' ? usuario : 'DESCONOCIDO';
}

app.get('/actas/health-check', verificarTokenApex, (_req: Request, res: Response) => {
  res.json({ status: 'ok' });
});

app.get('/actas/ingreso/:id', verificarTokenApex, async (req: Request, res: Response) => {
  try {
    const { cabecera, detalle } = await buscarIngreso(req.params.id);
    const pdf = await generarActaIngreso(cabecera, detalle, usuarioDeQuery(req));
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="acta_ingreso_${cabecera.consecutivo}.pdf"`);
    res.send(pdf);
  } catch (err) {
    console.error('[actas/ingreso] error:', err);
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get('/actas/traslado/:id', verificarTokenApex, async (req: Request, res: Response) => {
  try {
    const { cabecera, detalle } = await buscarTraslado(req.params.id);
    const pdf = await generarActaTraslado(cabecera, detalle, usuarioDeQuery(req));
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="acta_traslado_${cabecera.consecutivo}.pdf"`);
    res.send(pdf);
  } catch (err) {
    console.error('[actas/traslado] error:', err);
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get('/actas/egreso/:id', verificarTokenApex, async (req: Request, res: Response) => {
  try {
    const { cabecera, detalle } = await buscarEgreso(req.params.id);
    const pdf = await generarActaEgreso(cabecera, detalle, usuarioDeQuery(req));
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="acta_egreso_${cabecera.consecutivo}.pdf"`);
    res.send(pdf);
  } catch (err) {
    console.error('[actas/egreso] error:', err);
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get('/actas/depreciacion/:id', verificarTokenApex, async (req: Request, res: Response) => {
  try {
    const { cabecera, detalle, firmantes } = await buscarDepreciacion(req.params.id);
    const pdf = await generarActaDepreciacion(cabecera, detalle, firmantes, usuarioDeQuery(req));
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="acta_depreciacion_${cabecera.consecutivo}.pdf"`);
    res.send(pdf);
  } catch (err) {
    console.error('[actas/depreciacion] error:', err);
    res.status(500).json({ error: (err as Error).message });
  }
});

// Ruta 'comite_baja' (con guion bajo) para que calce con
// LOWER(:P36_TIPO) cuando P36_TIPO='COMITE_BAJA' desde la Pagina 36 --
// mismo criterio de nombres que los demas tipos (ingreso/traslado/
// egreso/depreciacion), solo que este es un tipo compuesto.
app.get('/actas/comite_baja/:id', verificarTokenApex, async (req: Request, res: Response) => {
  try {
    const { cabecera, detalle, firmantes } = await buscarComiteBaja(req.params.id);
    const pdf = await generarActaComiteBaja(cabecera, detalle, firmantes, usuarioDeQuery(req));
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="acta_comite_baja_${cabecera.consecutivo}.pdf"`);
    res.send(pdf);
  } catch (err) {
    console.error('[actas/comite_baja] error:', err);
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get('/actas/deterioro/:id', verificarTokenApex, async (req: Request, res: Response) => {
  try {
    const { cabecera, detalle, firmantes } = await buscarDeterioro(req.params.id);
    const pdf = await generarActaDeterioro(cabecera, detalle, firmantes, usuarioDeQuery(req));
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="acta_deterioro_${cabecera.consecutivo}.pdf"`);
    res.send(pdf);
  } catch (err) {
    console.error('[actas/deterioro] error:', err);
    res.status(500).json({ error: (err as Error).message });
  }
});

// Ruta 'recalculo_vida_util' -- NO usar el alias corto 'rvu' aqui: la
// Pagina 36 (proxy de descarga generico, ver Objetos_BD_ACF.txt
// "Modulo de Actas") arma la ruta como
// 'actas/' || LOWER(:P36_TIPO) || '/' || :P36_ID, y P36_TIPO llega
// siempre con el valor de NEGOCIO sin abreviar (mismo valor que
// ACF_TIPO_MOVIMIENTO.TIPO_MOV_ACF y ACF_FIRMANTE.TIPO_DOCUMENTO,
// 'RECALCULO_VIDA_UTIL' -- ver el DA de la Pagina 40:
// P36_TIPO,P36_ID:RECALCULO_VIDA_UTIL,&P40_ID.). Solo los NOMBRES DE
// OBJETOS de base de datos se abreviaron a RVU (ACF_RVU,
// ACF_DETALLE_RVU, etc.) -- este segmento de URL no es un nombre de
// objeto, es el mismo valor de negocio que las otras rutas de este
// dispatcher (comparar con 'comite_baja', que tampoco se abrevio).
app.get('/actas/recalculo_vida_util/:id', verificarTokenApex, async (req: Request, res: Response) => {
  try {
    const { cabecera, detalle, firmantes } = await buscarRVU(req.params.id);
    const pdf = await generarActaRVU(cabecera, detalle, firmantes, usuarioDeQuery(req));
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="acta_recalculo_vida_util_${cabecera.consecutivo}.pdf"`);
    res.send(pdf);
  } catch (err) {
    console.error('[actas/recalculo_vida_util] error:', err);
    res.status(500).json({ error: (err as Error).message });
  }
});

// Reportes de Elementos Asignados (Paginas 42/43, ver Objetos_BD_ACF.txt
// "PAGINAS 42/43" y "CORRECCION PAGINAS 42/43"). A diferencia de las
// actas de arriba, el :id de la URL no es la PK de un documento propio
// -- es el ID de GTH_FUNCIONARIOS (elementos_funcionario) o de
// GEN_DEPENDENCIA (elementos_dependencia) elegido en el selector de la
// pagina. Mismo patron P36_TIPO,P36_ID de la Pagina 36 (proxy generico
// de descarga): P36_TIPO='ELEMENTOS_FUNCIONARIO'/'ELEMENTOS_DEPENDENCIA'
// (sin abreviar, valor de negocio -- mismo criterio ya aplicado a
// 'comite_baja'/'recalculo_vida_util').
app.get('/actas/elementos_funcionario/:id', verificarTokenApex, async (req: Request, res: Response) => {
  try {
    const { cabecera, detalle } = await buscarElementosFuncionario(req.params.id);
    const pdf = await generarReporteElementosFuncionario(cabecera, detalle, usuarioDeQuery(req));
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="reporte_elementos_funcionario_${cabecera.funcionario_id}.pdf"`);
    res.send(pdf);
  } catch (err) {
    console.error('[actas/elementos_funcionario] error:', err);
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get('/actas/elementos_dependencia/:id', verificarTokenApex, async (req: Request, res: Response) => {
  try {
    const { cabecera, detalle } = await buscarElementosDependencia(req.params.id);
    const pdf = await generarReporteElementosDependencia(cabecera, detalle, usuarioDeQuery(req));
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="reporte_elementos_dependencia_${cabecera.dependencia_id}.pdf"`);
    res.send(pdf);
  } catch (err) {
    console.error('[actas/elementos_dependencia] error:', err);
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get('/health', (_req: Request, res: Response) => {
  res.json({ status: 'ok' });
});

app.listen(PORT, () => {
  console.log(`Servidor de ACF (actas/reportes) escuchando en http://localhost:${PORT}`);
});
