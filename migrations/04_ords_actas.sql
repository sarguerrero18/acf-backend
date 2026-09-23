-- ============================================================
-- Endpoints ORDS del modulo 'acf.actas' -- correr en SQL Workshop
-- del esquema ACF, DESPUES de 01/02/03_ords_*.sql.
--
-- *** REGLA CRITICA, confirmada con datos reales (2026-09-08): este
-- archivo debe ser SIEMPRE la copia COMPLETA Y UNICA de todo el modulo
-- 'acf.actas' -- ORDS.DEFINE_MODULE, al llamarse sobre un modulo que
-- YA EXISTE, borra TODOS sus templates/handlers previos antes de
-- aplicar los DEFINE_TEMPLATE/DEFINE_HANDLER que sigan en el MISMO
-- script (no esta documentado asi en ningun lado, se confirmo
-- empiricamente: Sergio corrio este archivo -- entrega la Version 84
-- de la actas, 18 endpoints, actas viejas funcionando -- y despues
-- corrio por separado un archivo aparte migrations/
-- 05_ords_reportes_elementos.sql con SOLO los 4 endpoints de
-- Elementos Asignados (Paginas 42/43); ese segundo script, con su
-- propio ORDS.DEFINE_MODULE, borro los 18 endpoints que este archivo
-- acababa de crear, dejando SOLO los 4 nuevos -- rompiendo la
-- impresion de TODAS las actas de un dia para otro).
--
-- Por eso, cualquier endpoint nuevo de /actas/* (nueva acta, nuevo
-- reporte) se agrega DIRECTO en este archivo (antes del COMMIT final),
-- NUNCA en un migrations/0N_ords_*.sql aparte -- migrations/
-- 05_ords_reportes_elementos.sql queda MARCADO COMO NO USAR (ver su
-- propio header) y su contenido ya esta fusionado aca abajo, en la
-- seccion "ELEMENTOS ASIGNADOS A FUNCIONARIO/DEPENDENCIA". Repetir
-- SIEMPRE este archivo completo (los 18 endpoints originales + lo que
-- se agregue) es justamente lo que ya veniamos haciendo sin darnos
-- cuenta desde el principio -- cada acta nueva (Traslado, Egreso,
-- Depreciacion, Comite de Bajas, Deterioro, RVU) se agrego SIEMPRE
-- editando este mismo archivo y volviendo a correrlo entero, nunca en
-- un script separado -- migrations/05 fue la primera vez que se rompio
-- ese patron, y por eso fue la primera vez que paso esto.
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
-- SEPTIMA CORRECCION: ingreso-detalle salia vacio para ingresos en
-- ESTADO=ELABORADO (probado con Ingreso No. 10, id=82 -- ORDS devolvia
-- {"items":[]}). Causa: la query solo consultaba ACF_ACTIVOS_FIJOS
-- WHERE INGRESO_ID=:id, pero esos registros NO existen todavia
-- mientras el ingreso esta en ELABORADO -- Sergio confirmo que el
-- detalle real, mientras tanto, vive en ACF_DETALLE_INGRESO (columnas
-- CATALOGO_ID/MARCA/REFERENCIA/MODELO/SERIAL/VALOR/VALOR_IVA/
-- VALOR_TOTAL/NUMERO_PLACA -- este ultimo nulo hasta la aprobacion).
-- Al aprobar el ingreso, se crean los registros definitivos en
-- ACF_ACTIVOS_FIJOS A PARTIR de ACF_DETALLE_INGRESO, y el
-- NUMERO_PLACA de ACF_DETALLE_INGRESO se actualiza solo a nivel
-- informativo (consultas/historial) -- ACF_ACTIVOS_FIJOS queda como
-- la fuente autoritativa una vez existe (puede tener correcciones
-- posteriores). Fix: ingreso-detalle ahora es un UNION ALL -- usa
-- ACF_ACTIVOS_FIJOS si ya hay filas para ese ingreso (caso normal,
-- APROBADO), y si no hay ninguna, cae a ACF_DETALLE_INGRESO (caso
-- ELABORADO). NUMERO_PLACA puede salir NULL en el segundo caso (se
-- ordena con NULLS LAST).
--
-- Traslado y Egreso NO deberian tener este problema -- a diferencia
-- de Ingreso, solo se puede trasladar/egresar un activo que YA EXISTE
-- en ACF_ACTIVOS_FIJOS (con placa real), asi que ACF_DETALLE_TRASLADO/
-- ACF_DETALLE_EGRESO siempre apuntan a un activo fijo real sin
-- importar el estado del movimiento. No confirmado explicitamente por
-- Sergio (dijo que no habia revisado los otros tipos todavia) -- si
-- aparece el mismo sintoma alli, avisar para aplicar el mismo patron.
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
--
-- OCTAVA ADICION: acta de Deterioro (2026-09-04/05). DDL real
-- compartida por Sergio para ACF_DETERIORO (ID/CLIENTE_ID/ENTIDAD_ID/
-- TIPO_MOVIMIENTO_ID/VIGENCIA/CONSECUTIVO/NUMERO_ACTA/FECHA/ESTADO IN
-- ('ELABORADO','APROBADO') -- OJO, sin ANULADO, igual que Comite de
-- Bajas -- /DEPENDENCIA_ID/FECHA_APROBACION/USUARIO_APROBACION/
-- OBSERVACIONES/auditoria), ACF_DETALLE_DETERIORO (CLIENTE_ID/
-- ENTIDAD_ID/DETERIORO_ID/ACTIVO_FIJO_ID/INDICIO_DETERIORO_ID/
-- VALOR_EN_LIBROS/PRECIO_ESTIMADO_VENTA/COSTO_DIRECTO_VENTA/
-- VALOR_NETO_RAZONABLE/VALOR_EN_USO/IMPORTE_RECUPERABLE/
-- PERDIDA_POR_DETERIORO/DIAGNOSTICO/OBSERVACIONES/APLICA_DETERIORO
-- CHAR(1) S/N/auditoria) y la nueva tabla catalogo ACF_INDICIO_
-- DETERIORO (CLIENTE_ID/ENTIDAD_ID/TIPO_FUENTE EXTERNA|INTERNA/
-- ORIGEN_FUENTE/DESCRIPCION/auditoria), sembrada por Sergio con 7
-- indicios de deterioro segun NIC 36 parrafo 12 (a-d externos, e-g
-- internos).
--
-- deterioro-detalle selecciona los 7 campos que Sergio prioriza para
-- el reporte impreso (placa, valor en libros, importe recuperable,
-- diagnostico, indicio, aplica deterioro, observaciones) -- igual
-- criterio que las otras actas, donde el endpoint de detalle solo
-- trae lo que el PDF necesita, no todo el modelo de datos. CORRECCION
-- del mismo dia: Sergio pidio agregar tambien la Descripcion del
-- activo (join ACF_ACTIVOS_FIJOS -> ACF_CATALOGO, mismo patron que las
-- otras 5 actas) -- deterioro-detalle ahora trae 8 columnas.
--
-- SUPUESTOS DE LA OCTAVA ADICION -- CONFIRMADOS por Sergio el mismo
-- dia (ya no son supuestos):
--
-- 1. deterioro-firmantes restringe ROL IN ('CONTADOR','ALMACENISTA') --
--    confirmado: Sergio creo los firmantes CONTADOR y ALMACENISTA para
--    Deterioro (mismo patron que Depreciacion), asi que la restriccion
--    se queda tal cual.
-- 2. El CHECK CONSTRAINT de ACF_FIRMANTE.TIPO_DOCUMENTO ya fue
--    actualizado por Sergio para aceptar 'DETERIORO' -- confirmado.
-- 3. El prefijo de consecutivo del trigger ACF_DETERIORO_BIU YA NO es
--    'CMBJ' (el que compartia, sin corregir, con
--    ACF_COMITE_BAJA_BIU) -- Sergio lo actualizo a 'DTAF', propio de
--    Deterioro. Esto es un cambio en el trigger del lado de la base de
--    datos de Sergio (no vive en este archivo, que solo define
--    endpoints ORDS) -- se deja esta nota aca solo como registro
--    historico de que la duda se resolvio. Ademas, Sergio confirmo que
--    el trigger ACF_DETERIORO_BIU esta en estado ENABLE (el
--    ALTER TRIGGER ... DISABLE del DDL original ya no aplica) -- por
--    lo tanto CONSECUTIVO/FECHA_CREACION/USUARIO_CREACION/CLIENTE_ID/
--    ENTIDAD_ID de ACF_DETERIORO SI se llenan solos al insertar. Ya no
--    queda ningun supuesto abierto de la OCTAVA ADICION.
-- 4. La tabla no tiene columna propia de "fecha en que se aprobo" mas
--    alla de FECHA_APROBACION (si tiene) -- se sigue el mismo patron de
--    fechaDelEstado() ya usado (ELABORADO->fecha_creacion,
--    APROBADO->fecha_aprobacion; Deterioro no tiene ANULADO).
--
-- NOVENA ADICION: informe (acta) de Toma Fisica (2026-09-21/22) --
-- Toma Fisica NO tiene el ciclo ELABORADO/APROBADO/ANULADO de las
-- otras actas (ACF_TF.ESTADO solo admite EN_PROCESO/CERRADA, sin
-- contabilizacion). Firma: unicamente el almacenista ACTIVO de
-- ACF_ALMACENISTA (mismo mecanismo que ingreso/traslado/egreso-
-- cabecera, NO el patron ACF_FIRMANTE de Depreciacion/Comite/
-- Deterioro/RVU) -- por eso toma_fisica-cabecera resuelve
-- nombre_almacenista directo via LEFT JOIN, sin endpoint de firmantes
-- aparte. toma_fisica-detalle incluye la columna nueva
-- DEPENDENCIA_ENCONTRADA_ID (ACF_TF_DETALLE.DEPENDENCIA_ENCONTRADA_ID
-- NUMBER(20), agregada por Sergio) -- campo opcional, sin regla de
-- validacion (el concepto de "ubicacion" en este modulo -- estado
-- categorico BODEGA/SERVICIO/MANTENIMIENTO/COMODATO/BAJA/PERDIDO/
-- NO_EXPLOTADO -- es independiente de la dependencia, confirmado por
-- Sergio: ver Objetos_BD_ACF.txt VERSION 102).
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
      SELECT * FROM (
        SELECT
          AF.ID AS activo_fijo_id, AF.NUMERO_PLACA AS numero_placa,
          C.DESCRIPCION AS descripcion,
          AF.MARCA AS marca, AF.REFERENCIA AS referencia, AF.MODELO AS modelo,
          AF.SERIAL AS serial, AF.ESTADO AS estado,
          AF.VALOR AS valor, AF.VALOR_IVA AS valor_iva, AF.VALOR_TOTAL AS valor_total
        FROM ACF_ACTIVOS_FIJOS AF
        JOIN ACF_CATALOGO C ON C.ID = AF.CATALOGO_ID
        WHERE AF.INGRESO_ID = :id
        UNION ALL
        SELECT
          DI.ID AS activo_fijo_id, DI.NUMERO_PLACA AS numero_placa,
          C2.DESCRIPCION AS descripcion,
          DI.MARCA AS marca, DI.REFERENCIA AS referencia, DI.MODELO AS modelo,
          DI.SERIAL AS serial, CAST(NULL AS VARCHAR2(30)) AS estado,
          DI.VALOR AS valor, DI.VALOR_IVA AS valor_iva, DI.VALOR_TOTAL AS valor_total
        FROM ACF_DETALLE_INGRESO DI
        JOIN ACF_CATALOGO C2 ON C2.ID = DI.CATALOGO_ID
        WHERE DI.INGRESO_ID = :id
          AND NOT EXISTS (SELECT 1 FROM ACF_ACTIVOS_FIJOS AF2 WHERE AF2.INGRESO_ID = DI.INGRESO_ID)
      )
      ORDER BY numero_placa NULLS LAST, activo_fijo_id
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

  ------------------------------------------------------------
  -- DETERIORO (landscape/margenes estrechos en el generador Node --
  -- ver src/pdf/generarActaDeterioro.ts. Firmantes: mismo patron que
  -- Depreciacion via ACF_FIRMANTE, TIPO_DOCUMENTO='DETERIORO',
  -- restringiendo ROL -- confirmado por Sergio: se crearon los
  -- firmantes CONTADOR y ALMACENISTA para Deterioro, igual que
  -- Depreciacion, asi que el filtro ROL IN ('CONTADOR','ALMACENISTA')
  -- se deja tal cual. El CHECK CONSTRAINT de
  -- ACF_FIRMANTE.TIPO_DOCUMENTO ya fue actualizado por Sergio para
  -- aceptar 'DETERIORO'. deterioro-detalle ahora incluye la columna
  -- Descripcion del activo (JOIN a ACF_CATALOGO), a pedido de Sergio.)
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'deterioro-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'deterioro-cabecera',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        D.ID AS id, D.CLIENTE_ID AS cliente_id, D.ENTIDAD_ID AS entidad_id,
        D.VIGENCIA AS vigencia, D.CONSECUTIVO AS consecutivo,
        D.NUMERO_ACTA AS numero_acta, D.FECHA AS fecha_deterioro,
        D.ESTADO AS estado, D.OBSERVACIONES AS observaciones,
        D.FECHA_APROBACION AS fecha_aprobacion, D.USUARIO_APROBACION AS usuario_aprobacion,
        D.FECHA_CREACION AS fecha_creacion, D.FECHA_MODIFICACION AS fecha_modificacion,
        TM.DESC_TIPO_MOVIMIENTO AS desc_tipo_movimiento,
        PK_GENERAL.fn_nombre_dependencia(D.DEPENDENCIA_ID) AS nombre_dependencia,
        PK_GENERAL.fn_nombre_cliente(D.CLIENTE_ID) AS nombre_cliente,
        PK_GENERAL.fn_nombre_entidad(D.ENTIDAD_ID) AS nombre_entidad,
        GE.LOGO_ENTIDAD AS logo_entidad, GE.LOGO_MIME_TYPE AS logo_mime_type,
        GE.LOGO_FILENAME AS logo_filename
      FROM ACF_DETERIORO D
      JOIN ACF_TIPO_MOVIMIENTO TM ON TM.ID = D.TIPO_MOVIMIENTO_ID
      JOIN GEN_ENTIDAD GE         ON GE.ID = D.ENTIDAD_ID
      WHERE D.ID = :id
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'deterioro-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'deterioro-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        AF.NUMERO_PLACA AS numero_placa, C.DESCRIPCION AS descripcion,
        DD.VALOR_EN_LIBROS AS valor_en_libros,
        DD.IMPORTE_RECUPERABLE AS importe_recuperable,
        DD.DIAGNOSTICO AS diagnostico,
        IND.DESCRIPCION AS indicio,
        DD.APLICA_DETERIORO AS aplica_deterioro,
        DD.OBSERVACIONES AS observaciones
      FROM ACF_DETALLE_DETERIORO DD
      JOIN ACF_ACTIVOS_FIJOS AF        ON AF.ID = DD.ACTIVO_FIJO_ID
      JOIN ACF_CATALOGO C              ON C.ID = AF.CATALOGO_ID
      JOIN ACF_INDICIO_DETERIORO IND   ON IND.ID = DD.INDICIO_DETERIORO_ID
      WHERE DD.DETERIORO_ID = :id
      ORDER BY AF.NUMERO_PLACA
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'deterioro-firmantes');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'deterioro-firmantes',
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
        AND F.TIPO_DOCUMENTO = 'DETERIORO'
        AND F.ESTADO = 'ACTIVO'
        AND F.ROL IN ('CONTADOR','ALMACENISTA')
      ORDER BY F.ORDEN_FIRMA
    ]'
  );

  ------------------------------------------------------------
  -- RECALCULO DE VIDA UTIL (RVU) -- acta sin firmantes-entrega/recibe,
  -- mismo criterio de Deterioro (evaluacion tecnica, sin
  -- contabilizacion -- ver ddl_recalculo_vida_util.sql). Firmantes:
  -- confirmado por Sergio (2026-09-07) mismo patron de
  -- Depreciacion/Deterioro, TIPO_DOCUMENTO='RECALCULO_VIDA_UTIL' (SIN
  -- abreviar -- es un valor de dato, no un nombre de objeto, mismo
  -- criterio ya aplicado a TIPO_MOV_ACF), ROL IN ('CONTADOR',
  -- 'ALMACENISTA'). *** SUPUESTO A VALIDAR: requiere que Sergio extienda
  -- el CHECK CONSTRAINT de ACF_FIRMANTE.TIPO_DOCUMENTO para aceptar
  -- 'RECALCULO_VIDA_UTIL' y cree los firmantes activos para ese tipo
  -- (igual que hizo para 'DETERIORO') -- mientras tanto rvu-firmantes
  -- devuelve 0 filas y el generador cae al placeholder "(sin asignar)".
  --
  -- rvu-cabecera: ACF_RVU no tiene VIGENCIA/NUMERO_ACTA (a diferencia de
  -- Deterioro/Comite de Bajas) -- usa CONSECUTIVO + PERIODO_ID (ANIO/MES
  -- via JOIN a ACF_PERIODO), mismo patron de Depreciacion.
  --
  -- rvu-detalle: trae los campos priorizados para el acta impresa --
  -- placa/descripcion del activo, nombre de la causa, justificacion, los
  -- dos insumos del evaluador (ajuste_dias, porcentaje_valor_residual),
  -- valor en libros y los 3 pares antes/despues (vida util ajustada,
  -- vida util restante, valor residual). VALOR_SALVAMENTO (informativo,
  -- sin antes/despues, ver ddl_recalculo_vida_util.sql) se incluye por
  -- si el acta lo quiere mostrar, pero no es obligatorio en la tabla
  -- impresa.
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'rvu-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'rvu-cabecera',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        R.ID AS id, R.CLIENTE_ID AS cliente_id, R.ENTIDAD_ID AS entidad_id,
        R.CONSECUTIVO AS consecutivo, R.ESTADO AS estado,
        R.FECHA_GENERACION AS fecha_generacion, R.FECHA_APROBACION AS fecha_aprobacion,
        R.USUARIO_APROBACION AS usuario_aprobacion,
        R.FECHA_CREACION AS fecha_creacion, R.FECHA_MODIFICACION AS fecha_modificacion,
        R.NUMERO_DOCUMENTO_SOPORTE AS numero_documento_soporte,
        R.FECHA_DOCUMENTO_SOPORTE AS fecha_documento_soporte,
        R.OBSERVACIONES AS observaciones,
        P.ANIO AS anio, P.MES AS mes,
        TM.DESC_TIPO_MOVIMIENTO AS desc_tipo_movimiento,
        PK_GENERAL.fn_nombre_cliente(R.CLIENTE_ID) AS nombre_cliente,
        PK_GENERAL.fn_nombre_entidad(R.ENTIDAD_ID) AS nombre_entidad,
        GE.LOGO_ENTIDAD AS logo_entidad, GE.LOGO_MIME_TYPE AS logo_mime_type,
        GE.LOGO_FILENAME AS logo_filename
      FROM ACF_RVU R
      JOIN ACF_PERIODO P          ON P.ID = R.PERIODO_ID
      JOIN ACF_TIPO_MOVIMIENTO TM ON TM.ID = R.TIPO_MOVIMIENTO_ID
      JOIN GEN_ENTIDAD GE         ON GE.ID = R.ENTIDAD_ID
      WHERE R.ID = :id
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'rvu-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'rvu-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        AF.NUMERO_PLACA AS numero_placa, C.DESCRIPCION AS descripcion,
        CA.NOMBRE AS causa,
        DR.JUSTIFICACION AS justificacion,
        DR.AJUSTE_DIAS AS ajuste_dias,
        DR.PORCENTAJE_VALOR_RESIDUAL AS porcentaje_valor_residual,
        DR.VALOR_LIBROS_ANTES AS valor_libros_antes,
        DR.VIDA_UTIL_AJUSTADA_ANTES AS vida_util_ajustada_antes,
        DR.VIDA_UTIL_AJUSTADA_DESPUES AS vida_util_ajustada_despues,
        DR.VIDA_UTIL_RESTANTE_ANTES AS vida_util_restante_antes,
        DR.VIDA_UTIL_RESTANTE_DESPUES AS vida_util_restante_despues,
        DR.VALOR_RESIDUAL_ANTES AS valor_residual_antes,
        DR.VALOR_RESIDUAL_DESPUES AS valor_residual_despues,
        DR.VALOR_SALVAMENTO AS valor_salvamento
      FROM ACF_DETALLE_RVU DR
      JOIN ACF_ACTIVOS_FIJOS AF ON AF.ID = DR.ACTIVO_FIJO_ID
      JOIN ACF_CATALOGO C       ON C.ID = AF.CATALOGO_ID
      JOIN ACF_CAUSA_RVU CA     ON CA.ID = DR.CAUSA_RECALCULO_ID
      WHERE DR.RECALCULO_ID = :id
      ORDER BY AF.NUMERO_PLACA
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'rvu-firmantes');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'rvu-firmantes',
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
        AND F.TIPO_DOCUMENTO = 'RECALCULO_VIDA_UTIL'
        AND F.ESTADO = 'ACTIVO'
        AND F.ROL IN ('CONTADOR','ALMACENISTA')
      ORDER BY F.ORDEN_FIRMA
    ]'
  );

  ------------------------------------------------------------
  -- TOMA FISICA (informe/acta, 2026-09-21/22) -- NOVENA ADICION, ver
  -- header de este archivo. Sin endpoint de firmantes aparte (mismo
  -- mecanismo que ingreso/traslado/egreso-cabecera): nombre_almacenista
  -- se resuelve directo via LEFT JOIN a ACF_ALMACENISTA + GTH_FUNCIONARIOS
  -- con ESTADO='ACTIVO', puede venir NULL si no hay ningun almacenista
  -- ACTIVO configurado (el generador de PDF muestra "(sin asignar)").
  -- toma_fisica-detalle: DEPENDENCIA_ENCONTRADA_ID es opcional, sin
  -- regla de validacion (ver header -- corregido en Objetos_BD_ACF.txt
  -- VERSION 102, el trigger ACF_TF_DET_BIU ya NO exige este campo).
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'toma_fisica-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'toma_fisica-cabecera',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        T.ID AS id, T.CLIENTE_ID AS cliente_id, T.ENTIDAD_ID AS entidad_id,
        T.CONSECUTIVO AS consecutivo, T.DESCRIPCION AS descripcion,
        T.FECHA_INICIO AS fecha_inicio, T.FECHA_FIN AS fecha_fin,
        T.ALCANCE_TIPO AS alcance_tipo,
        T.DEP_RESPONSABLE_ID AS dep_responsable_id,
        CASE WHEN T.DEP_RESPONSABLE_ID IS NULL THEN NULL
             ELSE PK_GENERAL.fn_nombre_dependencia(T.DEP_RESPONSABLE_ID) END AS nombre_dep_responsable,
        T.BODEGA AS bodega, T.ESTADO AS estado,
        T.FECHA_CIERRE AS fecha_cierre, T.USUARIO_CIERRE AS usuario_cierre,
        T.OBSERVACIONES AS observaciones,
        T.FECHA_CREACION AS fecha_creacion, T.USUARIO_CREACION AS usuario_creacion,
        T.FECHA_MODIFICACION AS fecha_modificacion, T.USUARIO_MODIFICACION AS usuario_modificacion,
        PK_GENERAL.fn_nombre_cliente(T.CLIENTE_ID) AS nombre_cliente,
        PK_GENERAL.fn_nombre_entidad(T.ENTIDAD_ID) AS nombre_entidad,
        GE.LOGO_ENTIDAD AS logo_entidad, GE.LOGO_MIME_TYPE AS logo_mime_type,
        GE.LOGO_FILENAME AS logo_filename,
        PK_GENERAL.fn_nombre_tercero(GF_ALM.FUNCIONARIO_ID) AS nombre_almacenista
      FROM ACF_TF T
      JOIN GEN_ENTIDAD GE ON GE.ID = T.ENTIDAD_ID
      LEFT JOIN ACF_ALMACENISTA ALM ON ALM.CLIENTE_ID = T.CLIENTE_ID
        AND ALM.ENTIDAD_ID = T.ENTIDAD_ID AND ALM.ESTADO = 'ACTIVO'
      LEFT JOIN GTH_FUNCIONARIOS GF_ALM ON GF_ALM.ID = ALM.FUNCIONARIO_ID
      WHERE T.ID = :id
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'toma_fisica-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'toma_fisica-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        AF.NUMERO_PLACA AS numero_placa, C.DESCRIPCION AS descripcion,
        D.UBICACION_ESPERADA AS ubicacion_esperada,
        D.UBICACION_ENCONTRADA AS ubicacion_encontrada,
        D.ESTADO_ESPERADO AS estado_esperado,
        D.ESTADO_ENCONTRADO AS estado_encontrado,
        D.RESULTADO AS resultado,
        CASE WHEN D.DEPENDENCIA_ESPERADA_ID IS NULL THEN NULL
             ELSE PK_GENERAL.fn_nombre_dependencia(D.DEPENDENCIA_ESPERADA_ID) END AS nombre_dependencia_esperada,
        CASE WHEN D.DEPENDENCIA_ENCONTRADA_ID IS NULL THEN NULL
             ELSE PK_GENERAL.fn_nombre_dependencia(D.DEPENDENCIA_ENCONTRADA_ID) END AS nombre_dependencia_encontrada,
        D.OBSERVACIONES AS observaciones
      FROM ACF_TF_DETALLE D
      JOIN ACF_ACTIVOS_FIJOS AF ON AF.ID = D.ACTIVO_FIJO_ID
      JOIN ACF_CATALOGO C       ON C.ID = AF.CATALOGO_ID
      WHERE D.TF_ID = :id
      ORDER BY AF.NUMERO_PLACA
    ]'
  );

  ------------------------------------------------------------
  -- ELEMENTOS ASIGNADOS A FUNCIONARIO/DEPENDENCIA (Paginas 42/43,
  -- 2026-09-08) -- fusionado aca desde migrations/
  -- 05_ords_reportes_elementos.sql (ver *** REGLA CRITICA en el header
  -- de este archivo -- ese script aparte causo que ORDS.DEFINE_MODULE
  -- borrara los 18 endpoints de arriba; no se debe volver a correr por
  -- separado).
  --
  -- A diferencia de las 7 actas de arriba, no hay tabla de cabecera
  -- propia (no existe "ACF_REPORTE_ELEMENTOS" ni similar) -- son un
  -- filtro sobre ACF_ACTIVOS_FIJOS por FUNCIONARIO_RESPONSABLE_ID o
  -- DEP_RESPONSABLE_ID (cualquier UBICACION con responsable registrado,
  -- salvo 'BAJA' -- mismo alcance ya confirmado por Sergio para las
  -- Paginas 42/43). Como :id es el ID de GTH_FUNCIONARIOS o de
  -- GEN_DEPENDENCIA (no el de un documento ACF propio), CLIENTE_ID/
  -- ENTIDAD_ID se derivan del primer activo encontrado en
  -- ACF_ACTIVOS_FIJOS para ese funcionario/dependencia. *** SUPUESTO A
  -- VALIDAR: si el funcionario/dependencia no tiene NINGUN activo
  -- asignado, *-cabecera no resuelve fila -- no deberia pasar en la
  -- practica (Sergio solo imprime despues de ver filas en pantalla).
  ------------------------------------------------------------
  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'elementos_funcionario-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'elementos_funcionario-cabecera',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        GF.ID AS funcionario_id,
        PK_GENERAL.fn_nombre_tercero(GF.FUNCIONARIO_ID) AS nombre_funcionario,
        PK_GENERAL.fn_nombre_dependencia(GF.DEPENDENCIA_ID) AS nombre_dependencia_funcionario,
        X.CLIENTE_ID AS cliente_id, X.ENTIDAD_ID AS entidad_id,
        PK_GENERAL.fn_nombre_cliente(X.CLIENTE_ID) AS nombre_cliente,
        PK_GENERAL.fn_nombre_entidad(X.ENTIDAD_ID) AS nombre_entidad,
        GE.LOGO_ENTIDAD AS logo_entidad, GE.LOGO_MIME_TYPE AS logo_mime_type,
        GE.LOGO_FILENAME AS logo_filename
      FROM GTH_FUNCIONARIOS GF
      JOIN (
        SELECT CLIENTE_ID, ENTIDAD_ID FROM ACF_ACTIVOS_FIJOS
         WHERE FUNCIONARIO_RESPONSABLE_ID = :id AND UBICACION != 'BAJA' AND ROWNUM = 1
      ) X ON 1 = 1
      JOIN GEN_ENTIDAD GE ON GE.ID = X.ENTIDAD_ID
      WHERE GF.ID = :id
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'elementos_funcionario-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'elementos_funcionario-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        AF.NUMERO_PLACA AS numero_placa,
        C.DESCRIPCION AS descripcion,
        (
          SELECT MAX(K.FECHA_MOVIMIENTO)
            FROM ACF_V_KARDEX_ACTIVOS K
           WHERE K.ACTIVO_FIJO_ID = AF.ID
             AND K.CLASE_MOVIMIENTO IN ('INGRESO','TRASLADO')
        ) AS fecha_asignacion,
        PK_GENERAL.fn_nombre_dependencia(AF.DEP_RESPONSABLE_ID) AS nombre_dependencia
      FROM ACF_ACTIVOS_FIJOS AF
      JOIN ACF_CATALOGO C ON C.ID = AF.CATALOGO_ID
      WHERE AF.FUNCIONARIO_RESPONSABLE_ID = :id
        AND AF.UBICACION != 'BAJA'
      ORDER BY AF.NUMERO_PLACA
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'elementos_dependencia-cabecera');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'elementos_dependencia-cabecera',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        :id AS dependencia_id,
        PK_GENERAL.fn_nombre_dependencia(:id) AS nombre_dependencia,
        X.CLIENTE_ID AS cliente_id, X.ENTIDAD_ID AS entidad_id,
        PK_GENERAL.fn_nombre_cliente(X.CLIENTE_ID) AS nombre_cliente,
        PK_GENERAL.fn_nombre_entidad(X.ENTIDAD_ID) AS nombre_entidad,
        GE.LOGO_ENTIDAD AS logo_entidad, GE.LOGO_MIME_TYPE AS logo_mime_type,
        GE.LOGO_FILENAME AS logo_filename
      FROM (
        SELECT CLIENTE_ID, ENTIDAD_ID FROM ACF_ACTIVOS_FIJOS
         WHERE DEP_RESPONSABLE_ID = :id AND UBICACION != 'BAJA' AND ROWNUM = 1
      ) X
      JOIN GEN_ENTIDAD GE ON GE.ID = X.ENTIDAD_ID
    ]'
  );

  ORDS.DEFINE_TEMPLATE(p_module_name => 'acf.actas', p_pattern => 'elementos_dependencia-detalle');

  ORDS.DEFINE_HANDLER(
    p_module_name    => 'acf.actas',
    p_pattern        => 'elementos_dependencia-detalle',
    p_method         => 'GET',
    p_source_type    => ORDS.source_type_query,
    p_items_per_page => 0,
    p_source         => q'[
      SELECT
        AF.NUMERO_PLACA AS numero_placa,
        C.DESCRIPCION AS descripcion,
        (
          SELECT MAX(K.FECHA_MOVIMIENTO)
            FROM ACF_V_KARDEX_ACTIVOS K
           WHERE K.ACTIVO_FIJO_ID = AF.ID
             AND K.CLASE_MOVIMIENTO IN ('INGRESO','TRASLADO')
        ) AS fecha_asignacion,
        PK_GENERAL.fn_nombre_tercero(GF.FUNCIONARIO_ID) AS nombre_funcionario
      FROM ACF_ACTIVOS_FIJOS AF
      JOIN ACF_CATALOGO C ON C.ID = AF.CATALOGO_ID
      LEFT JOIN GTH_FUNCIONARIOS GF ON GF.ID = AF.FUNCIONARIO_RESPONSABLE_ID
      WHERE AF.DEP_RESPONSABLE_ID = :id
        AND AF.UBICACION != 'BAJA'
      ORDER BY AF.NUMERO_PLACA
    ]'
  );

  ------------------------------------------------------------
  -- ALM INGRESO/EGRESO/TRASLADO/DEVOLUCION -- agregado 2026-09-23,
  -- reglas de la pagina 36 de ALM (clonada de la de ACF, mismo numero
  -- de pagina). Se EXTIENDE acf-backend en vez de crear un backend/ORDS
  -- separado para ALM (decision de Sergio) -- mismo modulo 'acf.actas',
  -- mismo host, mismo OAuth2 (ACF_APEX_OAUTH2/acf_apex_client), mismo
  -- PKG_ACF_CLIENT. Los handlers corren en el schema ACF pero consultan
  -- tablas de ALM cross-schema (ALM.ALM_*) -- ver GRANT SELECT
  -- necesarios (a correr como ALM) en migrations/06_ords_grants_alm.sql.
  --
  -- Ademas la pagina 36 de ALM debe calificar la llamada como
  -- ACF.PKG_ACF_CLIENT.DESCARGAR_ACTA(l_ruta) (no
  -- pkg_acf_client.descargar_acta sin calificar, son schemas distintos)
  -- y ACF debe otorgar GRANT EXECUTE ON PKG_ACF_CLIENT TO ALM.
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
