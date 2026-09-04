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
-- Confirmar y ajustar si no es el caso. La URL de url_backend() es
-- PLACEHOLDER hasta que acf-backend tenga su propio deploy (Render u
-- otro) -- ajustar cuando exista.
-- ============================================================

CREATE OR REPLACE PACKAGE pkg_acf_client AS

  /** URL base del backend Node de ACF (acf-backend) una vez desplegado.
   *  PLACEHOLDER -- reemplazar cuando exista el deploy real. */
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
    RETURN 'https://PENDIENTE-deploy-acf-backend.onrender.com'; -- *** ajustar al desplegar
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
  BEGIN
    APEX_WEB_SERVICE.G_REQUEST_HEADERS.DELETE;
    APEX_WEB_SERVICE.G_REQUEST_HEADERS(1).NAME  := 'Authorization';
    APEX_WEB_SERVICE.G_REQUEST_HEADERS(1).VALUE := obtener_bearer_header;

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
