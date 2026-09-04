-- ============================================================
-- Habilita ORDS (RESTful Services) sobre el schema ACF.
-- Correr en SQL Workshop del esquema ACF (o SQLcl conectado como ACF).
--
-- Mismo mecanismo ya usado para el schema GTH en el backend de nomina
-- (formula-engine) -- GTH y ACF viven en la MISMA Autonomous Database
-- (mismo host que ya usa pkg_nomina_client.sql:
-- g12b41f87b2bc76-apcdb.adb.sa-bogota-1.oraclecloudapps.com), asi que
-- ORDS ya esta activo a nivel de instancia; lo que falta es habilitar
-- especificamente el schema ACF (opt-in por schema).
--
-- p_url_mapping_pattern => 'acf' deja las rutas como
-- https://<host>/ords/acf/<modulo>/... -- paralelo a /ords/gth/... que
-- ya usa GTH.
--
-- *** SUPUESTO A VALIDAR: que ACF y GTH son en efecto el mismo host/
-- instancia de Autonomous Database. Si no lo son, el resto de este
-- script sigue sirviendo igual, solo cambia el host que se usa en
-- deploy/pkg_acf_client.sql.
-- ============================================================

BEGIN
  ORDS.ENABLE_SCHEMA(
    p_enabled              => TRUE,
    p_url_mapping_type     => 'BASE_PATH',
    p_url_mapping_pattern  => 'acf',
    p_auto_rest_auth       => FALSE
  );
  COMMIT;
END;
/

-- Verificar que quedo habilitado:
SELECT rest_enabled, url_mapping_pattern
  FROM user_ords_schemas;
