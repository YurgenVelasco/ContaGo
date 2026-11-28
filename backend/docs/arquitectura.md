# Arquitectura del backend

```text
backend/
  src/
    app.module.ts
    main.ts
    config/
    database/
    health/
    common/
    auth/
    users/
    businesses/
    memberships/
  tests/
  prisma/
  prisma.config.ts
```

- `config` valida los parámetros de arranque y los publica mediante un proveedor de Nest. Los mensajes de configuración identifican la variable y omiten su valor.
- `database` crea un único pool de negocio, comprueba el contrato de permisos en el arranque y cierra las conexiones al detenerse. Usa tiempos máximos de conexión y de consulta, y un `search_path` de sesión acotado. Las llamadas al esquema deben estar calificadas.
- `health` comprueba disponibilidad del proceso y del enlace a PostgreSQL. La respuesta HTTP omite roles, nombres de la base, consultas y detalles de fallos. La comprobación completa de permisos ocurre en el arranque. Reinicie y verifique después de cambios de permisos o migraciones.
- `auth`, `users`, `businesses` y `memberships` definen los límites de módulos futuros. `common` reserva la ubicación de componentes transversales con consumidores reales.

PostgreSQL conserva el control de autorizaciones por negocio y de transacciones financieras. El backend usa un driver SQL para conservar ese contrato. Prisma es una herramienta de inspección en desarrollo. El despliegue de base de datos se realiza fuera del proceso web con los SQL existentes.

