-- ============================================================
-- Cliente OAuth2 para APEX (distinto al que usa Node para llamar a
-- ORDS). Reutiliza el MISMO rol/privilegio ya creado en
-- 02_ords_protect_oauth2.sql (acf_actas_api_role /
-- acf.actas.api.privilege sobre /actas/*) -- no hace falta crear un
-- privilegio nuevo, solo un cliente OAuth2 nuevo con ese rol.
--
-- Correr en SQL Workshop del esquema ACF. Mismo patron exacto que usa
-- formula-engine para GTH (nomina_apex_client).
-- ============================================================

BEGIN
  OAUTH.CREATE_CLIENT(
    p_name            => 'acf_apex_client',
    p_grant_type      => 'client_credentials',
    p_owner           => 'ACF',
    p_description     => 'Cliente OAuth2 para que APEX (app 104) llame al backend Node (acf-backend)',
    p_support_email   => 'soporte@tuempresa.com', -- ajustar
    p_privilege_names => 'acf.actas.api.privilege'
  );

  OAUTH.GRANT_CLIENT_ROLE(
    p_client_name => 'acf_apex_client',
    p_role_name   => 'acf_actas_api_role'
  );
  COMMIT;
END;
/

-- Consultar client_id / client_secret generados. Estos van en APEX
-- (Shared Components -> Web Credentials, Workspace GEN -- mismo
-- workspace donde ya vive NOMINA_APEX_OAUTH2), en un Web Credential
-- nuevo llamado ACF_APEX_OAUTH2, Authentication Type = Basic
-- Authentication.
SELECT name, client_id, client_secret
FROM user_ords_clients
WHERE name = 'acf_apex_client';
