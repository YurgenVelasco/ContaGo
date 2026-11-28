# Modelo relacional

```mermaid
erDiagram
    MONEDAS ||--o{ NEGOCIOS : denomina
    USUARIOS ||--o{ MEMBRESIAS_NEGOCIO : integra
    NEGOCIOS ||--o{ MEMBRESIAS_NEGOCIO : agrupa
    NEGOCIOS ||--o{ CATEGORIAS : define
    NEGOCIOS ||--o{ TERCEROS : registra
    NEGOCIOS ||--o{ CUENTAS_FINANCIERAS : contiene
    MEMBRESIAS_NEGOCIO ||--o{ ACCESOS_CUENTA : recibe
    CUENTAS_FINANCIERAS ||--o{ ACCESOS_CUENTA : autoriza
    MEMBRESIAS_NEGOCIO ||--o{ OPERACIONES_FINANCIERAS : registra
    MEMBRESIAS_NEGOCIO o|--o{ OPERACIONES_FINANCIERAS : resuelve
    CATEGORIAS o|--o{ OPERACIONES_FINANCIERAS : clasifica
    TERCEROS o|--o{ OPERACIONES_FINANCIERAS : participa
    CUENTAS_FINANCIERAS o|--o{ OPERACIONES_FINANCIERAS : cuenta_de_origen
    CUENTAS_FINANCIERAS o|--o{ OPERACIONES_FINANCIERAS : cuenta_de_destino
    OPERACIONES_FINANCIERAS o|--o| OPERACIONES_FINANCIERAS : reversa
    OPERACIONES_FINANCIERAS ||--o{ APUNTES_CUENTA : genera
    CUENTAS_FINANCIERAS ||--o{ APUNTES_CUENTA : recibe
    TERCEROS ||--o{ OBLIGACIONES : contraparte
    MEMBRESIAS_NEGOCIO ||--o{ OBLIGACIONES : crea
    OPERACIONES_FINANCIERAS ||--o{ APLICACIONES_PAGO : financia
    OBLIGACIONES ||--o{ APLICACIONES_PAGO : recibe
    MEMBRESIAS_NEGOCIO ||--o{ APLICACIONES_PAGO : aplica
    USUARIOS ||--o{ AUDITORIA : ejecuta
    NEGOCIOS o|--o{ AUDITORIA : contextualiza
```

| Tabla | Responsabilidad |
|---|---|
| `monedas` | Códigos monetarios y nombres. El catálogo inicial contiene COP. |
| `usuarios` | Identidad, hash y estado administrativo global. |
| `negocios` | Identidad, moneda y estado administrativo independiente. |
| `membresias_negocio` | Usuario, negocio, rol local y vigencia del acceso. |
| `categorias` | Clasificación local de ingresos o gastos. |
| `terceros` | Contrapartes locales de operaciones y obligaciones. |
| `cuentas_financieras` | Cajas y otras cuentas de un negocio. |
| `accesos_cuenta` | Permisos individuales de miembros sobre cuentas. |
| `operaciones_financieras` | Cabecera, importe, estado y resolución de cada movimiento. |
| `apuntes_cuenta` | Eventos inmutables con variaciones firmadas por cuenta. |
| `obligaciones` | Importe original de cuentas por cobrar y pagar. |
| `aplicaciones_pago` | Asignación de un importe de una operación a una obligación. |
| `auditoria` | Actor, instante y referencia a acciones administrativas y financieras. |

Las entidades financieras usan el negocio como parte de sus claves. Por ejemplo, una aplicación apunta a una operación y a una obligación mediante dos referencias que comparten `negocio_id`. Identificadores iguales en negocios distintos pueden existir y sus filas siguen aisladas. Las membresías históricas conservan la atribución aunque se revoque su acceso.

