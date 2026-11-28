# Estrategia de autenticación y autorización

## Sesión y credenciales

- Implementar sesiones opacas generadas criptográficamente y gestionadas en el servidor, con vencimiento absoluto y por inactividad, rotación al autenticar y al cambiar privilegios, y revocación al cerrar sesión o deshabilitar una cuenta. El almacenamiento y cualquier cambio en PostgreSQL se diseñarán y aprobarán en la fase 2.1.
- Transportar el identificador con una cookie `__Host-` con `Secure`, `HttpOnly`, `SameSite` explícito, `Path=/` y sin `Domain`. Servir por HTTPS y proteger las operaciones de escritura contra CSRF. [OWASP Session Management](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html)
- Usar Argon2id con sal aleatoria por contraseña, partiendo de un mínimo de 19 MiB, 2 iteraciones y paralelismo 1. Ajustar el costo con mediciones, aplicar límites de intento y usar errores de autenticación genéricos. Solo el pool `contago_auth` debe consultar hashes. Nunca incluir hashes, identificadores de sesión, contraseñas o URLs de conexión en respuestas y registros. [OWASP Password Storage](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)

## Actor, negocio y privilegios

1. Un guard de sesión resuelve el UUID del actor en el servidor y valida la vigencia de su identidad. Nunca use `usuario_id`, `rol` ni encabezados del cliente como prueba de identidad. Un UUID en el cuerpo puede identificar un usuario **objetivo** de una acción autorizada.
2. Una política de módulo usa el rol global para decidir si permite rutas de SA. Las rutas operativas validan membresía activa y rol específico del negocio. El UUID de negocio recibido identifica el recurso y debe validarse con la sesión.
3. Las funciones PostgreSQL reciben el UUID del actor verificado en `p_actor`. Revalidan el estado administrativo, la membresía y, cuando corresponde, el acceso a la cuenta. El chequeo del servidor web facilita el control de rutas. La función SQL conserva la comprobación que protege la transacción.
4. Los módulos usan pools dedicados con cuentas de privilegios separados y nunca cambian de grupo mediante `SET ROLE` en una conexión compartida. Si se compromete una identidad de servicio, puede suplantar actores dentro de los permisos de su grupo debido al contrato `p_actor`. Restrinja su conectividad, rote el secreto y monitoree el uso.
5. Use parámetros enlazados para valores e identificadores de SQL estáticos. Los errores de PostgreSQL pueden revelar datos internos. Mapee SQLSTATE conocidos a respuestas públicas genéricas, por ejemplo `42501` a un acceso denegado y `23505` a un conflicto cuando corresponda al contexto. Para fallos desconocidos, devuelva un error genérico y registre solo metadatos diagnósticos autorizados.

La fase 2.1 debe validar revocación inmediata, separación SA/negocio, solicitudes cruzadas entre negocios y rechazo de identidades declaradas por el cliente. Las pruebas de producción también deben verificar la cadena TLS y el nombre del servidor.

