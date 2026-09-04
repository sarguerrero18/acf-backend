import 'dotenv/config';
import express, { Request, Response } from 'express';
import { verificarTokenApex } from './http/verificarTokenApex';
import { buscarIngreso, buscarTraslado, buscarEgreso, buscarDepreciacion, buscarComiteBaja } from './repositorios/actasRepo';
import { generarActaIngreso } from './pdf/generarActaIngreso';
import { generarActaTraslado } from './pdf/generarActaTraslado';
import { generarActaEgreso } from './pdf/generarActaEgreso';
import { generarActaDepreciacion } from './pdf/generarActaDepreciacion';
import { generarActaComiteBaja } from './pdf/generarActaComiteBaja';

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

app.get('/health', (_req: Request, res: Response) => {
  res.json({ status: 'ok' });
});

app.listen(PORT, () => {
  console.log(`Servidor de ACF (actas/reportes) escuchando en http://localhost:${PORT}`);
});
