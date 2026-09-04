-- ============================================================
-- pkg_acf_client
-- Correr en SQL Workshop -> SQL Commands, sobre el esquema ACF (el
-- mismo al que apunta la Application 104 en APEX).
--
-- Requiere que el Web Credential 'ACF_APEX_OAUTH2' ya exista en el
-- Workspace GEN (mismo workspace donde ya vive NOMINA_APEX_OAUTH2),
-- con Authentication Type = Basic Authentication, y el client_id/
-- client_secret de acf_apex_client (ver migrations/03_ords_apex_client.sql).
--
-- Uso desde cualquier proceso PL/SQL de la Application 104 (ACF):
--   l_auth := pkg_acf_client.obtener_bearer_header;
--   APEX_WEB_SERVICE.G_REQUEST_HEADERS(2).NAME  := 'Authorization';
--   APEX_WEB_SERVICE.G_REQUEST_HEADERS(2).VALUE := l_auth;
--
-- Mismo patron exacto que pkg_nomina_client.sql (schema GTH,
-- formula-engine) -- pero llama al backend acf-backend (proyecto/
-- deploy independiente), no al de nomina.
--
-- *** SUPUESTO A VALIDAR: la URL del endpoint de token asume que ACF
-- vive en la MISMA Autonomous Database que GTH (mismo host que ya usa
-- pkg_nomina_client.sql), solo cambiando /ords/gth/ por /ords/acf/.
-- Confirmar y ajustar si no es el caso.
--
-- url_backend() ya NO es placeholder -- acf-backend quedo desplegado
-- en Render en https://acf-backend-xwrq.onrender.com (2026-09-03).
-- ============================================================

CREATE OR REPLACE PACKAGE pkg_acf_client AS

  /** URL base del backend Node de ACF (acf-backend), desplegado en
   *  Render. */
  FUNCTION url_backend RETURN VARCHAR2;

  /** Devuelve 'Bearer <token>' listo para usar como header Authorization.
   *  Cachea el token a nivel de sesion de BD mientras siga vigente, para
   *  no pedir uno nuevo en cada llamada dentro de la misma sesion APEX. */
  FUNCTION obtener_bearer_header RETURN VARCHAR2;

  /** Descarga el PDF de un acta desde acf-backend (rutas protegidas
   *  /actas/*), llamando con el Bearer token de obtener_bearer_header,
   *  y devuelve el cuerpo de la respuesta como BLOB.
   *  p_ruta ej: 'actas/ingreso/123?usuario=JPEREZ' (sin la URL base ni
   *  la barra inicial). Usado por la Pagina de descarga (proxy) -- ver
   *  Objetos_BD_ACF.txt, seccion de Actas ("Entrega del PDF"). */
  FUNCTION descargar_acta(p_ruta VARCHAR2) RETURN BLOB;

END pkg_acf_client;
/

CREATE OR REPLACE PACKAGE BODY pkg_acf_client AS

  g_token  VARCHAR2(2000);
  g_expira TIMESTAMP;

  FUNCTION url_backend RETURN VARCHAR2 IS
  BEGIN
    RETURN 'https://acf-backend-xwrq.onrender.com';
  END url_backend;

  FUNCTION obtener_bearer_header RETURN VARCHAR2 IS
    l_resp CLOB;
  BEGIN
    IF g_token IS NOT NULL AND g_expira > SYSTIMESTAMP THEN
      RETURN 'Bearer ' || g_token;
    END IF;

    APEX_WEB_SERVICE.G_REQUEST_HEADERS.DELETE;
    APEX_WEB_SERVICE.G_REQUEST_HEADERS(1).NAME  := 'Content-Type';
    APEX_WEB_SERVICE.G_REQUEST_HEADERS(1).VALUE := 'application/x-www-form-urlencoded';

    -- ATENCION: p_credential_static_id busca por el campo "Static ID"
    -- del Web Credential (Workspace Utilities > Web Credentials), NO
    -- por el campo "Name" que se ve en la lista -- son campos distintos
    -- y el lookup es sensible a mayusculas/minusculas. CONFIRMADO por
    -- captura de pantalla de Sergio (2026-09-03, segunda verificacion):
    -- el Static ID real es 'ACF_APEX_OAUTH2' (mayusculas, igual al
    -- Name) -- hubo una version intermedia en minusculas que ya no
    -- aplica. Si en algun momento se re-crea el credential, verificar
    -- el Static ID real en pantalla antes de asumir que coincide con
    -- lo que hay aca.
    l_resp := APEX_WEB_SERVICE.MAKE_REST_REQUEST(
      p_url                  => 'https://g12b41f87b2bc76-apcdb.adb.sa-bogota-1.oraclecloudapps.com/ords/acf/oauth/token',
      p_http_method          => 'POST',
      p_body                 => 'grant_type=client_credentials',
      p_credential_static_id => 'ACF_APEX_OAUTH2'
    );

    APEX_JSON.PARSE(l_resp);
    g_token  := APEX_JSON.GET_VARCHAR2(p_path => 'access_token');
    -- se resta 1 minuto de margen para evitar usar un token a punto de expirar
    g_expira := SYSTIMESTAMP + NUMTODSINTERVAL(
                  NVL(APEX_JSON.GET_NUMBER(p_path => 'expires_in'), 3600) - 60, 'SECOND'
                );

    IF g_token IS NULL THEN
      RAISE_APPLICATION_ERROR(-20001, 'No se pudo obtener el token OAuth2: ' || DBMS_LOB.SUBSTR(l_resp, 500, 1));
    END IF;

    RETURN 'Bearer ' || g_token;
  END obtener_bearer_header;

  FUNCTION descargar_acta(p_ruta VARCHAR2) RETURN BLOB IS
    l_blob BLOB;
    l_auth VARCHAR2(2000);
  BEGIN
    -- Resolver el token ANTES de tocar G_REQUEST_HEADERS. G_REQUEST_
    -- HEADERS es un array GLOBAL de APEX_WEB_SERVICE (no privado de
    -- esta funcion) -- si se arma la asignacion en dos pasos (NAME
    -- primero, VALUE := obtener_bearer_header despues) y el token
    -- cacheado ya vencio, obtener_bearer_header hace su propio DELETE +
    -- set de headers (Content-Type) para pedir el token nuevo a ORDS,
    -- pisando el NAME='Authorization' que se acababa de asignar --
    -- el header final terminaba siendo "Content-Type: Bearer <token>",
    -- sin ningun Authorization. Bug real, confirmado por Sergio: fallaba
    -- solo cuando tocaba pedir un token nuevo (sesion recien logueada),
    -- funcionaba si el token seguia cacheado de una llamada previa.
    l_auth := obtener_bearer_header;

    APEX_WEB_SERVICE.G_REQUEST_HEADERS.DELETE;
    APEX_WEB_SERVICE.G_REQUEST_HEADERS(1).NAME  := 'Authorization';
    APEX_WEB_SERVICE.G_REQUEST_HEADERS(1).VALUE := l_auth;

    l_blob := APEX_WEB_SERVICE.MAKE_REST_REQUEST_B(
      p_url         => url_backend() || '/' || p_ruta,
      p_http_method => 'GET'
    );

    IF l_blob IS NULL OR DBMS_LOB.GETLENGTH(l_blob) = 0 THEN
      RAISE_APPLICATION_ERROR(-20360, 'El backend de actas no devolvio contenido para: ' || p_ruta);
    END IF;

    RETURN l_blob;
  END descargar_acta;

END pkg_acf_client;
/
