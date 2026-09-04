-- ============================================================
-- Endpoints ORDS del modulo 'acf.actas' -- correr en SQL Workshop
-- del esquema ACF, DESPUES de 01/02/03_ords_*.sql.
--
-- Cabecera + detalle para las 4 actas (Ingreso, Traslado, Egreso,
-- Depreciacion) + un endpoint barato de salud usado por
-- src/http/verificarTokenApex.ts (acf-backend) para validar el
-- Bearer token que manda APEX.
--
-- IMPORTANTE: todas las columnas se alias explicitamente en
-- minuscula. ORDS/AutoREST refleja el nombre del alias tal cual en
-- el JSON -- sin el alias, Oracle devuelve el nombre de columna en
-- MAYUSCULA por default y el JSON saldria con llaves en mayuscula,
-- que no calzarian con los interfaces TypeScript (snake_case en
-- minuscula) de src/repositorios/actasRepo.ts. Mismo criterio ya
-- usado en formula-engine/migrations/08_ords_comprobante.sql.
--
-- Resolucion de nombre de funcionario -- ACLARADO por Sergio (ya NO es
-- un supuesto): ACF_INGRESO.FUNCIONARIO_ENTREGA_ID/FUNCIONARIO_RECIBE_ID,
-- ACF_TRASLADO.FUNCIONARIO_ORIGEN_ID/FUNCIONARIO_DESTINO_ID,
-- ACF_EGRESO.RESPONSABLE_ID y ACF_FIRMANTE.FUNCIONARIO_ID guardan
-- GTH_FUNCIONARIOS.ID (la fila del funcionario), NO el id de tercero
-- directo. Para el nombre hace falta el join intermedio: la columna
-- GTH_FUNCIONARIOS.FUNCIONARIO_ID (dentro de esa misma tabla) es la que
-- referencia a GEN_PERSONA, y es lo que se le pasa a fn_nombre_tercero.
-- Patron en cada query: LEFT JOIN GTH_FUNCIONARIOS GF ON GF.ID = <FK> y
-- luego PK_GENERAL.fn_nombre_tercero(GF.FUNCIONARIO_ID). LEFT JOIN (no
-- JOIN) porque estas columnas son nullable en varios de los tipos.
--
-- Nota: PROVEEDOR_ID (Ingreso) y TERCERO_ID (Traslado, comodato) SI son
-- referencia directa a GEN_PERSONA (asi quedo documentado desde el
-- DDL original) -- esos dos se resuelven con fn_nombre_tercero directo,
-- sin pasar por GTH_FUNCIONARIOS.
--
-- CORRECCION (ORA-01775 al probar): ACF_INGRESO.TIPO_INGRESO_ID ya NO
-- referencia a la tabla ACF_TIPO_INGRESO (existio al inicio del
-- desarrollo del modulo, se elimino cuando todo paso a usar
-- ACF_TIPO_MOVIMIENTO) -- el DDL real de ACF_INGRESO que compartio
-- Sergio confirma que no hay FK a ACF_TIPO_INGRESO. El nombre de la
-- columna se quedo igual (TIPO_INGRESO_ID) pero ahora apunta a
-- ACF_TIPO_MOVIMIENTO.ID, mismo patron que TIPO_TRASLADO_ID/
-- TIPO_EGRESO_ID/TIPO_DEPRECIACION_ID. ingreso-cabecera se corrigio
-- para hacer JOIN ACF_TIPO_MOVIMIENTO TM ON TM.ID = I.TIPO_INGRESO_ID
-- (en vez de JOIN ACF_TIPO_INGRESO), igual que las otras 3 actas.
--
-- CORRECCION en depreciacion-detalle: las columnas de ACF_HISTORICO_
-- DEPRECIACION que se usaron al principio (VIDA_UTIL_ANTES/DESPUES,
-- VALOR_ALICUOTA, VALOR_DEPRECIADO_ANTES/DESPUES, VALOR_LIBROS_DESPUES)
-- eran en realidad las de OTRA tabla (ACF_DETALLE_DEPRECIACION) --
-- nunca se tuvo a la vista el DDL real de ACF_HISTORICO_DEPRECIACION.
-- Sergio compartio el query correcto con las columnas reales:
-- VIDA_UTIL_ACTUAL, DIAS_DEPRECIADOS, VIDA_UTIL_NUEVA,
-- VALOR_ANTES_DEPRECIACION, VALOR_DEPRECIADO, VALOR_NUEVO_BIEN.
--
-- QUINTA CORRECCION: etiqueta "(almacenista)" en las firmas de Ingreso
-- estaba HARDCODEADA siempre sobre el rol "Entrega" (generarActaIngreso.ts),
-- sin verificar nada -- Sergio detecto que en la practica el almacenista
-- suele ser quien RECIBE (bodega), no quien entrega, asi que la etiqueta
-- salia en la persona equivocada. Se corrigio para que sea dinamico,
-- consultando ACF_ALMACENISTA (DDL real compartido por Sergio:
-- ID/CLIENTE_ID/ENTIDAD_ID/FUNCIONARIO_ID/FECHA_INICIAL/FECHA_FINAL/
-- ESTADO). Se agrego un flag es_almacenista_<rol> (0/1) a
-- ingreso-cabecera, traslado-cabecera y egreso-cabecera, via EXISTS
-- contra ACF_ALMACENISTA con ESTADO='ACTIVO', y el generador de PDF
-- decide la etiqueta segun ese flag en vez de hardcodearla.
--
-- *** SUPUESTO A VALIDAR: se asume que ACF_ALMACENISTA.FUNCIONARIO_ID
-- guarda GTH_FUNCIONARIOS.ID (igual patron que TODAS las demas columnas
-- FUNCIONARIO_ID de este modulo: ACF_INGRESO, ACF_TRASLADO, ACF_EGRESO,
-- ACF_FIRMANTE) -- por eso se compara directo contra la columna FK
-- (I.FUNCIONARIO_ENTREGA_ID, etc.), SIN pasar por el join intermedio a
-- GTH_FUNCIONARIOS.FUNCIONARIO_ID que si hace falta para resolver el
-- NOMBRE. No confirmado explicitamente por Sergio para esta tabla en
-- particular -- si el flag sale siempre en 0 (o siempre en 1) contra
-- datos donde se sabe que deberia ser lo contrario, revisar este
-- supuesto primero.
--
-- SEXTA ADICION: acta de Comite de Bajas (2026-09-04). DDL real
-- compartida por Sergio para ACF_COMITE_BAJA (ID/CLIENTE_ID/ENTIDAD_ID/
-- VIGENCIA/CONSECUTIVO/NUMERO_ACTA/FECHA_COMITE/ESTADO IN
-- ('ELABORADO','APROBADO') -- OJO, sin ANULADO, a diferencia de las
-- otras 4 actas). CORRECCION del mismo dia: la version inicial de
-- ACF_COMITE_BAJA no tenia FECHA_APROBACION/USUARIO_APROBACION --
-- Sergio las agrego (con la validacion FECHA_APROBACION >=
-- FECHA_COMITE resuelta en PR_APROBAR_COMITE_BAJA, no en este query) y
-- ahora comite-cabecera las selecciona igual que las otras 4 actas.
-- FECHA_COMITE (el dia real del comite) y FECHA_APROBACION (el tramite,
-- que puede ser posterior) se muestran ambas en el acta.
--
-- ACF_COMITE_BAJA_DETALLE (COMITE_BAJA_ID/ACTIVO_FIJO_ID/DIAGNOSTICO/
-- TIPO_EGRESO_SUGERIDO_ID -> FK a ACF_TIPO_MOVIMIENTO/DECISION/
-- EGRESO_ID -> FK a ACF_EGRESO, nullable hasta que se ejecute la
-- decision/OBSERVACIONES). Firmantes: ACF_FIRMANTE.TIPO_DOCUMENTO =
-- 'COMITE_BAJA' ya existia como valor permitido y ya tiene datos reales
-- (ALMACENISTA orden 1 + CONTADOR orden 2, mismo patron que
-- Depreciacion) -- a diferencia de depreciacion-firmantes, comite-
-- firmantes NO restringe por ROL (el check constraint de ACF_FIRMANTE
-- permite tambien 'OTRO', pensado para mas miembros de comite a
-- futuro).
--
-- *** SUPUESTO A VALIDAR restante (probar con datos reales y corregir
-- si hace falta):
--
-- 1. Fecha que acompana la marca de agua (fecha en que el movimiento
--    alcanzo su ESTADO actual): no se tiene la estructura exacta de
--    ACF_HISTORICO_ESTADO_* (tablas AIU de v46/47/48), asi que por
--    ahora se resuelve del lado de Node/pdfkit con las columnas ya
--    conocidas del propio encabezado: ELABORADO -> fecha_creacion,
--    APROBADO -> fecha_aprobacion, ANULADO -> fecha_modificacion
--    (proxy, no hay columna propia de fecha de anulacion). Si se
--    quiere precision real habria que resolver contra el historico --
--    pendiente confirmar su estructura con Sergio.
-- ============================================================

BEGIN
  ------------------------------------------------------------
  -- Modulo ORDS 'acf.actas' -- FALTABA este paso (se omitio al armar
  -- este script; en formula-engine/GTH el modulo 'nomina.api' ya
  -- existia de un script previo ya aplicado, historial_ya_aplicado/
  -- ords_setup.sql, que no se replico aca). DEFINE_TEMPLATE/
  -- DEFINE_HANDLER fallan con ORA-01403 si el modulo no existe todavia
  -- -- por eso se crea primero, antes de cualquier DEFINE_TEMPLATE.
  -- La proteccion real del modulo (OAuth2) ya quedo resuelta en
  -- 02_ords_protect_oauth2.sql via CREATE_PRIVILEGE_MAPPING sobre el
  -- patron '/actas/*' -- no hace falta p_priv_group aca.
  ------------------------------------------------------------
  ORDS.DEFINE_MODULE(
    p_module_name    => 'acf.actas',
    p_base_path      => '/actas/',
    p_items_per_page => 0,
    p_status         => 'PUBLISHED',
    p_comments       => 'API de actas de Activos Fijos -- consumida por el backend Node (acf-backend)'
  );

  ------------------------------------------------------------
  -- Salud (usado solo para validar el Bearer token de APEX)
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'health-check');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'health-check',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[SELECT 'ok' AS status FROM dual]'
  );

  ------------------------------------------------------------
  -- INGRESO
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'ingreso-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'ingreso-cabecera',
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
        PK_GENERAL.fn_nombre_tercero(GF_ENTREGA.FUNCIONARIO_ID) AS nombre_entrega,
        PK_GENERAL.fn_nombre_dependencia(I.DEPENDENCIA_ENTREGA_ID) AS nombre_dep_entrega,
        CASE WHEN EXISTS (
          SELECT 1 FROM ACF_ALMACENISTA ALM
          WHERE ALM.FUNCIONARIO_ID = I.FUNCIONARIO_ENTREGA_ID
            AND ALM.CLIENTE_ID = I.CLIENTE_ID AND ALM.ENTIDAD_ID = I.ENTIDAD_ID
            AND ALM.ESTADO = 'ACTIVO'
        ) THEN 1 ELSE 0 END AS es_almacenista_entrega,
        I.FUNCIONARIO_RECIBE_ID AS funcionario_recibe_id,
        PK_GENERAL.fn_nombre_tercero(GF_RECIBE.FUNCIONARIO_ID) AS nombre_recibe,
        PK_GENERAL.fn_nombre_dependencia(I.DEPENDENCIA_RECIBE_ID) AS nombre_dep_recibe,
        CASE WHEN EXISTS (
          SELECT 1 FROM ACF_ALMACENISTA ALM
          WHERE ALM.FUNCIONARIO_ID = I.FUNCIONARIO_RECIBE_ID
            AND ALM.CLIENTE_ID = I.CLIENTE_ID AND ALM.ENTIDAD_ID = I.ENTIDAD_ID
            AND ALM.ESTADO = 'ACTIVO'
        ) THEN 1 ELSE 0 END AS es_almacenista_recibe
      FROM ACF_INGRESO I
      JOIN ACF_TIPO_MOVIMIENTO TM ON TM.ID = I.TIPO_INGRESO_ID
      JOIN GEN_ENTIDAD GE      ON GE.ID = I.ENTIDAD_ID
      LEFT JOIN GTH_FUNCIONARIOS GF_ENTREGA ON GF_ENTREGA.ID = I.FUNCIONARIO_ENTREGA_ID
      LEFT JOIN GTH_FUNCIONARIOS GF_RECIBE  ON GF_RECIBE.ID = I.FUNCIONARIO_RECIBE_ID
      WHERE I.ID = :id
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'ingreso-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'ingreso-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        AF.ID AS activo_fijo_id, AF.NUMERO_PLACA AS numero_placa,
        C.DESCRIPCION AS descripcion,
        AF.MARCA AS marca, AF.REFERENCIA AS referencia, AF.MODELO AS modelo,
        AF.SERIAL AS serial, AF.ESTADO AS estado,
        AF.VALOR AS valor, AF.VALOR_IVA AS valor_iva, AF.VALOR_TOTAL AS valor_total
      FROM ACF_ACTIVOS_FIJOS AF
      JOIN ACF_CATALOGO C ON C.ID = AF.CATALOGO_ID
      WHERE AF.INGRESO_ID = :id
      ORDER BY AF.NUMERO_PLACA
    ]'
  );

  ------------------------------------------------------------
  -- TRASLADO
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'traslado-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'traslado-cabecera',
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
        T.UBICACION_ORIGEN AS ubicacion_origen, T.FUNCIONARIO_ORIGEN_ID AS funcionario_origen_id,
        PK_GENERAL.fn_nombre_tercero(GF_ORIGEN.FUNCIONARIO_ID) AS nombre_origen,
        PK_GENERAL.fn_nombre_dependencia(T.DEPENDENCIA_ORIGEN_ID) AS nombre_dep_origen,
        CASE WHEN EXISTS (
          SELECT 1 FROM ACF_ALMACENISTA ALM
          WHERE ALM.FUNCIONARIO_ID = T.FUNCIONARIO_ORIGEN_ID
            AND ALM.CLIENTE_ID = T.CLIENTE_ID AND ALM.ENTIDAD_ID = T.ENTIDAD_ID
            AND ALM.ESTADO = 'ACTIVO'
        ) THEN 1 ELSE 0 END AS es_almacenista_origen,
        T.UBICACION_DESTINO AS ubicacion_destino, T.FUNCIONARIO_DESTINO_ID AS funcionario_destino_id,
        PK_GENERAL.fn_nombre_tercero(GF_DESTINO.FUNCIONARIO_ID) AS nombre_destino,
        PK_GENERAL.fn_nombre_dependencia(T.DEPENDENCIA_DESTINO_ID) AS nombre_dep_destino,
        CASE WHEN EXISTS (
          SELECT 1 FROM ACF_ALMACENISTA ALM
          WHERE ALM.FUNCIONARIO_ID = T.FUNCIONARIO_DESTINO_ID
            AND ALM.CLIENTE_ID = T.CLIENTE_ID AND ALM.ENTIDAD_ID = T.ENTIDAD_ID
            AND ALM.ESTADO = 'ACTIVO'
        ) THEN 1 ELSE 0 END AS es_almacenista_destino,
        PK_GENERAL.fn_nombre_tercero(T.TERCERO_ID) AS nombre_tercero_comodato
      FROM ACF_TRASLADO T
      JOIN ACF_TIPO_MOVIMIENTO TM ON TM.ID = T.TIPO_TRASLADO_ID
      JOIN GEN_ENTIDAD GE         ON GE.ID = T.ENTIDAD_ID
      LEFT JOIN GTH_FUNCIONARIOS GF_ORIGEN  ON GF_ORIGEN.ID = T.FUNCIONARIO_ORIGEN_ID
      LEFT JOIN GTH_FUNCIONARIOS GF_DESTINO ON GF_DESTINO.ID = T.FUNCIONARIO_DESTINO_ID
      WHERE T.ID = :id
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'traslado-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'traslado-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        AF.ID AS activo_fijo_id, AF.NUMERO_PLACA AS numero_placa,
        C.DESCRIPCION AS descripcion,
        AF.MARCA AS marca, AF.REFERENCIA AS referencia, AF.MODELO AS modelo,
        AF.SERIAL AS serial, AF.ESTADO AS estado, AF.VALOR AS valor
      FROM ACF_DETALLE_TRASLADO DT
      JOIN ACF_ACTIVOS_FIJOS AF ON AF.ID = DT.ACTIVO_FIJO_ID
      JOIN ACF_CATALOGO C       ON C.ID = AF.CATALOGO_ID
      WHERE DT.TRASLADO_ID = :id
      ORDER BY AF.NUMERO_PLACA
    ]'
  );

  ------------------------------------------------------------
  -- EGRESO (una sola firma: RESPONSABLE_ID)
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'egreso-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'egreso-cabecera',
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
        E.VALOR_A_RESARCIR AS valor_a_resarcir, E.OBSERVACIONES AS observaciones,
        TM.DESC_TIPO_MOVIMIENTO AS desc_tipo_movimiento,
        PK_GENERAL.fn_nombre_cliente(E.CLIENTE_ID) AS nombre_cliente,
        PK_GENERAL.fn_nombre_entidad(E.ENTIDAD_ID) AS nombre_entidad,
        GE.LOGO_ENTIDAD AS logo_entidad, GE.LOGO_MIME_TYPE AS logo_mime_type,
        GE.LOGO_FILENAME AS logo_filename,
        E.RESPONSABLE_ID AS responsable_id,
        PK_GENERAL.fn_nombre_tercero(GF_RESP.FUNCIONARIO_ID) AS nombre_responsable,
        CASE WHEN EXISTS (
          SELECT 1 FROM ACF_ALMACENISTA ALM
          WHERE ALM.FUNCIONARIO_ID = E.RESPONSABLE_ID
            AND ALM.CLIENTE_ID = E.CLIENTE_ID AND ALM.ENTIDAD_ID = E.ENTIDAD_ID
            AND ALM.ESTADO = 'ACTIVO'
        ) THEN 1 ELSE 0 END AS es_almacenista_responsable
      FROM ACF_EGRESO E
      JOIN ACF_TIPO_MOVIMIENTO TM ON TM.ID = E.TIPO_EGRESO_ID
      JOIN GEN_ENTIDAD GE         ON GE.ID = E.ENTIDAD_ID
      LEFT JOIN GTH_FUNCIONARIOS GF_RESP ON GF_RESP.ID = E.RESPONSABLE_ID
      WHERE E.ID = :id
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'egreso-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'egreso-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        AF.ID AS activo_fijo_id, AF.NUMERO_PLACA AS numero_placa,
        C.DESCRIPCION AS descripcion,
        AF.MARCA AS marca, AF.REFERENCIA AS referencia, AF.MODELO AS modelo,
        AF.SERIAL AS serial,
        AF.VALOR AS valor, AF.VALOR_DEPRECIADO AS valor_depreciado
      FROM ACF_DETALLE_EGRESO DE
      JOIN ACF_ACTIVOS_FIJOS AF ON AF.ID = DE.ACTIVO_FIJO_ID
      JOIN ACF_CATALOGO C       ON C.ID = AF.CATALOGO_ID
      WHERE DE.EGRESO_ID = :id
      ORDER BY AF.NUMERO_PLACA
    ]'
  );

  ------------------------------------------------------------
  -- DEPRECIACION (firmantes: almacenista + contador via ACF_FIRMANTE)
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'depreciacion-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'depreciacion-cabecera',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        D.ID AS id, D.CLIENTE_ID AS cliente_id, D.ENTIDAD_ID AS entidad_id,
        D.CONSECUTIVO AS consecutivo, D.ESTADO AS estado,
        D.FECHA_GENERACION AS fecha_generacion, D.FECHA_APROBACION AS fecha_aprobacion,
        D.USUARIO_APROBACION AS usuario_aprobacion,
        D.FECHA_CREACION AS fecha_creacion, D.FECHA_MODIFICACION AS fecha_modificacion,
        D.NUMERO_DOCUMENTO_SOPORTE AS numero_documento_soporte,
        D.FECHA_DOCUMENTO_SOPORTE AS fecha_documento_soporte,
        D.OBSERVACIONES AS observaciones,
        P.ANIO AS anio, P.MES AS mes,
        PK_GENERAL.fn_nombre_cliente(D.CLIENTE_ID) AS nombre_cliente,
        PK_GENERAL.fn_nombre_entidad(D.ENTIDAD_ID) AS nombre_entidad,
        GE.LOGO_ENTIDAD AS logo_entidad, GE.LOGO_MIME_TYPE AS logo_mime_type,
        GE.LOGO_FILENAME AS logo_filename
      FROM ACF_DEPRECIACION D
      JOIN ACF_PERIODO P  ON P.ID = D.PERIODO_ID
      JOIN GEN_ENTIDAD GE ON GE.ID = D.ENTIDAD_ID
      WHERE D.ID = :id
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'depreciacion-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'depreciacion-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        AF.NUMERO_PLACA AS numero_placa, C.DESCRIPCION AS descripcion,
        HD.VIDA_UTIL_ACTUAL AS vida_util_actual, HD.DIAS_DEPRECIADOS AS dias_depreciados,
        HD.VIDA_UTIL_NUEVA AS vida_util_nueva,
        HD.VALOR_ANTES_DEPRECIACION AS valor_antes_depreciacion,
        HD.VALOR_DEPRECIADO AS valor_depreciado,
        HD.VALOR_NUEVO_BIEN AS valor_nuevo_bien
      FROM ACF_HISTORICO_DEPRECIACION HD
      JOIN ACF_ACTIVOS_FIJOS AF ON AF.ID = HD.ACTIVO_FIJO_ID
      JOIN ACF_CATALOGO C       ON C.ID = AF.CATALOGO_ID
      WHERE HD.DEPRECIACION_ID = :id
      ORDER BY AF.NUMERO_PLACA
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'depreciacion-firmantes');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'depreciacion-firmantes',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        F.ROL AS rol, F.CEDULA AS cedula,
        F.MATRICULA_PROFESIONAL AS matricula_profesional, F.ORDEN_FIRMA AS orden_firma,
        PK_GENERAL.fn_nombre_tercero(GF.FUNCIONARIO_ID) AS nombre_firmante
      FROM ACF_FIRMANTE F
      LEFT JOIN GTH_FUNCIONARIOS GF ON GF.ID = F.FUNCIONARIO_ID
      WHERE F.CLIENTE_ID = :clienteId
        AND F.ENTIDAD_ID = :entidadId
        AND F.TIPO_DOCUMENTO = 'DEPRECIACION'
        AND F.ESTADO = 'ACTIVO'
        AND F.ROL IN ('CONTADOR','ALMACENISTA')
      ORDER BY F.ORDEN_FIRMA
    ]'
  );

  ------------------------------------------------------------
  -- COMITE DE BAJAS (firmantes: mismo patron que Depreciacion via
  -- ACF_FIRMANTE, TIPO_DOCUMENTO='COMITE_BAJA', sin restringir ROL)
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'comite-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'comite-cabecera',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        CB.ID AS id, CB.CLIENTE_ID AS cliente_id, CB.ENTIDAD_ID AS entidad_id,
        CB.VIGENCIA AS vigencia, CB.CONSECUTIVO AS consecutivo,
        CB.NUMERO_ACTA AS numero_acta, CB.FECHA_COMITE AS fecha_comite,
        CB.ESTADO AS estado, CB.OBSERVACIONES AS observaciones,
        CB.FECHA_APROBACION AS fecha_aprobacion, CB.USUARIO_APROBACION AS usuario_aprobacion,
        CB.FECHA_CREACION AS fecha_creacion, CB.FECHA_MODIFICACION AS fecha_modificacion,
        PK_GENERAL.fn_nombre_cliente(CB.CLIENTE_ID) AS nombre_cliente,
        PK_GENERAL.fn_nombre_entidad(CB.ENTIDAD_ID) AS nombre_entidad,
        GE.LOGO_ENTIDAD AS logo_entidad, GE.LOGO_MIME_TYPE AS logo_mime_type,
        GE.LOGO_FILENAME AS logo_filename
      FROM ACF_COMITE_BAJA CB
      JOIN GEN_ENTIDAD GE ON GE.ID = CB.ENTIDAD_ID
      WHERE CB.ID = :id
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'comite-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'comite-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        AF.NUMERO_PLACA AS numero_placa, C.DESCRIPCION AS descripcion,
        CBD.DIAGNOSTICO AS diagnostico, CBD.DECISION AS decision,
        TM2.DESC_TIPO_MOVIMIENTO AS tipo_egreso_sugerido,
        EG.CONSECUTIVO AS numero_egreso,
        CBD.OBSERVACIONES AS observaciones
      FROM ACF_COMITE_BAJA_DETALLE CBD
      JOIN ACF_ACTIVOS_FIJOS AF ON AF.ID = CBD.ACTIVO_FIJO_ID
      JOIN ACF_CATALOGO C       ON C.ID = AF.CATALOGO_ID
      LEFT JOIN ACF_TIPO_MOVIMIENTO TM2 ON TM2.ID = CBD.TIPO_EGRESO_SUGERIDO_ID
      LEFT JOIN ACF_EGRESO EG           ON EG.ID = CBD.EGRESO_ID
      WHERE CBD.COMITE_BAJA_ID = :id
      ORDER BY AF.NUMERO_PLACA
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'comite-firmantes');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'comite-firmantes',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        F.ROL AS rol, F.CEDULA AS cedula,
        F.MATRICULA_PROFESIONAL AS matricula_profesional, F.ORDEN_FIRMA AS orden_firma,
        PK_GENERAL.fn_nombre_tercero(GF.FUNCIONARIO_ID) AS nombre_firmante
      FROM ACF_FIRMANTE F
      LEFT JOIN GTH_FUNCIONARIOS GF ON GF.ID = F.FUNCIONARIO_ID
      WHERE F.CLIENTE_ID = :clienteId
        AND F.ENTIDAD_ID = :entidadId
        AND F.TIPO_DOCUMENTO = 'COMITE_BAJA'
        AND F.ESTADO = 'ACTIVO'
      ORDER BY F.ORDEN_FIRMA
    ]'
  );

  COMMIT;
END;
/
