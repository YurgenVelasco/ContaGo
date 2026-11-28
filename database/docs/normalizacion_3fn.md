# Revisión de normalización

Sea N el identificador de negocio, U el identificador de usuario e I el identificador local de la fila. La tabla enumera las claves candidatas de cada relación y una cobertura de las dependencias funcionales no triviales sobre atributos persistidos. Los identificadores locales generados como UUID forman una clave con N. No se impone unicidad individual para esos UUID. Las claves de nombre usan la igualdad de PostgreSQL.

| Relación | Claves candidatas y determinantes generales |
|---|---|
| monedas | Código → nombre. |
| usuarios | ID → resto; correo obligatorio único → resto, incluido ID. |
| negocios | ID → nombre, código de moneda, habilitado, creación. El nombre de la moneda está en `monedas`. |
| membresias_negocio | (N, U) → rol, activa, creación. N o U por separado pueden tener varios roles y fechas asociados. |
| categorias | (N, I) → tipo, nombre; (N, tipo, nombre) → I. |
| terceros | (N, I) → nombre. Varios terceros pueden compartir nombre. |
| cuentas_financieras | (N, I) → nombre; (N, nombre) → I. |
| accesos_cuenta | (N, U, cuenta) es la clave completa. No hay atributos no clave. |
| operaciones_financieras | (N, I) → tipo, estado, importe, cuentas, clasificación, contraparte, reversada, registro y resolución. |
| apuntes_cuenta | (N, operación, cuenta) → variación. Una transferencia permite dos variaciones de signo contrario para una operación. El signo es derivable de la variación y no tiene columna propia. |
| obligaciones | (N, I) → contraparte, autor, tipo, concepto, importe y fechas. |
| aplicaciones_pago | (N, I) → operación, obligación, monto, autor y fecha. Una misma operación puede abonar varias veces la misma obligación, con identificadores distintos. |
| auditoria | ID → N, actor, acción, entidad, referencia, detalle e instante. |

Las restricciones sobre apertura y reverso son unicidades **condicionales**. (N, cuenta de destino) identifica una fila de apertura y (N, operación original) identifica un reverso cuando existe. Esos atributos no identifican filas arbitrarias en toda la relación. Las restricciones por estado también son condicionales. El estado fija qué campos deben estar presentes y permite determinar la ausencia de un motivo en ciertas filas. No fija la identidad de quien resolvió ni el instante de resolución.

- **1FN.** Cada fila representa un hecho. Los campos relacionales son escalares y los grupos repetibles se modelan con filas, por ejemplo, los permisos y los abonos. `auditoria.detalle` es un documento de evento de forma variable, almacenado como un único valor. Ninguna regla de integridad, búsqueda por entidad o autorización depende de sus claves internas. Su contenido se limita a los metadatos que emiten las funciones.
- **2FN.** Para cada clave compuesta, ninguno de sus subconjuntos determina un atributo no primo. La misma cuenta local puede existir en varios negocios. Los roles varían por pareja negocio–usuario, el tipo y el nombre clasifican conjuntamente una categoría dentro de un negocio y cada apunte depende tanto de la operación como de la cuenta. Las claves de un solo atributo satisfacen esta condición directamente.
- **3FN.** Para las dependencias generales de la tabla, cada determinante no trivial es una superclave. Por ejemplo, `membresias_negocio` conserva el ID de usuario pero su correo sigue en `usuarios`, y `obligaciones` conserva el ID de tercero pero su nombre sigue en `terceros`. No hay atributos no primos determinados transitivamente por otros atributos no primos. La revisión aplica a las relaciones y a sus dependencias generales, con las restricciones condicionales descritas arriba.

Hay redundancia controlada **entre relaciones y entre eventos**, independiente de la revisión de 3FN por tabla. El identificador N compartido por claves foráneas requiere concordancia declarativa. Los apuntes materializan la proyección monetaria de una operación para consultar el historial por cuenta. Dos triggers diferibles comprueban que cada variación corresponda a la cuenta y al importe de la cabecera. El reverso materializa el evento compensatorio con las direcciones opuestas y la misma cuantía. La función transaccional lo deriva del original y la clave única asegura que se compense una sola vez. El saldo y el pendiente se calculan en consulta y carecen de una columna editable.

