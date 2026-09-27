--------------------------------------------------------------------------------
-- GRANTs requeridos para la Pagina 27 de ALM (Consolidado y Conciliacion
-- Contable, f107_page_27_consolidado_conciliacion.sql).
--
-- Igual que 06_ords_grants_alm.sql (que solo agrego GRANT SELECT sobre
-- tablas de ALM a favor de ACF, para las actas de impresion), este
-- archivo SOLO contiene GRANTs -- NUNCA definiciones ORDS.DEFINE_MODULE/
-- DEFINE_TEMPLATE/DEFINE_HANDLER, que deben ir siempre dentro del archivo
-- maestro 04_ords_actas.sql (ver advertencia en su encabezado: un
-- ORDS.DEFINE_MODULE ejecutado en un archivo SEPARADO sobre un modulo ya
-- existente BORRA todas las plantillas/handlers previos de ese modulo --
-- incidente real ya documentado).
--
-- Motivo: la region "Conciliacion Contable" de la Pagina 27 de ALM
-- consulta CNT_MOV_TRANSACCION directamente (igual patron que la Pagina
-- 31 de ACF) para cruzar los montos ya contabilizados por ALM contra lo
-- que el modulo de Contabilidad realmente registro. ALM nunca antes
-- necesito leer esa tabla directamente -- solo la escribe indirectamente
-- a traves de CNT.PCK_CNT_GENERAL (que corre con derechos de definidor).
--
-- Ejecutar conectado como un usuario con privilegio para otorgar sobre
-- el esquema CNT (o como el propio owner CNT):

GRANT SELECT ON CNT.CNT_MOV_TRANSACCION TO ALM;

-- No se requiere ningun otro GRANT nuevo para esta pagina: el LOV de
-- P27_PERIODO_ID consulta ACF.ACF_PERIODO, que ALM ya viene consultando
-- sin problema desde ALM_V_MOVIMIENTOS_CONTAB (Seccion 8 del DDL,
-- 00_ddl_alm_v1_completo.sql) -- ese acceso ya esta confirmado
-- funcionando (Pagina 26 ya probada por Sergio).

COMMIT;
