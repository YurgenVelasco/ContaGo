# Backend de ContaGo 1.0

Fundación NestJS con TypeScript estricto y conectividad a PostgreSQL mediante `pg`. Los únicos endpoints de esta fase son los de salud. Los módulos de autenticación, usuarios, negocios y membresías reservan la estructura para la siguiente fase.

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

## Documentación

- [Arquitectura](docs/arquitectura.md)
- [Contrato PostgreSQL e introspección](docs/postgresql.md)
- [Autenticación y autorización para la fase 2.1](docs/seguridad.md)

