-- ============================================================
-- GRANTs necesarios para que los handlers ORDS 'alm_*' agregados en
-- migrations/04_ords_actas.sql (seccion "ALM INGRESO/EGRESO/TRASLADO/
-- DEVOLUCION", 2026-09-23) puedan leer las tablas de ALM cross-schema.
--
-- Correr como usuario ALM (SQL Workshop del esquema ALM). Sin esto,
-- 04_ords_actas.sql compila igual (son solo SELECT en texto, no se
-- valida contra las tablas al definir el handler) pero cada llamada a
-- /actas/alm_*/... falla en tiempo de ejecucion con ORA-00942 (tabla o
-- vista no existe).
--
-- *** IMPORTANTE: los endpoints ORDS reales viven TODOS juntos en
-- migrations/04_ords_actas.sql -- ORDS.DEFINE_MODULE borra el modulo
-- completo al re-ejecutarse (ver advertencia al inicio de ese
-- archivo). Este archivo (06) SOLO contiene los GRANT, no vuelvas a
-- poner aca ningun ORDS.DEFINE_HANDLER/DEFINE_TEMPLATE nuevo -- agregalo
-- siempre dentro de 04_ords_actas.sql y vuelve a correr ese archivo
-- COMPLETO.
-- ============================================================

GRANT SELECT ON ALM_INGRESO            TO ACF;
GRANT SELECT ON ALM_DETALLE_INGRESO    TO ACF;
GRANT SELECT ON ALM_EGRESO             TO ACF;
GRANT SELECT ON ALM_DETALLE_EGRESO     TO ACF;
GRANT SELECT ON ALM_TRASLADO           TO ACF;
GRANT SELECT ON ALM_DETALLE_TRASLADO   TO ACF;
GRANT SELECT ON ALM_DEVOLUCION         TO ACF;
GRANT SELECT ON ALM_DETALLE_DEVOLUCION TO ACF;
GRANT SELECT ON ALM_CATALOGO           TO ACF;
GRANT SELECT ON ALM_TIPO_MOVIMIENTO    TO ACF;

-- Aparte de este archivo, faltan 2 ajustes para que la pagina 36 de ALM
-- (proxy de descarga) funcione -- fuera del alcance de este script SQL:
--
--   1) Correr como ACF:
--        GRANT EXECUTE ON PKG_ACF_CLIENT TO ALM;
--
--   2) En el proceso PL/SQL de la pagina 36 DE ALM (Application 107),
--      cambiar la linea:
--        l_blob := pkg_acf_client.descargar_acta(l_ruta);
--      por:
--        l_blob := ACF.PKG_ACF_CLIENT.DESCARGAR_ACTA(l_ruta);
--      (sin calificar el esquema, ALM no encuentra el paquete -- vive
--      en el esquema ACF, no en ALM).
