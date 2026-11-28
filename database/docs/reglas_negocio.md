# Reglas de negocio y contrato de seguridad

## Movimientos

- Una cuenta nace con saldo implícito de cero. El administrador puede registrar una apertura positiva una vez por cuenta, incluso si ese asiento se reversa después. Los ingresos y aperturas abonan. Los gastos cargan. Las transferencias generan dos apuntes de igual cuantía, signos opuestos y cuentas distintas del negocio.
- El miembro publica ingresos inmediatamente y envía gastos a aprobación con su cuenta autorizada. La solicitud conserva autor e instante. La aprobación comprueba también que el solicitante mantenga acceso al negocio y, si sigue siendo miembro, a la cuenta. El rechazo exige un motivo y puede cerrar solicitudes de usuarios que perdieron el acceso.
- Los pendientes y rechazados tienen cero apuntes. La resolución adquiere el bloqueo de la operación y permite una sola transición. Si la aprobación falla por saldo, se revierte toda la sentencia y la solicitud sigue pendiente.
- Para contabilizar, la función bloquea las cuentas por UUID ascendente con `FOR NO KEY UPDATE`. Después suma los apuntes de la cuenta de origen en otra sentencia y aplica el débito únicamente con saldo suficiente. Los triggers diferibles comprueban cardinalidad, cuenta, signo e importe al final de la transacción.
- El UUID que pasa el cliente identifica una solicitud de operación o aplicación dentro del negocio. Un reintento con actor y datos idénticos devuelve el mismo UUID. Su reutilización para otra solicitud falla con `23505`. El bloqueo asesor es transaccional. Una colisión de hash solo puede serializar solicitudes independientes.
- El reverso crea una operación confirmada con la misma cuantía y direcciones opuestas. Respeta el saldo disponible, conserva el historial y solo se admite una vez por original. Para corregir un movimiento reversado, registre una nueva operación con un identificador nuevo.

## Obligaciones y abonos

- Los administradores crean obligaciones y aplican importes confirmados. Los ingresos se aplican a cuentas por cobrar y los gastos a cuentas por pagar, con el mismo tercero y dentro del mismo negocio.
- Se bloquea primero la operación de pago y después la obligación. Se comprueba el importe disponible en la operación y el pendiente de la obligación. Un reverso bloquea primero la operación original y luego sus obligaciones afectadas por UUID ascendente antes de contabilizar. Las aplicaciones históricas se conservan y el cálculo del pendiente excluye las ligadas a operaciones reversadas.
- La obligación conserva principal y vencimiento. El pendiente es el principal menos los abonos vigentes. Una corrección de un abono en esta versión usa el reverso del movimiento asociado y, si corresponde, una nueva operación con las aplicaciones corregidas.

## Responsabilidades y límites

| Capa | Controles |
|---|---|
| PostgreSQL | Estados de acceso, roles locales, cuentas autorizadas, revisión de gastos, permisos de ejecución por servicio, visibilidad por actor y negocio, integridad de saldos y abonos, conservación de historial y auditoría transaccional. |
| API de autenticación | Hash seguro, verificación de contraseñas, gestión de sesión y revocación, protección de credenciales, limitación de intentos y validación del correo. Solo el servicio de autenticación recibe hashes. |
| API de negocio y administración | Identificar al actor desde la sesión, respetar la separación de conexiones, parametrizar llamadas y asignar UUID de idempotencia con estabilidad entre reintentos. Tratar una falla de transacción como unidad; reintentar un `40P01` con los mismos UUID. |
| Operación de PostgreSQL | Custodiar cuentas de propietario y de superusuario, separar servicios, revisar pertenencias de roles, restringir la conectividad al servidor y proteger respaldos. |

Los roles de servicio ejecutan funciones con privilegios del propietario y carecen de permisos directos sobre tablas. Las funciones de negocios rechazan usuarios SA incluso si una integración los envía al servicio equivocado. Un usuario habilitado puede listar sus negocios y ver el estado de cada uno. El bloqueo de un negocio impide el acceso financiero a ese negocio. El bloqueo de un usuario impide su autenticación y las llamadas de negocio, sin cambiar el estado de sus negocios.

Las identidades de servicio son de confianza: su capacidad de pasar `p_actor` implica que una conexión de servicio comprometida puede suplantar actores de su ámbito. El propietario sigue teniendo control de mantenimiento sobre el esquema y puede desactivar las defensas. Los accesos normales deben usar exclusivamente las funciones publicadas. La auditoría conserva acciones exitosas en la misma transacción; el componente de autenticación debe auditar intentos fallidos si se requiere ese registro.

Los saldos se calculan sobre el historial. El índice reduce el recorrido a la cuenta, aunque una cuenta con gran volumen requiere evaluación de rendimiento. Las operaciones por lotes que retienen bloqueos de varias llamadas pueden producir interbloqueos; PostgreSQL aborta una transacción para conservar la integridad. La moneda del negocio es inmutable desde las funciones de servicio y el despliegue inicial solo registra COP.

[PostgreSQL: aislamiento de transacciones](https://www.postgresql.org/docs/current/transaction-iso.html) · [PostgreSQL: volatilidad de funciones](https://www.postgresql.org/docs/current/xfunc-volatility.html)

