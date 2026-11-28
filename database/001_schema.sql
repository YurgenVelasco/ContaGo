BEGIN;
CREATE SCHEMA contago;
REVOKE ALL ON SCHEMA contago FROM PUBLIC;
SET LOCAL search_path = contago, pg_catalog;

CREATE TYPE rol_negocio AS ENUM ('ADMINISTRADOR', 'MIEMBRO');
CREATE TYPE tipo_operacion AS ENUM ('APERTURA', 'INGRESO', 'GASTO', 'TRANSFERENCIA', 'REVERSO');
CREATE TYPE estado_operacion AS ENUM ('PENDIENTE_APROBACION', 'CONFIRMADA', 'RECHAZADA');
CREATE TYPE tipo_categoria AS ENUM ('INGRESO', 'GASTO');
CREATE TYPE tipo_obligacion AS ENUM ('POR_COBRAR', 'POR_PAGAR');
CREATE DOMAIN monto_positivo AS numeric(18,2)
    CHECK (VALUE > 0 AND VALUE <> 'NaN'::numeric);

CREATE TABLE monedas (
    codigo text PRIMARY KEY CHECK (codigo ~ '^[A-Z]{3}$'),
    nombre text NOT NULL CHECK (btrim(nombre) <> '')
);

CREATE TABLE usuarios (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    correo text NOT NULL UNIQUE CHECK (correo = lower(btrim(correo)) AND strpos(correo, '@') > 1),
    hash_contrasena text NOT NULL CHECK (btrim(hash_contrasena) <> ''),
    es_sa boolean NOT NULL DEFAULT false,
    habilitado boolean NOT NULL DEFAULT true,
    creado_en timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE negocios (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre text NOT NULL CHECK (btrim(nombre) <> ''),
    moneda text NOT NULL DEFAULT 'COP' REFERENCES monedas(codigo),
    habilitado boolean NOT NULL DEFAULT true,
    creado_en timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE membresias_negocio (
    negocio_id uuid REFERENCES negocios(id),
    usuario_id uuid REFERENCES usuarios(id),
    rol rol_negocio NOT NULL,
    activa boolean NOT NULL DEFAULT true,
    creada_en timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (negocio_id, usuario_id)
);

CREATE TABLE categorias (
    negocio_id uuid REFERENCES negocios(id),
    id uuid DEFAULT gen_random_uuid(),
    tipo tipo_categoria NOT NULL,
    nombre text NOT NULL CHECK (btrim(nombre) <> ''),
    PRIMARY KEY (negocio_id, id),
    UNIQUE (negocio_id, tipo, nombre)
);

CREATE TABLE terceros (
    negocio_id uuid REFERENCES negocios(id),
    id uuid DEFAULT gen_random_uuid(),
    nombre text NOT NULL CHECK (btrim(nombre) <> ''),
    PRIMARY KEY (negocio_id, id)
);

CREATE TABLE cuentas_financieras (
    negocio_id uuid REFERENCES negocios(id),
    id uuid DEFAULT gen_random_uuid(),
    nombre text NOT NULL CHECK (btrim(nombre) <> ''),
    PRIMARY KEY (negocio_id, id),
    UNIQUE (negocio_id, nombre)
);

CREATE TABLE accesos_cuenta (
    negocio_id uuid,
    usuario_id uuid,
    cuenta_id uuid,
    PRIMARY KEY (negocio_id, usuario_id, cuenta_id),
    FOREIGN KEY (negocio_id, usuario_id) REFERENCES membresias_negocio,
    FOREIGN KEY (negocio_id, cuenta_id) REFERENCES cuentas_financieras
);

CREATE TABLE operaciones_financieras (
    negocio_id uuid,
    id uuid,
    tipo tipo_operacion NOT NULL,
    estado estado_operacion NOT NULL,
    monto monto_positivo NOT NULL,
    cuenta_origen_id uuid,
    cuenta_destino_id uuid,
    categoria_id uuid,
    tercero_id uuid,
    reversa_a_id uuid,
    registrado_por uuid NOT NULL,
    registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(),
    resuelto_por uuid,
    resuelto_en timestamptz,
    motivo_rechazo text,
    PRIMARY KEY (negocio_id, id),
    UNIQUE (negocio_id, reversa_a_id),
    FOREIGN KEY (negocio_id, cuenta_origen_id) REFERENCES cuentas_financieras,
    FOREIGN KEY (negocio_id, cuenta_destino_id) REFERENCES cuentas_financieras,
    FOREIGN KEY (negocio_id, categoria_id) REFERENCES categorias,
    FOREIGN KEY (negocio_id, tercero_id) REFERENCES terceros,
    FOREIGN KEY (negocio_id, registrado_por) REFERENCES membresias_negocio,
    FOREIGN KEY (negocio_id, resuelto_por) REFERENCES membresias_negocio,
    FOREIGN KEY (negocio_id, reversa_a_id) REFERENCES operaciones_financieras
);

CREATE TABLE apuntes_cuenta (
    negocio_id uuid,
    operacion_id uuid,
    cuenta_id uuid,
    variacion numeric(18,2) NOT NULL CHECK (variacion <> 0 AND variacion <> 'NaN'::numeric),
    PRIMARY KEY (negocio_id, operacion_id, cuenta_id),
    FOREIGN KEY (negocio_id, operacion_id) REFERENCES operaciones_financieras,
    FOREIGN KEY (negocio_id, cuenta_id) REFERENCES cuentas_financieras
);

CREATE TABLE obligaciones (
    negocio_id uuid,
    id uuid DEFAULT gen_random_uuid(),
    tercero_id uuid NOT NULL,
    creada_por uuid NOT NULL,
    tipo tipo_obligacion NOT NULL,
    concepto text NOT NULL CHECK (btrim(concepto) <> ''),
    monto monto_positivo NOT NULL,
    vence_el date,
    creada_en timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (negocio_id, id),
    FOREIGN KEY (negocio_id, tercero_id) REFERENCES terceros,
    FOREIGN KEY (negocio_id, creada_por) REFERENCES membresias_negocio
);

CREATE TABLE aplicaciones_pago (
    negocio_id uuid,
    id uuid,
    operacion_id uuid NOT NULL,
    obligacion_id uuid NOT NULL,
    monto monto_positivo NOT NULL,
    aplicada_por uuid NOT NULL,
    aplicada_en timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (negocio_id, id),
    FOREIGN KEY (negocio_id, operacion_id) REFERENCES operaciones_financieras,
    FOREIGN KEY (negocio_id, obligacion_id) REFERENCES obligaciones,
    FOREIGN KEY (negocio_id, aplicada_por) REFERENCES membresias_negocio
);

CREATE TABLE auditoria (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    negocio_id uuid REFERENCES negocios(id),
    actor_id uuid NOT NULL REFERENCES usuarios(id),
    accion text NOT NULL,
    entidad text NOT NULL,
    entidad_id uuid NOT NULL,
    detalle jsonb NOT NULL DEFAULT '{}',
    ocurrida_en timestamptz NOT NULL DEFAULT clock_timestamp()
);
COMMIT;
