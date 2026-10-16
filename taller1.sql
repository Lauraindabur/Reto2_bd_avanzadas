-- Taller 1: PostgreSQL local + CockroachDB 

-- Integrantes: Dorian Alejandro Guisao Ospina
--            : Ana Isabella Gómez García
--            : Laura Indabur García
--            : David Quintero Gallego



-- FASE 1 - PASO 1.1 | Donde: PostgreSQL local | Crear la base de datos principal del negocio
CREATE DATABASE tienda_local;


-- FASE 1 - PASO 1.2 | Donde: CockroachDB  | Crear la base de datos de auditoria
CREATE DATABASE auditoria_db;
USE auditoria_db;

-- FASE 2 - PASO 2.1 | Donde: PostgreSQL local | Crear la tabla de negocio productos
CREATE TABLE productos (
    id        SERIAL PRIMARY KEY,
    nombre    VARCHAR(100) NOT NULL,
    precio    DECIMAL(10,2) NOT NULL,
    stock     INT DEFAULT 0,
    categoria VARCHAR(50),
    creado_en TIMESTAMP DEFAULT NOW()
);

-- FASE 2 - PASO 2.2 | Donde: CockroachDB  | Crear la tabla audit_log que guarda el historial de cambios
CREATE TABLE audit_log (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    operacion        VARCHAR(10)  NOT NULL,
    tabla_origen     VARCHAR(50)  NOT NULL,
    registro_id      VARCHAR(100),
    datos_anteriores JSONB,
    datos_nuevos     JSONB,
    fecha_hora       TIMESTAMP DEFAULT current_timestamp()
);

-- FASE 3 - PASO 3.1 | Donde: PostgreSQL local  | Activar la extension postgres_fdw
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- FASE 3 - PASO 3.2 | Donde: PostgreSQL local | Registrar el cluster de CockroachDB como servidor externo (puerto 26257, SSL require)
CREATE SERVER crdb_server
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (
        host    'taller-2-35277.j77.aws-us-east-1.cockroachlabs.cloud',
        port    '26257',
        dbname  'auditoria_db',
        sslmode 'require'
    );

-- FASE 3 - PASO 3.3 | Donde: PostgreSQL local | Mapear el usuario local postgres con las credenciales del cluster (contraseña omitida por seguridad)
CREATE USER MAPPING FOR postgres
    SERVER crdb_server
    OPTIONS (user 'laura', password '----');

-- FASE 3 - PASO 3.4 | Donde: PostgreSQL local | Crear la tabla foranea audit_log_crdb, espejo de audit_log en CockroachDB
CREATE FOREIGN TABLE audit_log_crdb (
    id               UUID,
    operacion        VARCHAR(10),
    tabla_origen     VARCHAR(50),
    registro_id      VARCHAR(100),
    datos_anteriores JSONB,
    datos_nuevos     JSONB,
    fecha_hora       TIMESTAMP
)
SERVER crdb_server
OPTIONS (schema_name 'public', table_name 'audit_log');

-- FASE 3 - PASO 3.5 | Donde: PostgreSQL local | Verificar la conexion con CockroachDB (debe devolver 0 filas sin error)
SELECT * FROM audit_log_crdb;

-- FASE 4 - PASO 4.1 | Donde: PostgreSQL local | Funcion del trigger: registra INSERT, UPDATE y DELETE en audit_log_crdb
-- El id y la fecha_hora se envian desde PostgreSQL porque CockroachDB no aplica sus DEFAULT por la tabla foranea
CREATE OR REPLACE FUNCTION fn_auditoria()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log_crdb
            (id, operacion, tabla_origen, registro_id, datos_anteriores, datos_nuevos, fecha_hora)
        VALUES
            (gen_random_uuid(), 'INSERT', TG_TABLE_NAME, NEW.id::text,
             NULL, row_to_json(NEW)::jsonb, clock_timestamp());
        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log_crdb
            (id, operacion, tabla_origen, registro_id, datos_anteriores, datos_nuevos, fecha_hora)
        VALUES
            (gen_random_uuid(), 'UPDATE', TG_TABLE_NAME, NEW.id::text,
             row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb, clock_timestamp());
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log_crdb
            (id, operacion, tabla_origen, registro_id, datos_anteriores, datos_nuevos, fecha_hora)
        VALUES
            (gen_random_uuid(), 'DELETE', TG_TABLE_NAME, OLD.id::text,
             row_to_json(OLD)::jsonb, NULL, clock_timestamp());
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- FASE 4 - PASO 4.2 | Donde: PostgreSQL local | Asociar el trigger a productos (AFTER INSERT, UPDATE y DELETE)
CREATE TRIGGER trg_auditoria_productos
AFTER INSERT OR UPDATE OR DELETE ON productos
FOR EACH ROW EXECUTE FUNCTION fn_auditoria();

-- FASE 5 - PASO 5.1 (enunciado 8.1) | Donde: PostgreSQL local | Prueba de 5 INSERT sobre productos
INSERT INTO productos (nombre, precio, stock, categoria) VALUES ('Raton Inalambrico Logitech', 25.50, 50, 'Accesorios');
INSERT INTO productos (nombre, precio, stock, categoria) VALUES ('Portatil Lenovo Legion', 1200.00, 10, 'Computadores');
INSERT INTO productos (nombre, precio, stock, categoria) VALUES ('Auriculares HyperX Cloud', 75.00, 20, 'Audio');
INSERT INTO productos (nombre, precio, stock, categoria) VALUES ('Monitor Gamer 27 pulgadas', 280.00, 15, 'Monitores');
INSERT INTO productos (nombre, precio, stock, categoria) VALUES ('Teclado Mecanico Redragon', 45.00, 30, 'Accesorios');

-- FASE 5 - PASO 5.2 (enunciado 8.2) | Donde: PostgreSQL local | Prueba de 3 UPDATE (cambia el precio en los tres)
UPDATE productos SET precio = 29.90 WHERE nombre = 'Raton Inalambrico Logitech';
UPDATE productos SET precio = 1150.00 WHERE nombre = 'Portatil Lenovo Legion';
UPDATE productos SET precio = 49.90, stock = 25 WHERE nombre = 'Teclado Mecanico Redragon';

-- FASE 5 - PASO 5.3 (enunciado 8.3) | Donde: PostgreSQL local | Prueba de 2 DELETE
DELETE FROM productos WHERE nombre = 'Auriculares HyperX Cloud';
DELETE FROM productos WHERE nombre = 'Monitor Gamer 27 pulgadas';

-- FASE 5 - PASO 5.4 (enunciado 8.4) | Donde: PostgreSQL local | Verificar via tabla foranea los 10 registros (5 INSERT, 3 UPDATE, 2 DELETE)
SELECT
    id,
    operacion,
    tabla_origen,
    registro_id,
    datos_anteriores,
    datos_nuevos,
    fecha_hora
FROM audit_log_crdb
ORDER BY fecha_hora ASC;

-- FASE 5 - PASO 5.5 (enunciado 8.5) | Donde: CockroachDB  | Verificar directamente en la nube los mismos 10 registros
SELECT
    id,
    operacion,
    tabla_origen,
    registro_id,
    datos_anteriores,
    datos_nuevos,
    fecha_hora
FROM audit_log
ORDER BY fecha_hora ASC;

-- FASE 5 - PASO 5.6 (enunciado 8.6) | Donde: PostgreSQL local | Detalle de los UPDATE con precio anterior y precio nuevo
SELECT
    registro_id,
    datos_anteriores->>'nombre' AS producto,
    datos_anteriores->>'precio' AS precio_anterior,
    datos_nuevos->>'precio'     AS precio_nuevo,
    fecha_hora
FROM audit_log_crdb
WHERE operacion = 'UPDATE'
ORDER BY fecha_hora ASC;