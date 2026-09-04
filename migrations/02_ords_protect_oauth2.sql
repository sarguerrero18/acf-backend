-- ============================================================
-- PROTEGER EL MODULO ORDS 'actas' (schema ACF) CON OAUTH2
-- (client_credentials). Correr en SQL Workshop del esquema ACF,
-- DESPUES de 01_ords_setup.sql.
--
-- Mismo patron exacto que el que usa formula-engine para GTH, solo
-- cambia el nombre del modulo/rol/cliente y el schema owner.
--
-- Flujo resultante:
--   1. Node (este proyecto, acf-backend) pide un token:
--      POST /ords/acf/oauth/token
--      Authorization: Basic base64(client_id:client_secret)
--      Body: grant_type=client_credentials
--   2. ORDS responde {"access_token": "...", "expires_in": 3600, ...}
--   3. Node llama a /actas/* con: Authorization: Bearer <access_token>
-- ============================================================

-- 1. Rol que representa "quien puede usar la API de actas"
BEGIN
  ORDS.CREATE_ROLE(p_role_name => 'acf_actas_api_role');
  COMMIT;
END;
/

-- 2. Privilegio protegiendo TODO el modulo /actas/*
BEGIN
  ORDS.CREATE_PRIVILEGE(
    p_name        => 'acf.actas.api.privilege',
    p_role_name   => 'acf_actas_api_role',
    p_label       => 'Acceso API de actas (Activos Fijos)',
    p_description => 'Acceso al modulo REST de generacion de actas y reportes de Activos Fijos (backend Node acf-backend)'
  );

  ORDS.CREATE_PRIVILEGE_MAPPING(
    p_privilege_name => 'acf.actas.api.privilege',
    p_pattern        => '/actas/*'
  );
  COMMIT;
END;
/

-- 3. Cliente OAuth2 para el backend Node (maquina-a-maquina)
BEGIN
  OAUTH.CREATE_CLIENT(
    p_name            => 'acf_backend_client',
    p_grant_type      => 'client_credentials',
    p_owner           => 'ACF',
    p_description     => 'Backend Node (proyecto acf-backend) para actas y reportes de Activos Fijos',
    p_support_email   => 'soporte@tuempresa.com', -- ajustar
    p_privilege_names => 'acf.actas.api.privilege'
  );

  OAUTH.GRANT_CLIENT_ROLE(
    p_client_name => 'acf_backend_client',
    p_role_name   => 'acf_actas_api_role'
  );
  COMMIT;
END;
/

-- 4. Obtener client_id / client_secret generados (van en el .env de
--    acf-backend como ORDS_CLIENT_ID / ORDS_CLIENT_SECRET -- NUNCA
--    versionar el .env real).
SELECT name, client_id, client_secret
FROM user_ords_clients
WHERE name = 'acf_backend_client';
