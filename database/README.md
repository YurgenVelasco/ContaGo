# Base de datos ContaGo 1.0

Implementación PostgreSQL en el esquema `contago`. Las migraciones se ejecutan una vez y en orden, sobre una base vacía. Cada archivo tiene su propia transacción. Se requiere PostgreSQL 14 o posterior y `psql`. Use un propietario de despliegue de confianza, con capacidad para crear los roles de grupo del script 004 o con esos roles ya aprovisionados. Los mismos objetos y funciones deben quedar bajo el mismo propietario.

Desde la raíz del repositorio, con un usuario de despliegue y la conexión configurada mediante las opciones de `psql` o las variables estándar de libpq:

```powershell
createdb contago_local
$env:PGDATABASE = 'contago_local'
Get-ChildItem database/00*.sql | Sort-Object Name | ForEach-Object {
    psql -X -v ON_ERROR_STOP=1 -f $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Falló $($_.Name)" }
}
psql -X -v ON_ERROR_STOP=1 -f database/tests/integrity_tests.sql
if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas de integridad' }
pwsh -NoProfile -File database/tests/concurrency_tests.ps1
```

El script de integridad usa una transacción con `ROLLBACK` y cambia a los roles de servicio para probar sus permisos. Ejecútelo sobre una base de pruebas como el propietario, con permiso para asumir los tres roles. El script de concurrencia requiere PowerShell 7, `psql` y privilegio para crear y eliminar su propia base temporal. Instala las migraciones en esa base, verifica que una sesión espera un bloqueo real y elimina la base que creó. Si el clúster es compartido, aprovisione los roles ContaGo antes de las pruebas o use un clúster desechable. Los roles de PostgreSQL tienen alcance de clúster.

Para actualizar una instalación con 001–005 aplicados, ejecute solo 006_auth_sessions.sql como propietario del esquema. Consulte el aprovisionamiento de identidades de ejecución en [el README del backend](../backend/README.md).

## Despliegue e integración

- Cree tres identidades de conexión de servicio y conceda a cada una solo su grupo `NOLOGIN` correspondiente. No use el propietario de las migraciones como identidad de la API. Verifique que los grupos preexistentes y las identidades de servicio no hereden privilegios ajenos.
- Cree el primer usuario SA mediante una operación de aprovisionamiento del propietario. Genere su hash en un componente de autenticación autorizado y entregue el valor por un canal seguro. El registro normal siempre crea usuarios comunes.
- El servicio de autenticación usa `contago_auth`. El módulo administrativo usa `contago_sa` y el módulo de negocios usa `contago_app`. El backend obtiene `p_actor` de la identidad autenticada y nunca lo toma del cuerpo o los parámetros del cliente.
- Use consultas parametrizadas y funciones calificadas con `contago.`. Mantenga `READ COMMITTED` y las restricciones diferibles en su modo inicial para las escrituras. Una transacción puede combinar el registro de un movimiento y sus aplicaciones de pago. Reutilice los mismos UUID de solicitud al reintentar.
- Gestione este DDL con migraciones SQL. Prisma puede introspectar tablas con una identidad de desarrollo de confianza. La aplicación debe llamar las funciones con SQL parametrizado y conservar restricciones, índices, triggers y permisos en las migraciones.

## Archivos

| Archivo | Contenido |
|---|---|
| `001_schema.sql` | Esquema, tipos, tablas y claves foráneas |
| `002_constraints_indexes.sql` | Restricciones de operaciones e índices |
| `003_financial_functions.sql` | Validación de acceso, contabilización, aprobación, pagos y reversos |
| `004_audit_security.sql` | Registro, administración, consultas autorizadas, triggers y permisos |
| `005_seed_catalogs.sql` | Catálogo inicial COP |
| `006_auth_sessions.sql` | Sesiones revocables, funciones privadas de autenticación y revocación al deshabilitar |
| `tests/integrity_tests.sql` | Integridad, aislamiento, estados, reversos y permisos |
| `tests/concurrency_tests.ps1` | Carreras de saldo, idempotencia, aprobación y aplicaciones |
| [Modelo relacional](docs/modelo_relacional.md) | Entidades y cardinalidades |
| [Normalización](docs/normalizacion_3fn.md) | Claves candidatas y dependencias funcionales |
| [Reglas de negocio](docs/reglas_negocio.md) | Semántica, límites y contrato de seguridad |
| [Diccionario de datos](docs/diccionario_datos.md) | Columnas, dominios e índices de consulta |

