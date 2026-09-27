--------------------------------------------------------------------------------
-- Migracion para la base de datos ALM ya desplegada (el CREATE TABLE de
-- 00_ddl_alm_v1_completo.sql solo aplica a una instalacion nueva desde
-- cero -- las tablas ALM_EGRESO/ALM_DEVOLUCION de Sergio ya existen con
-- datos de prueba).
--
-- Ajustes pedidos por Sergio (2026-09-24), ver PKG_ALM VERSION 6, nota
-- (viii).3 en 01_pkg_alm_v1_completo.sql:
--   1. ALM_EGRESO.FUNCIONARIO_DESTINO_ID pasa de opcional a OBLIGATORIO.
--   2. ALM_DEVOLUCION necesita una columna NUEVA, FUNCIONARIO_ORIGEN_ID
--      (quien devuelve), tambien OBLIGATORIA.
--
-- Conectar como el owner ALM (o un usuario con privilegio sobre el
-- esquema ALM) antes de ejecutar.
--------------------------------------------------------------------------------

-- Paso 1: agregar la columna nueva a ALM_DEVOLUCION -- se agrega
-- NULLABLE primero (una columna NOT NULL no se puede agregar directo a
-- una tabla con filas existentes salvo que se de un DEFAULT), se
-- backfillea si hace falta, y solo al final se aplica la constraint
-- NOT NULL (Paso 3).
ALTER TABLE ALM_DEVOLUCION ADD (
  FUNCIONARIO_ORIGEN_ID NUMBER(20)
);
COMMENT ON COLUMN ALM_DEVOLUCION.FUNCIONARIO_ORIGEN_ID IS
  'Funcionario que devuelve -- agregado 2026-09-24 (Sergio): importante para trazabilidad, ej. devoluciones originadas por un traslado (la dependencia que recibio le retorna algo a la dependencia que entrego).';

-- Paso 2: verificar si hay filas existentes que quedarian con el campo
-- vacio antes de aplicar las constraints NOT NULL del Paso 3 -- si
-- cualquiera de las 2 consultas devuelve filas, el ALTER TABLE .. MODIFY
-- del Paso 3 fallara con ORA-02296 (no se puede habilitar la constraint,
-- hay filas que la violan). Revisar con Sergio que valor usar para esas
-- filas (backfill manual) antes de continuar.

SELECT ID, CONSECUTIVO, ESTADO, FECHA_EGRESO
  FROM ALM_EGRESO
 WHERE FUNCIONARIO_DESTINO_ID IS NULL;

SELECT ID, CONSECUTIVO, ESTADO, FECHA_DEVOLUCION
  FROM ALM_DEVOLUCION
 WHERE FUNCIONARIO_ORIGEN_ID IS NULL;

-- Si alguna de las 2 consultas anteriores devolvio filas, backfillear
-- ANTES de continuar, por ejemplo:
--   UPDATE ALM_EGRESO SET FUNCIONARIO_DESTINO_ID = <id> WHERE ID = <id_del_egreso>;
--   UPDATE ALM_DEVOLUCION SET FUNCIONARIO_ORIGEN_ID = <id> WHERE ID = <id_de_la_devolucion>;
-- (no se backfillea aqui con un valor generico -- es informacion real de
-- quien recibio/devolvio, debe venir de Sergio o de los datos de origen).

-- Paso 3: aplicar las constraints NOT NULL -- ejecutar solo despues de
-- confirmar que las 2 consultas del Paso 2 no devuelven filas.
ALTER TABLE ALM_EGRESO MODIFY (
  FUNCIONARIO_DESTINO_ID NOT NULL
);
ALTER TABLE ALM_DEVOLUCION MODIFY (
  FUNCIONARIO_ORIGEN_ID NOT NULL
);

COMMIT;
