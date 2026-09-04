import { Request, Response, NextFunction } from 'express';

/**
 * Valida el Authorization: Bearer <token> que manda APEX, reutilizando
 * ORDS como fuente de verdad: si ORDS acepta ese mismo token para un
 * GET protegido de /actas/*, el token es valido y tiene el privilegio
 * correcto (acf_actas_api_role, ver migrations/02 y 03).
 *
 * Mismo mecanismo que verificarTokenApex.ts de formula-engine (GTH).
 *
 * El "ping" apunta a PING_PATH abajo -- ya no es un placeholder:
 * /health-check es un handler ORDS real (migrations/04_ords_actas.sql,
 * protegido por el mismo privilege que el resto de /actas/*), creado
 * especificamente para esto (sin efectos secundarios, SELECT trivial).
 */
const PING_PATH = '/health-check';

export async function verificarTokenApex(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Falta el header Authorization: Bearer <token>' });
    return;
  }

  const ordsBaseUrl = process.env.ORDS_BASE_URL;
  if (!ordsBaseUrl) {
    res.status(500).json({ error: 'Falta la variable de entorno ORDS_BASE_URL en el servidor' });
    return;
  }

  try {
    const pingUrl = `${ordsBaseUrl.replace(/\/$/, '')}${PING_PATH}`;
    const respuesta = await fetch(pingUrl, {
      headers: { Authorization: authHeader, Accept: 'application/json' },
    });

    if (!respuesta.ok) {
      res.status(401).json({ error: 'Token invalido o sin privilegio sobre /actas/*' });
      return;
    }

    next();
  } catch (err) {
    res.status(502).json({ error: `No se pudo validar el token contra ORDS: ${(err as Error).message}` });
  }
}
