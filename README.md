# Taller 1: PostgreSQL local + CockroachDB
 
Auditoría distribuida con Foreign Data Wrapper (FDW) y triggers.
Taller práctico de Bases de Datos Distribuidas.
 
## Integrantes
 
- Dorian Alejandro Guisao Ospina
- Ana Isabella Gómez García
- Laura Indabur García
- David Quintero Gallego
## Resumen
 
El taller construye un sistema donde **PostgreSQL local** guarda los datos del negocio (tabla `productos`) y **CockroachDB Serverless en la nube** guarda el historial de cambios (tabla `audit_log`). Un **trigger** registra automáticamente cada INSERT, UPDATE y DELETE sobre `productos` y lo envía a CockroachDB mediante una **tabla foránea** creada con `postgres_fdw`.
 
De esta forma, la auditoría queda separada del negocio, replicada en varios nodos y disponible aunque la máquina local falle.
