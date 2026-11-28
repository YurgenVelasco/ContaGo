# Contrato de integración PostgreSQL

Se revisaron `001_schema.sql` a `005_seed_catalogs.sql`, el README y los cuatro documentos de `database/docs/`. Las trece tablas son `monedas`, `usuarios`, `negocios`, `membresias_negocio`, `categorias`, `terceros`, `cuentas_financieras`, `accesos_cuenta`, `operaciones_financieras`, `apuntes_cuenta`, `obligaciones`, `aplicaciones_pago` y `auditoria`. Consulte columnas, tipos y cardinalidades en la documentación de la base. Las entidades financieras tienen claves y referencias compuestas que incluyen `negocio_id`. Los roles de negocio pertenecen a `membresias_negocio`. [Diccionario](../../database/docs/diccionario_datos.md) · [Modelo](../../database/docs/modelo_relacional.md)

| Identidad | Acceso |
|---|---|
| Propietario de despliegue | Gestiona esquema, objetos, permisos y catálogo. Sus credenciales pertenecen al proceso de despliegue. |
| LOGIN operativo, miembro de `contago_app` | Ejecuta las funciones publicadas de negocio. El arranque exige los 19 permisos de ejecución y rechaza otros permisos en `contago`. |
| LOGIN de autenticación, miembro de `contago_auth` | Futuro pool con acceso a `registrar_usuario(text,text)` y `buscar_credencial(text)`. |
| LOGIN administrativo, miembro de `contago_sa` | Futuro pool con las tres funciones `sa_*` del script 004. |
| Identidad de introspección | Conexión de desarrollo separada con visibilidad de los metadatos necesarios. Úsela contra una base desechable o de desarrollo. |

## Funciones financieras

`actor` y `negocio` son UUID. El actor proviene de una sesión verificada por el servidor. El negocio es el recurso solicitado y PostgreSQL comprueba el acceso a él. Los argumentos opcionales admiten `NULL` según la firma y las reglas del movimiento.

| Función | Argumentos en orden | Resultado |
|---|---|---|
| `registrar_operacion` | actor, negocio, id UUID, tipo `contago.tipo_operacion`, monto NUMERIC, origen UUID opcional, destino UUID opcional, categoría UUID opcional, tercero UUID opcional | UUID |
| `resolver_gasto` | actor, negocio, id UUID, aprobar boolean, motivo text opcional | void |
| `crear_obligacion` | actor, negocio, tercero UUID, tipo `contago.tipo_obligacion`, concepto text, monto NUMERIC, vencimiento date opcional | UUID |
| `aplicar_pago` | actor, negocio, id UUID, operación UUID, obligación UUID, monto NUMERIC | UUID |
| `reversar_operacion` | actor, negocio, id UUID, original UUID | UUID |

Ejemplo para un futuro servicio NestJS con un cliente `pg` operativo y un actor ya autenticado:

```ts
const { rows } = await client.query<{ id: string }>(
  'SELECT contago.aplicar_pago($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::uuid, $6::numeric) AS id',
  [actor.id, negocioId, solicitudId, operacionId, obligacionId, montoDecimal],
);
```

Use montos como cadenas decimales para preservar precisión. Use parámetros enlazados, SQL de texto fijo y el esquema explícito. En una operación de varias llamadas, obtenga un cliente del pool y úselo para `BEGIN ISOLATION LEVEL READ COMMITTED`, todas las consultas y `COMMIT`. Haga `ROLLBACK` ante error y devuelva el cliente al pool. Conserve los UUID de idempotencia al reintentar una transacción abortada. Las funciones que comprueban acceso exigen `READ COMMITTED`; los triggers de apuntes verifican el resultado al confirmar.

## Prisma

La configuración limita el datasource al esquema `contago`. Desde `backend/`, exporte `PRISMA_INTROSPECTION_URL` para la base de desarrollo y ejecute:

```powershell
pnpm prisma:introspect
```

El comando ejecuta `prisma db pull --print`. Imprime el modelo y deja intacto el archivo `schema.prisma`. La prueba con Prisma 7.10.1 y PostgreSQL 19.0 devolvió 13 modelos y cinco enums. Representó las tres columnas del dominio monto_positivo como Decimal con precisión 18 y escala 2. El modelo impreso conserva la precisión, mientras que PostgreSQL conserva la validación del dominio. Prisma advirtió sobre 15 restricciones CHECK. Las funciones, los triggers diferibles y los permisos quedan a cargo de PostgreSQL. Las migraciones SQL son la fuente de verdad. Utilice los contratos SQL para el runtime y excluya `db push` y las migraciones generadas por Prisma de este esquema. [Introspección de Prisma 7](https://www.prisma.io/docs/orm/v7/prisma-schema/introspection)

