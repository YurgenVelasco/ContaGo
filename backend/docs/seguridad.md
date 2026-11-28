# Autenticación, sesiones y autorización

## Sesiones

El registro normaliza el correo y guarda la contraseña como un hash Argon2id con sal aleatoria, 19 MiB de memoria, dos iteraciones y paralelismo uno. El inicio de sesión responde de forma genérica para una contraseña incorrecta, una cuenta inexistente o una cuenta deshabilitada. El registro acepta contraseñas de al menos 12 caracteres y hasta 512 bytes UTF-8. Los DTO rechazan campos ajenos al contrato.

Cada login genera un token opaco de 32 bytes aleatorios. Solo se almacena su SHA-256 en `contago.sesiones`, junto con usuario, fechas y marca de revocación. La expiración absoluta es de ocho horas. El servidor verifica estado de cuenta, vigencia y revocación en cada petición protegida. El cierre de sesión revoca el token actual. El cierre global revoca todas las sesiones bajo el bloqueo del usuario. El cambio de contraseña verifica la anterior, actualiza el hash, revoca las sesiones anteriores y crea una nueva en la misma transacción.

Deshabilitar una cuenta revoca sus sesiones incluso si después se rehabilita. Una operación que ya pasó el guard puede estar en curso cuando se revoca; PostgreSQL vuelve a comprobar estado y permisos en las funciones de negocio y SA. El servicio de autenticación puede operar sobre hashes mediante funciones específicas. Una conexión de servicio comprometida sigue siendo un riesgo que requiere aislamiento de red y rotación de credenciales. Las sesiones expiradas o revocadas se conservan en esta fase. Defina la retención y la purga en una migración operativa posterior.

La cookie tiene `HttpOnly`, `SameSite=Strict`, `Path=/` y vencimiento. En producción usa `Secure` y el nombre `__Host-contago_session`. Para operaciones de escritura se exige un `Origin` exacto permitido y la cabecera `X-Contago-CSRF: 1`. CORS admite credenciales y los mismos orígenes explícitos. Los clientes web deben usar el mismo sitio para que el navegador envíe la cookie. Registro, login y cambio de contraseña comparten un límite de 20 solicitudes por minuto por IP TCP y 120 por proceso. En un despliegue con réplicas o proxy este contador no es compartido y el proxy puede agrupar los clientes por origen TCP. Configure un control de tasa adicional en el perímetro antes de escalar.

## Matriz

| Acción | Usuario común | Miembro activo | Administrador del negocio | SA global |
|---|---|---|---|---|
| Consultar y gestionar su sesión | Sí | Sí | Sí | Sí |
| Crear negocio propio | Sí | Sí | Sí | Denegado |
| Listar asociaciones propias | Sí | Sí | Sí | Denegado |
| Consultar un negocio habilitado | Requiere membresía | En su negocio | En su negocio | Denegado |
| Renombrar negocio y administrar membresías | Denegado | Denegado | En su negocio | Denegado |
| Consultar directorio administrativo y cambiar estados | Denegado | Denegado | Denegado | Sí |
| Consultar movimientos financieros | Fuera de alcance | Fuera de alcance | Fuera de alcance | Denegado por PostgreSQL |

Cada ruta declara su política. Los guards deniegan rutas sin política y requieren sesión cuando la política así lo indica. Los UUID de URL identifican recursos o usuarios objetivo. El actor, su condición de SA y la membresía efectiva se obtienen del servidor y de PostgreSQL. El estado y el rol de un negocio se comprueban mediante las funciones existentes. Las asociaciones propias pueden listar negocios deshabilitados con su estado. El acceso al detalle y a las acciones requiere un negocio habilitado y membresía activa. Un administrador puede proponer el nuevo rol de otro miembro mediante el DTO de gestión. Su propia autoridad sigue determinada en servidor y la función SQL impide editar su propia membresía.

## Contratos HTTP

Los POST, PUT y PATCH requieren los encabezados de origen y CSRF descritos arriba. Los errores son genéricos y omiten credenciales, hashes, tokens y mensajes SQL. Las operaciones con JSON rechazan propiedades extra y distinguen tipos estrictamente.

| Método y ruta | Entrada | Éxito |
|---|---|---|
| POST `/auth/register` | `{ "correo": "persona@example.invalid", "contrasena": "solo-un-ejemplo-largo" }` | 201, `{ id, correo }` |
| POST `/auth/login` | `{ correo, contrasena }` | 200, `{ id, correo, es_sa }` y cookie |
| GET `/auth/me` | Cookie de sesión | 200, `{ id, correo, es_sa }` |
| POST `/auth/logout` | Cookie de sesión | 204 y cookie expirada |
| POST `/auth/logout-all` | Cookie de sesión | 204 y cookie expirada |
| POST `/auth/change-password` | `{ contrasenaActual, contrasenaNueva }` y cookie | 204 y nueva cookie |
| GET / POST `/businesses` | Cookie; POST con `{ nombre }` | 200 con lista de asociaciones o 201 con `{ id }` |
| GET / PATCH `/businesses/:businessId` | Cookie; PATCH con `{ nombre }` | 200 con `{ id, nombre, habilitado, rol }` o 204 |
| GET `/businesses/:businessId/memberships` | Cookie de administrador local | 200 con membresías |
| PUT `/businesses/:businessId/memberships/:userId` | `{ rol: "MIEMBRO" o "ADMINISTRADOR", activa: boolean }` | 204 |
| GET `/admin/users` | Cookie de SA | 200 con directorio administrativo |
| PATCH `/admin/users/:userId/status` | `{ habilitado: boolean }` | 204 |
| PATCH `/admin/businesses/:businessId/status` | `{ habilitado: boolean }` | 204 |

Los estados previstos incluyen 400 por cuerpo o UUID inválido, 401 por credenciales o sesión inválida, 403 por autorización o CSRF, 409 por correo duplicado, 429 por tasa y 503 si falta una conexión de servicio o falla PostgreSQL.

Referencias de diseño. [OWASP, contraseñas](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) · [OWASP, sesiones](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html) · [OWASP, CSRF](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html)

