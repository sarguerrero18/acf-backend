// ------------------------------------------------------------
// Cliente HTTP para el modulo ORDS 'actas' del schema ACF (ver
// migrations/01_ords_setup.sql / 02_ords_protect_oauth2.sql).
// Adaptado del ordsClient.ts de formula-engine (backend de nomina,
// GTH) -- mismo mecanismo (fetch nativo de Node, cache de token OAuth2
// en memoria del proceso), pero es un proyecto/servicio independiente,
// no un import compartido.
//
// Autenticacion: OAuth2 client_credentials.
// ------------------------------------------------------------

function baseUrl(): string {
  const url = process.env.ORDS_BASE_URL;
  if (!url) {
    throw new Error(
      "Falta la variable de entorno ORDS_BASE_URL (ej: 'https://<host>/ords/acf/actas')"
    );
  }
  if (url.includes('?')) {
    throw new Error(
      `ORDS_BASE_URL no debe incluir un endpoint ni query string, solo la base del modulo. ` +
        `Valor actual: '${url}'. Debe verse como 'https://<host>/ords/acf/actas'.`
    );
  }
  return url.endsWith('/') ? url.slice(0, -1) : url;
}

/**
 * URL del endpoint de token OAuth2. Si no se define ORDS_TOKEN_URL
 * explicitamente, se deriva de ORDS_BASE_URL reemplazando el ultimo
 * segmento (el nombre del modulo, ej. 'actas') por 'oauth/token'.
 * Ej: https://host/ords/acf/actas -> https://host/ords/acf/oauth/token
 */
function tokenUrl(): string {
  const explicita = process.env.ORDS_TOKEN_URL;
  if (explicita) return explicita;

  const base = baseUrl();
  const segmentos = base.split('/');
  segmentos.pop(); // quita el nombre del modulo ('actas')
  return `${segmentos.join('/')}/oauth/token`;
}

interface TokenCache {
  accessToken: string;
  expiraEn: number; // epoch ms
}

let cache: TokenCache | null = null;

// Si ya hay una solicitud de token en vuelo, las llamadas concurrentes
// esperan esa MISMA promesa en vez de disparar cada una su propio POST
// al endpoint de token.
let solicitudEnCurso: Promise<string> | null = null;

async function obtenerAccessToken(): Promise<string> {
  if (cache && Date.now() < cache.expiraEn - 60_000) {
    return cache.accessToken;
  }

  if (solicitudEnCurso) {
    return solicitudEnCurso;
  }

  solicitudEnCurso = (async () => {
    try {
      const clientId = process.env.ORDS_CLIENT_ID;
      const clientSecret = process.env.ORDS_CLIENT_SECRET;
      if (!clientId || !clientSecret) {
        throw new Error(
          'Faltan ORDS_CLIENT_ID / ORDS_CLIENT_SECRET (ver migrations/02_ords_protect_oauth2.sql para generarlos)'
        );
      }

      const credenciales = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');
      const url = tokenUrl();
      console.log(`  [oauth] pidiendo token a ${url}`);

      const respuesta = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Basic ${credenciales}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'grant_type=client_credentials',
      });

      const textoCrudo = await respuesta.text();

      if (!respuesta.ok) {
        throw new Error(
          `No se pudo obtener el token OAuth2 (status ${respuesta.status}): ${textoCrudo}`
        );
      }

      let data: { access_token?: string; expires_in?: number };
      try {
        data = JSON.parse(textoCrudo);
      } catch {
        throw new Error(
          `La respuesta del endpoint de token no es JSON valido (status ${respuesta.status}): ${textoCrudo.slice(0, 300)}`
        );
      }

      if (!data.access_token) {
        throw new Error(
          `La respuesta del endpoint de token no trajo 'access_token'. Cuerpo completo: ${textoCrudo.slice(0, 300)}`
        );
      }

      console.log(
        `  [oauth] token obtenido: ${data.access_token.slice(0, 8)}...${data.access_token.slice(-4)} (expira en ${data.expires_in}s)`
      );

      cache = {
        accessToken: data.access_token,
        expiraEn: Date.now() + (data.expires_in ?? 3600) * 1000,
      };
      return cache.accessToken;
    } finally {
      solicitudEnCurso = null;
    }
  })();

  return solicitudEnCurso;
}

async function authHeader(): Promise<string> {
  const token = await obtenerAccessToken();
  return `Bearer ${token}`;
}

interface OrdsCollection<T> {
  items: T[];
  hasMore?: boolean;
  count?: number;
}

async function leerJson<T>(respuesta: Response, contexto: string): Promise<T> {
  const texto = await respuesta.text();
  if (!texto) {
    throw new Error(
      `${contexto} devolvio una respuesta vacia (status ${respuesta.status}). ` +
        `Si es un handler PL/SQL, revisar los binds de respuesta y los ` +
        `ORDS.DEFINE_PARAMETER de tipo RESPONSE correspondientes.`
    );
  }
  try {
    return JSON.parse(texto) as T;
  } catch (err) {
    throw new Error(
      `${contexto} devolvio un cuerpo que no es JSON valido (status ${respuesta.status}): ${texto.slice(0, 500)}`
    );
  }
}

export async function ordsGet<T>(path: string, params?: Record<string, string>): Promise<T> {
  const url = new URL(`${baseUrl()}${path}`);
  if (params) {
    for (const [clave, valor] of Object.entries(params)) {
      url.searchParams.set(clave, valor);
    }
  }

  const auth = await authHeader();

  const respuesta = await fetch(url.toString(), {
    headers: { Authorization: auth, Accept: 'application/json' },
  });

  if (!respuesta.ok) {
    throw new Error(`ORDS GET ${path} fallo (${respuesta.status}): ${await respuesta.text()}`);
  }

  return leerJson<T>(respuesta, `ORDS GET ${path}`);
}

export async function ordsGetCollection<T>(
  path: string,
  params?: Record<string, string>
): Promise<T[]> {
  const data = await ordsGet<OrdsCollection<T>>(path, params);
  return data.items ?? [];
}

export async function ordsPost<T>(path: string, body: unknown): Promise<T> {
  const respuesta = await fetch(`${baseUrl()}${path}`, {
    method: 'POST',
    headers: {
      Authorization: await authHeader(),
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!respuesta.ok) {
    throw new Error(`ORDS POST ${path} fallo (${respuesta.status}): ${await respuesta.text()}`);
  }

  return leerJson<T>(respuesta, `ORDS POST ${path}`);
}
