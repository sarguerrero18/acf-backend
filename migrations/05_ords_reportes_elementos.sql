-- ============================================================
-- Endpoints ORDS para los Reportes de Elementos Asignados (Paginas
-- 42/43, ver Objetos_BD_ACF.txt "PAGINAS 42/43" y "CORRECCION PAGINAS
-- 42/43") -- correr en SQL Workshop del esquema ACF, DESPUES de
-- 01/02/03/04_ords_*.sql (reutiliza el modulo 'acf.actas' ya creado por
-- 04_ords_actas.sql; se vuelve a llamar DEFINE_MODULE aca para que este
-- script sea autocontenido y se pueda correr solo, sin depender del
-- orden real de ejecucion -- DEFINE_MODULE con el mismo p_module_name
-- actualiza en vez de duplicar, mismo comportamiento que CREATE OR
-- REPLACE).
--
-- A diferencia de las 7 actas de 04_ords_actas.sql, estos 2 reportes NO
-- tienen una tabla de cabecera propia (no existe "ACF_REPORTE_
-- ELEMENTOS" ni similar) -- son un filtro sobre ACF_ACTIVOS_FIJOS por
-- FUNCIONARIO_RESPONSABLE_ID o DEP_RESPONSABLE_ID, exactamente el mismo
-- criterio de alcance ya usado en las Paginas 42/43 (ver su propio
-- header): cualquier UBICACION con responsable registrado, excepto
-- UBICACION='BAJA'.
--
-- Como :id (el path param que arma la Pagina 36 con P36_TIPO/P36_ID) es
-- el ID de GTH_FUNCIONARIOS o de GEN_DEPENDENCIA (no el de un documento
-- propio de ACF), no hay de donde sacar CLIENTE_ID/ENTIDAD_ID
-- directamente del :id salvo asumiendo que esas tablas externas los
-- traen (no confirmado). En vez de arriesgar una columna que quizas no
-- existe en GTH_FUNCIONARIOS/GEN_DEPENDENCIA, CLIENTE_ID/ENTIDAD_ID se
-- derivan del PRIMER activo encontrado para ese funcionario/dependencia
-- en ACF_ACTIVOS_FIJOS (tabla propia, con esas 2 columnas confirmadas
-- NOT NULL en el DDL original). *** SUPUESTO A VALIDAR: si el
-- funcionario/dependencia elegido no tiene NINGUN activo asignado
-- (reporte vacio), *-cabecera tambien queda sin filas -- el generador
-- de PDF (acf-backend) fallara con el mismo error de "no se encontro
-- ningun registro" que ya usan las demas actas cuando el :id no
-- resuelve. En la practica no deberia pasar: Sergio solo imprime
-- despues de ver filas en el Interactive Report en pantalla.
--
-- Nombres resueltos con los mismos helpers ya usados en el resto del
-- modulo (PK_GENERAL.fn_nombre_cliente/fn_nombre_entidad/
-- fn_nombre_dependencia/fn_nombre_tercero) -- fn_nombre_tercero recibe
-- GTH_FUNCIONARIOS.FUNCIONARIO_ID (la referencia a GEN_PERSONA dentro de
-- esa misma tabla), NO GTH_FUNCIONARIOS.ID directo, mismo patron
-- documentado en el header de 04_ords_actas.sql.
-- ============================================================

BEGIN
  ORDS.DEFINE_MODULE(
    p_module_name    => 'acf.actas',
    p_base_path      => '/actas/',
    p_items_per_page => 0,
    p_status         => 'PUBLISHED',
    p_comments       => 'API de actas de Activos Fijos -- consumida por el backend Node (acf-backend)'
  );

  ------------------------------------------------------------
  -- ELEMENTOS ASIGNADOS A UN FUNCIONARIO (Pagina 42)
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

  ------------------------------------------------------------
  -- ELEMENTOS ASIGNADOS A UNA DEPENDENCIA (Pagina 43)
  ------------------------------------------------------------
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

  COMMIT;
END;
/
