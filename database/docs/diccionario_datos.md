# Diccionario de datos

Los identificadores son `uuid`. Las fechas de registro y auditoría son `timestamptz`. `vence_el` es una fecha civil opcional. Todos los montos persistidos son `numeric(18,2)`; el dominio `monto_positivo` exige valores finitos estrictamente positivos. `variacion` admite ambos signos y exige un valor distinto de cero.

| Tabla | Campos |
|---|---|
| monedas | `codigo` clave primaria ISO de tres letras; `nombre`. |
| usuarios | `id`, `correo` normalizado y único, `hash_contrasena`, `es_sa`, `habilitado`, `creado_en`. |
| negocios | `id`, `nombre`, `moneda` FK a monedas con valor inicial COP, `habilitado`, `creado_en`. |
| membresias_negocio | `negocio_id`, `usuario_id` forman la PK; `rol`, `activa`, `creada_en`. |
| categorias | `negocio_id`, `id` forman la PK; `tipo`, `nombre` completan la clave alternativa por negocio. |
| terceros | `negocio_id`, `id` forman la PK; `nombre`. |
| cuentas_financieras | `negocio_id`, `id` forman la PK; `nombre` único por negocio. |
| accesos_cuenta | `negocio_id`, `usuario_id`, `cuenta_id` forman la PK; FKs a membresía y cuenta. |
| operaciones_financieras | `negocio_id`, `id` forman la PK; `tipo`, `estado`, `monto`, `cuenta_origen_id`, `cuenta_destino_id`, `categoria_id`, `tercero_id`, `reversa_a_id`, `registrado_por`, `registrado_en`, `resuelto_por`, `resuelto_en`, `motivo_rechazo`. Las cuentas, clasificación, contraparte, reverso y resolución son opcionales según tipo y estado. |
| apuntes_cuenta | `negocio_id`, `operacion_id`, `cuenta_id` forman la PK; `variacion` firmada. |
| obligaciones | `negocio_id`, `id` forman la PK; `tercero_id`, `creada_por`, `tipo`, `concepto`, `monto`, `vence_el`, `creada_en`. |
| aplicaciones_pago | `negocio_id`, `id` forman la PK; `operacion_id`, `obligacion_id`, `monto`, `aplicada_por`, `aplicada_en`. |
| auditoria | `id`, `negocio_id` opcional, `actor_id`, `accion`, `entidad`, `entidad_id`, `detalle` JSONB, `ocurrida_en`. La referencia a la entidad es polimórfica y la escriben las funciones. Las referencias a actor y negocio son FKs. |

Índices de uso frecuente:

- Membresías por usuario y negocio.
- Operaciones por negocio y fecha, por autor y fecha, y por estado y fecha. La paginación usa fecha e ID como cursor.
- Apuntes por negocio y cuenta para sumar el saldo.
- Obligaciones por negocio y vencimiento. Aplicaciones por operación y por obligación para calcular límites.
- Auditoría por negocio o actor y fecha. Un índice parcial impone una apertura por cuenta y una restricción única impone un reverso por operación.

