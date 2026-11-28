# Backend de ContaGo 1.0

Fundación NestJS con TypeScript estricto y conectividad a PostgreSQL mediante `pg`. La fase 2.1 implementa autenticación por sesión, administración de plataforma y autorización de negocios y membresías.

## Inicio local

1. Instale Node.js 24 LTS (24.11 o superior dentro de la rama 24) y pnpm 11.25.
2. Verifique que la base local se llame `contago_db` y que las migraciones existentes estén instaladas. Si el nombre es distinto, ajuste el tramo final de `DATABASE_URL`. Si la base aún no está preparada, siga la guía de instalación. [Instalación PostgreSQL](../database/README.md)
3. Desde una sesión de mantenimiento con `postgres` o el propietario del despliegue, cree `contago_api` si aún no existe y concédale `contago_app` después de instalar las migraciones. Use `\password` en `psql` para asignar su contraseña sin escribirla en el SQL.

   ```sql
   CREATE ROLE contago_api LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
   GRANT contago_app TO contago_api;
   ```

   ```psql
   \password contago_api
   ```

4. Desde `backend/`, cree `.env` a partir de `.env.example` solo si falta. En `DATABASE_URL`, reemplace `REEMPLAZAR_CONTRASENA` por la contraseña codificada de `contago_api` y ejecute:

   ```powershell
   if (-not (Test-Path -LiteralPath .env)) { Copy-Item .env.example .env }
   pnpm install --frozen-lockfile
   pnpm build
   pnpm start
   ```

La URL del proceso acepta usuario, contraseña, servidor, puerto y base. Codifique solo el valor de la contraseña en UTF-8 con escapes de URL. Por ejemplo, la contraseña ficticia `Ejemplo@19#` se representa como `Ejemplo%4019%23`. Para el runtime, mantenga `DATABASE_URL` sin parámetros ni fragmento. Configure el cifrado con `DATABASE_TLS`. En producción solo se acepta `verify-full`, que valida el certificado del servidor. Para una CA privada, aprovisione su certificado mediante `NODE_EXTRA_CA_CERTS` antes de iniciar Node. El valor `disable` del ejemplo es para la base local de desarrollo. El proceso lee `.env` si existe y las variables ya exportadas tienen precedencia.

| Ruta | Respuesta |
|---|---|
| `GET /health` | `200` mientras el servidor HTTP responde |
| `GET /health/ready` | `200` si PostgreSQL responde y el esquema es accesible, `503` en caso de fallo |

El arranque exige la cuenta de negocio y los permisos del esquema `contago`. Valida el usuario y el grupo efectivos, la ausencia de privilegios directos de tabla y el conjunto de funciones permitido. Ante un error de conexión o configuración, el proceso termina y no anuncia disponibilidad.

Para consultar los nombres reales de las bases y de los roles, use la sesión de mantenimiento. `-W` pide la contraseña de manera interactiva.

```powershell
psql -X -h localhost -p 5432 -U postgres -d postgres -W -c "SELECT datname FROM pg_database WHERE NOT datistemplate ORDER BY datname; SELECT rolname FROM pg_roles WHERE rolname IN ('contago_api', 'contago_app', 'contago_auth', 'contago_sa') ORDER BY rolname;"
```

Con el backend iniciado, `Invoke-RestMethod http://127.0.0.1:3000/health/ready` debe devolver `status: ok`.

## Activar autenticación y administración

Aplique database/006_auth_sessions.sql con el propietario del esquema. En una base nueva ejecute primero 001–005. En una base existente con las 13 tablas aplique solo 006. Esta migración añade la tabla de sesiones, funciones con acceso restringido y un trigger de revocación al deshabilitar un usuario.

Aprovisione dos identidades LOGIN separadas. Estos comandos se ejecutan en una sesión de mantenimiento. Puede usar \password para asignar las contraseñas de manera interactiva.

```sql
CREATE ROLE contago_auth_api LOGIN INHERIT;
GRANT contago_auth TO contago_auth_api;
CREATE ROLE contago_sa_api LOGIN INHERIT;
GRANT contago_sa TO contago_sa_api;
```

Configure las URLs en el .env privado o en el gestor de secretos del despliegue. Las tres apuntan a la misma base y usan el mismo modo TLS. El servidor valida que las identidades sean distintas y que sus permisos correspondan al grupo asignado. Ningún grupo de servicio tiene acceso directo a las tablas del esquema.

| Variable | Propósito |
|---|---|
| AUTH_DATABASE_URL | Conexión LOGIN con contago_auth. Necesaria para activar la autenticación. |
| ADMIN_DATABASE_URL | Conexión LOGIN con contago_sa. Necesaria para activar la administración de plataforma. |
| AUTH_ALLOWED_ORIGINS | Orígenes exactos separados por comas. En desarrollo se permiten por defecto localhost y 127.0.0.1 en el puerto 3000. En producción debe declararse al activar autenticación y los orígenes deben ser HTTPS. |

La configuración de fase 2.0 puede seguir sirviendo salud. Las operaciones que requieren una conexión de servicio ausente devuelven 503. El alta de un SA queda reservada al aprovisionamiento administrativo con un hash Argon2id. La ruta pública de registro crea usuarios comunes.

## Pruebas

```powershell
pnpm build
pnpm lint
pnpm test
```

Para las pruebas de integración, prepare una **base desechable** con los SQL de `database/`, configure `DATABASE_URL` con su cuenta operativa y defina `NODE_ENV=test`. Si también se proporciona `TEST_PRIVILEGED_DATABASE_URL` para esa base desechable, la suite comprueba que el backend rechaza esa cuenta al arrancar. Configure esa variable solo en el entorno de pruebas.

```powershell
$env:NODE_ENV = 'test'
pnpm test:postgres
```

Para las pruebas HTTP de fase 2.1, use PostgreSQL desechable con una base llamada contago_*_test, las migraciones 001–006 y las tres cuentas de servicio indicadas. Exporte NODE_ENV=test, DATABASE_URL, AUTH_DATABASE_URL, ADMIN_DATABASE_URL, DATABASE_TLS=disable para loopback y AUTH_TEST_OWNER_URL para el propietario de esa misma base desechable. Esta última conexión solo se usa para crear y observar fixtures. Ejecute pnpm test:auth y elimine la base de pruebas al terminar. El script usa las variables exportadas, que tienen precedencia sobre cualquier configuración de trabajo.

## Documentación

- [Arquitectura](docs/arquitectura.md)
- [Contrato PostgreSQL e introspección](docs/postgresql.md)
- [Sesiones, matriz de permisos y endpoints](docs/seguridad.md)

