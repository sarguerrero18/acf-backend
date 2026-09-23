-- ============================================================
-- Agrega los handlers de las 4 actas de ALM (Ingreso/Egreso/Traslado/
-- Devolucion) al MISMO modulo ORDS 'acf.actas' que ya usan las actas de
-- ACF (ver migrations/04_ords_actas.sql) -- se eligio EXTENDER
-- acf-backend en vez de crear un backend/ORDS separado para ALM
-- (decision de Sergio, 2026-09-23): mismo host, mismo OAuth2
-- (ACF_APEX_OAUTH2 / acf_apex_client), mismo PKG_ACF_CLIENT, un solo
-- ORDS_BASE_URL en el backend Node.
--
-- Los handlers de abajo corren en el schema ACF (mismo dueno del modulo
-- 'acf.actas'), pero consultan tablas de ALM cross-schema (ALM.ALM_*).
-- Correr PRIMERO, como usuario ALM, los GRANT que siguen (sin ellos, el
-- CREATE de este script compila pero los handlers fallan en tiempo de
-- ejecucion con ORA-00942 la primera vez que alguien pida una acta):
--
--   GRANT SELECT ON ALM_INGRESO           TO ACF;
--   GRANT SELECT ON ALM_DETALLE_INGRESO   TO ACF;
--   GRANT SELECT ON ALM_EGRESO            TO ACF;
--   GRANT SELECT ON ALM_DETALLE_EGRESO    TO ACF;
--   GRANT SELECT ON ALM_TRASLADO          TO ACF;
--   GRANT SELECT ON ALM_DETALLE_TRASLADO  TO ACF;
--   GRANT SELECT ON ALM_DEVOLUCION        TO ACF;
--   GRANT SELECT ON ALM_DETALLE_DEVOLUCION TO ACF;
--   GRANT SELECT ON ALM_CATALOGO          TO ACF;
--   GRANT SELECT ON ALM_TIPO_MOVIMIENTO   TO ACF;
--
-- Correr DESPUES este script, como usuario ACF (SQL Workshop, schema ACF
-- -- mismo usuario que corrio migrations/04_ords_actas.sql).
--
-- Ademas, la pagina 36 de ALM (proxy de descarga, clonada de la pagina
-- 36 de ACF) llama a `pkg_acf_client.descargar_acta` -- ese paquete
-- vive en el schema ACF, no en ALM, asi que hacen falta 2 ajustes en
-- ALM (fuera del alcance de este script SQL):
--   1) GRANT EXECUTE ON ACF.PKG_ACF_CLIENT TO ALM;  (correr como ACF)
--   2) En el proceso PL/SQL de la pagina 36 de ALM, calificar la
--      llamada como ACF.PKG_ACF_CLIENT.DESCARGAR_ACTA(l_ruta) en vez de
--      pkg_acf_client.descargar_acta(l_ruta) (sin calificar, ALM no
--      encuentra el paquete -- son schemas distintos).
-- ============================================================

BEGIN

  ------------------------------------------------------------
  -- ALM INGRESO
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'alm_ingreso-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'alm_ingreso-cabecera',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        I.ID AS id, I.CLIENTE_ID AS cliente_id, I.ENTIDAD_ID AS entidad_id,
        I.CONSECUTIVO AS consecutivo, I.ESTADO AS estado,
        I.FECHA_INGRESO AS fecha_ingreso, I.FECHA_APROBACION AS fecha_aprobacion,
        I.USUARIO_APROBACION AS usuario_aprobacion,
        I.FECHA_CREACION AS fecha_creacion, I.FECHA_MODIFICACION AS fecha_modificacion,
        I.TIPO_DOC_SOPORTE AS tipo_doc_soporte, I.NUMERO_DOC_SOPORTE AS numero_doc_soporte,
        I.FECHA_DOC_SOPORTE AS fecha_doc_soporte, I.OBSERVACIONES AS observaciones,
        TM.DESC_TIPO_MOVIMIENTO AS desc_tipo_movimiento,
        PK_GENERAL.fn_nombre_cliente(I.CLIENTE_ID) AS nombre_cliente,
        PK_GENERAL.fn_nombre_entidad(I.ENTIDAD_ID) AS nombre_entidad,
        GE.LOGO_ENTIDAD AS logo_entidad, GE.LOGO_MIME_TYPE AS logo_mime_type,
        GE.LOGO_FILENAME AS logo_filename,
        PK_GENERAL.fn_nombre_tercero(I.PROVEEDOR_ID) AS nombre_proveedor,
        I.FUNCIONARIO_ENTREGA_ID AS funcionario_entrega_id,
        PK_GENERAL.fn_nombre_tercero(I.FUNCIONARIO_ENTREGA_ID) AS nombre_entrega,
        PK_GENERAL.fn_nombre_dependencia(I.DEPENDENCIA_ENTREGA_ID) AS nombre_dep_entrega,
        CASE WHEN EXISTS (
          SELECT 1 FROM ACF_ALMACENISTA AA
          WHERE AA.FUNCIONARIO_ID = I.FUNCIONARIO_ENTREGA_ID
            AND AA.CLIENTE_ID = I.CLIENTE_ID AND AA.ENTIDAD_ID = I.ENTIDAD_ID
            AND AA.ESTADO = 'ACTIVO'
        ) THEN 1 ELSE 0 END AS es_almacenista_entrega,
        I.FUNCIONARIO_RECIBE_ID AS funcionario_recibe_id,
        PK_GENERAL.fn_nombre_tercero(I.FUNCIONARIO_RECIBE_ID) AS nombre_recibe,
        PK_GENERAL.fn_nombre_dependencia(I.DEPENDENCIA_RECIBE_ID) AS nombre_dep_recibe,
        CASE WHEN EXISTS (
          SELECT 1 FROM ACF_ALMACENISTA AA
          WHERE AA.FUNCIONARIO_ID = I.FUNCIONARIO_RECIBE_ID
            AND AA.CLIENTE_ID = I.CLIENTE_ID AND AA.ENTIDAD_ID = I.ENTIDAD_ID
            AND AA.ESTADO = 'ACTIVO'
        ) THEN 1 ELSE 0 END AS es_almacenista_recibe
      FROM ALM.ALM_INGRESO I
      JOIN ALM.ALM_TIPO_MOVIMIENTO TM ON TM.ID = I.TIPO_INGRESO_ID
      JOIN GEN_ENTIDAD GE            ON GE.ID = I.ENTIDAD_ID
      WHERE I.ID = :id
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'alm_ingreso-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'alm_ingreso-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        DI.ID AS detalle_id, C.DESCRIPCION AS descripcion,
        DI.CANTIDAD AS cantidad, DI.UNIDAD_MEDIDA AS unidad_medida,
        DI.VALOR_UNITARIO AS valor_unitario, DI.VALOR_TOTAL AS valor_total
      FROM ALM.ALM_DETALLE_INGRESO DI
      JOIN ALM.ALM_CATALOGO C ON C.ID = DI.CATALOGO_ID
      WHERE DI.INGRESO_ID = :id
      ORDER BY DI.ID
    ]'
  );

  ------------------------------------------------------------
  -- ALM EGRESO
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'alm_egreso-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'alm_egreso-cabecera',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        E.ID AS id, E.CLIENTE_ID AS cliente_id, E.ENTIDAD_ID AS entidad_id,
        E.CONSECUTIVO AS consecutivo, E.ESTADO AS estado,
        E.FECHA_EGRESO AS fecha_egreso, E.FECHA_APROBACION AS fecha_aprobacion,
        E.USUARIO_APROBACION AS usuario_aprobacion,
        E.FECHA_CREACION AS fecha_creacion, E.FECHA_MODIFICACION AS fecha_modificacion,
        E.OBSERVACIONES AS observaciones,
        TM.DESC_TIPO_MOVIMIENTO AS desc_tipo_movimiento,
        PK_GENERAL.fn_nombre_cliente(E.CLIENTE_ID) AS nombre_cliente,
        PK_GENERAL.fn_nombre_entidad(E.ENTIDAD_ID) AS nombre_entidad,
        GE.LOGO_ENTIDAD AS logo_entidad, GE.LOGO_MIME_TYPE AS logo_mime_type,
        GE.LOGO_FILENAME AS logo_filename,
        PK_GENERAL.fn_nombre_dependencia(E.DEPENDENCIA_DESTINO_ID) AS nombre_dep_destino,
        E.FUNCIONARIO_DESTINO_ID AS funcionario_destino_id,
        PK_GENERAL.fn_nombre_tercero(E.FUNCIONARIO_DESTINO_ID) AS nombre_destino,
        CASE WHEN EXISTS (
          SELECT 1 FROM ACF_ALMACENISTA AA
          WHERE AA.FUNCIONARIO_ID = E.FUNCIONARIO_DESTINO_ID
            AND AA.CLIENTE_ID = E.CLIENTE_ID AND AA.ENTIDAD_ID = E.ENTIDAD_ID
            AND AA.ESTADO = 'ACTIVO'
        ) THEN 1 ELSE 0 END AS es_almacenista_destino
      FROM ALM.ALM_EGRESO E
      JOIN ALM.ALM_TIPO_MOVIMIENTO TM ON TM.ID = E.TIPO_EGRESO_ID
      JOIN GEN_ENTIDAD GE             ON GE.ID = E.ENTIDAD_ID
      WHERE E.ID = :id
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'alm_egreso-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'alm_egreso-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        DE.ID AS detalle_id, C.DESCRIPCION AS descripcion,
        DE.CANTIDAD_SOLICITADA AS cantidad_solicitada,
        DE.CANTIDAD_ENTREGADA AS cantidad_entregada,
        DE.UNIDAD_MEDIDA AS unidad_medida,
        DE.VALOR_UNITARIO AS valor_unitario, DE.VALOR_TOTAL AS valor_total
      FROM ALM.ALM_DETALLE_EGRESO DE
      JOIN ALM.ALM_CATALOGO C ON C.ID = DE.CATALOGO_ID
      WHERE DE.EGRESO_ID = :id
      ORDER BY DE.ID
    ]'
  );

  ------------------------------------------------------------
  -- ALM TRASLADO
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'alm_traslado-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'alm_traslado-cabecera',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        T.ID AS id, T.CLIENTE_ID AS cliente_id, T.ENTIDAD_ID AS entidad_id,
        T.CONSECUTIVO AS consecutivo, T.ESTADO AS estado,
        T.FECHA_TRASLADO AS fecha_traslado, T.FECHA_APROBACION AS fecha_aprobacion,
        T.USUARIO_APROBACION AS usuario_aprobacion,
        T.FECHA_CREACION AS fecha_creacion, T.FECHA_MODIFICACION AS fecha_modificacion,
        T.OBSERVACIONES AS observaciones,
        TM.DESC_TIPO_MOVIMIENTO AS desc_tipo_movimiento,
        PK_GENERAL.fn_nombre_cliente(T.CLIENTE_ID) AS nombre_cliente,
        PK_GENERAL.fn_nombre_entidad(T.ENTIDAD_ID) AS nombre_entidad,
        GE.LOGO_ENTIDAD AS logo_entidad, GE.LOGO_MIME_TYPE AS logo_mime_type,
        GE.LOGO_FILENAME AS logo_filename,
        PK_GENERAL.fn_nombre_dependencia(T.DEPENDENCIA_ORIGEN_ID) AS nombre_dep_origen,
        PK_GENERAL.fn_nombre_dependencia(T.DEPENDENCIA_DESTINO_ID) AS nombre_dep_destino
      FROM ALM.ALM_TRASLADO T
      JOIN ALM.ALM_TIPO_MOVIMIENTO TM ON TM.ID = T.TIPO_TRASLADO_ID
      JOIN GEN_ENTIDAD GE             ON GE.ID = T.ENTIDAD_ID
      WHERE T.ID = :id
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'alm_traslado-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'alm_traslado-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        DT.ID AS detalle_id, C.DESCRIPCION AS descripcion,
        DT.CANTIDAD AS cantidad, DT.UNIDAD_MEDIDA AS unidad_medida
      FROM ALM.ALM_DETALLE_TRASLADO DT
      JOIN ALM.ALM_CATALOGO C ON C.ID = DT.CATALOGO_ID
      WHERE DT.TRASLADO_ID = :id
      ORDER BY DT.ID
    ]'
  );

  ------------------------------------------------------------
  -- ALM DEVOLUCION
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'alm_devolucion-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'alm_devolucion-cabecera',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        V.ID AS id, V.CLIENTE_ID AS cliente_id, V.ENTIDAD_ID AS entidad_id,
        V.CONSECUTIVO AS consecutivo, V.ESTADO AS estado,
        V.FECHA_DEVOLUCION AS fecha_devolucion, V.FECHA_APROBACION AS fecha_aprobacion,
        V.USUARIO_APROBACION AS usuario_aprobacion,
        V.FECHA_CREACION AS fecha_creacion, V.FECHA_MODIFICACION AS fecha_modificacion,
        V.OBSERVACIONES AS observaciones, V.MOTIVO AS motivo,
        TM.DESC_TIPO_MOVIMIENTO AS desc_tipo_movimiento,
        PK_GENERAL.fn_nombre_cliente(V.CLIENTE_ID) AS nombre_cliente,
        PK_GENERAL.fn_nombre_entidad(V.ENTIDAD_ID) AS nombre_entidad,
        GE.LOGO_ENTIDAD AS logo_entidad, GE.LOGO_MIME_TYPE AS logo_mime_type,
        GE.LOGO_FILENAME AS logo_filename,
        PK_GENERAL.fn_nombre_dependencia(V.DEPENDENCIA_ORIGEN_ID) AS nombre_dep_origen
      FROM ALM.ALM_DEVOLUCION V
      JOIN ALM.ALM_TIPO_MOVIMIENTO TM ON TM.ID = V.TIPO_DEVOLUCION_ID
      JOIN GEN_ENTIDAD GE             ON GE.ID = V.ENTIDAD_ID
      WHERE V.ID = :id
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'alm_devolucion-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'alm_devolucion-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        DV.ID AS detalle_id, C.DESCRIPCION AS descripcion,
        DV.CANTIDAD AS cantidad, DV.UNIDAD_MEDIDA AS unidad_medida
      FROM ALM.ALM_DETALLE_DEVOLUCION DV
      JOIN ALM.ALM_CATALOGO C ON C.ID = DV.CATALOGO_ID
      WHERE DV.DEVOLUCION_ID = :id
      ORDER BY DV.ID
    ]'
  );

  COMMIT;
END;
/

-- Verificar que quedaron registrados:
SELECT p_pattern FROM user_ords_templates
 WHERE p_module_name = 'acf.actas' AND p_pattern LIKE 'alm_%'
 ORDER BY 1;
