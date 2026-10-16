-- FASE 1 - PASO 1.1: PostgreSQL local  
CREATE DATABASE tienda_local;


-- FASE 1 - PASO 1.2: CockroachDB

CREATE DATABASE auditoria_db;
use auditoria_db;


-- FASE 2 - PASO 2.1: Tabla productos en PostgreSQL local, BD tienda_local

CREATE TABLE productos (
    id        SERIAL PRIMARY KEY,
    nombre    VARCHAR(100) NOT NULL,
    precio    DECIMAL(10,2) NOT NULL,
    stock     INT DEFAULT 0,
    categoria VARCHAR(50),
    creado_en TIMESTAMP DEFAULT NOW()
);

-- FASE 2 - PASO 2.2: Tabla audit_log (CockroachDB, BD auditoria_db)
CREATE TABLE audit_log (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    operacion        VARCHAR(10)  NOT NULL,
    tabla_origen     VARCHAR(50)  NOT NULL,
    registro_id      VARCHAR(100),
    datos_anteriores JSONB,
    datos_nuevos     JSONB,
    fecha_hora       TIMESTAMP DEFAULT current_timestamp()
);



-- FASE 3 - PASO 3.1: activar extension en PostgreSQL local 
CREATE EXTENSION IF NOT EXISTS postgres_fdw;



-- FASE 3 - PASO 3.1: activar extension en PostgreSQL local
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE SERVER crdb_server
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (
        host    'taller-2-35277.j77.aws-us-east-1.cockroachlabs.cloud',
        port    '26257',
        dbname  'auditoria_db',
        sslmode 'require'
    );

-- FASE 3 - Paso 3.3: mapeo de usuario (usuario/password del cluster CockroachDB)
CREATE USER MAPPING FOR postgres
    SERVER crdb_server
    OPTIONS (user 'laura', password '----');


-- Paso 3.4: tabla foranea (espejo de audit_log)
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

-- Paso 3.5: verificar conexion (debe devolver 0 filas, sin error)
SELECT * FROM audit_log_crdb;
 

-- FASE 4 TRIGGER DE AUDITORIA (PostgreSQL local)
-- Paso 4.1: funcion del trigger
CREATE OR REPLACE FUNCTION fn_auditoria()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log_crdb
            (id, operacion, tabla_origen, registro_id, datos_anteriores, datos_nuevos, fecha_hora)
        VALUES
            (gen_random_uuid(), 'INSERT', TG_TABLE_NAME, NEW.id::text,
             NULL, row_to_json(NEW)::jsonb, NOW());
        RETURN NEW;
 
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log_crdb
            (id, operacion, tabla_origen, registro_id, datos_anteriores, datos_nuevos, fecha_hora)
        VALUES
            (gen_random_uuid(), 'UPDATE', TG_TABLE_NAME, NEW.id::text,
             row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb, NOW());
        RETURN NEW;
 
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log_crdb
            (id, operacion, tabla_origen, registro_id, datos_anteriores, datos_nuevos, fecha_hora)
        VALUES
            (gen_random_uuid(), 'DELETE', TG_TABLE_NAME, OLD.id::text,
             row_to_json(OLD)::jsonb, NULL, NOW());
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Paso 4.2: asociar el trigger a productos
CREATE TRIGGER trg_auditoria_productos
AFTER INSERT OR UPDATE OR DELETE ON productos
FOR EACH ROW EXECUTE FUNCTION fn_auditoria();


-- FASE 5 - PRUEBAS
 
-- Paso 5.1: 5 INSERT
INSERT INTO productos (nombre, precio, stock, categoria) VALUES ('Raton Inalambrico Logitech', 25.50, 50, 'Accesorios');
INSERT INTO productos (nombre, precio, stock, categoria) VALUES ('Portatil Lenovo Legion', 1200.00, 10, 'Computadores');
INSERT INTO productos (nombre, precio, stock, categoria) VALUES ('Auriculares HyperX Cloud', 75.00, 20, 'Audio');
INSERT INTO productos (nombre, precio, stock, categoria) VALUES ('Monitor Gamer 27 pulgadas', 280.00, 15, 'Monitores');
INSERT INTO productos (nombre, precio, stock, categoria) VALUES ('Teclado Mecanico Redragon', 45.00, 30, 'Accesorios');

 
-- Paso 5.2: 3 UPDATE (cambiar el precio en los tres, para el paso 8.6)
UPDATE productos SET precio = 29.90 WHERE nombre = 'Raton Inalambrico Logitech';
UPDATE productos SET precio = 1150.00 WHERE nombre = 'Portatil Lenovo Legion';
UPDATE productos SET precio = 49.90, stock = 25 WHERE nombre = 'Teclado Mecanico Redragon';

-- Paso 5.3: 2 DELETE
DELETE FROM productos WHERE nombre = 'Auriculares HyperX Cloud';
DELETE FROM productos WHERE nombre = 'Monitor Gamer 27 pulgadas';


-- Paso 5.4: verificacion en PostgreSQL local 
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

-- Paso 5.5
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

