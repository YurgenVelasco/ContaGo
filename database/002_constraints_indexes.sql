BEGIN;
SET LOCAL search_path = contago, pg_catalog;

ALTER TABLE operaciones_financieras
    ADD CONSTRAINT operacion_cuentas CHECK (
        (tipo IN ('APERTURA', 'INGRESO') AND cuenta_origen_id IS NULL AND cuenta_destino_id IS NOT NULL)
        OR (tipo = 'GASTO' AND cuenta_origen_id IS NOT NULL AND cuenta_destino_id IS NULL)
        OR (tipo = 'TRANSFERENCIA' AND cuenta_origen_id IS NOT NULL AND cuenta_destino_id IS NOT NULL)
        OR (tipo = 'REVERSO' AND (cuenta_origen_id IS NOT NULL OR cuenta_destino_id IS NOT NULL))
    ),
    ADD CONSTRAINT operacion_cuentas_distintas CHECK (cuenta_origen_id IS DISTINCT FROM cuenta_destino_id),
    ADD CONSTRAINT operacion_catalogos CHECK (tipo IN ('INGRESO', 'GASTO') OR (categoria_id IS NULL AND tercero_id IS NULL)),
    ADD CONSTRAINT operacion_reverso CHECK ((tipo = 'REVERSO') = (reversa_a_id IS NOT NULL) AND reversa_a_id IS DISTINCT FROM id),
    ADD CONSTRAINT operacion_resolucion CHECK (
        (estado = 'PENDIENTE_APROBACION' AND tipo = 'GASTO'
            AND resuelto_por IS NULL AND resuelto_en IS NULL AND motivo_rechazo IS NULL)
        OR (estado = 'CONFIRMADA' AND resuelto_por IS NOT NULL AND resuelto_en IS NOT NULL AND motivo_rechazo IS NULL)
        OR (estado = 'RECHAZADA' AND tipo = 'GASTO'
            AND resuelto_por IS NOT NULL AND resuelto_en IS NOT NULL AND motivo_rechazo IS NOT NULL
            AND btrim(motivo_rechazo) <> '')
    );

CREATE UNIQUE INDEX operaciones_apertura_unica
    ON operaciones_financieras (negocio_id, cuenta_destino_id) WHERE tipo = 'APERTURA';
CREATE INDEX membresias_usuario ON membresias_negocio (usuario_id, negocio_id);
CREATE INDEX operaciones_fecha ON operaciones_financieras (negocio_id, registrado_en DESC, id DESC);
CREATE INDEX operaciones_usuario_fecha ON operaciones_financieras (negocio_id, registrado_por, registrado_en DESC, id DESC);
CREATE INDEX operaciones_estado_fecha ON operaciones_financieras (negocio_id, estado, registrado_en DESC, id DESC);
CREATE INDEX apuntes_cuenta_saldo ON apuntes_cuenta (negocio_id, cuenta_id) INCLUDE (variacion);
CREATE INDEX obligaciones_vencimiento ON obligaciones (negocio_id, vence_el, id);
CREATE INDEX aplicaciones_operacion ON aplicaciones_pago (negocio_id, operacion_id) INCLUDE (monto);
CREATE INDEX aplicaciones_obligacion ON aplicaciones_pago (negocio_id, obligacion_id) INCLUDE (monto, operacion_id);
CREATE INDEX auditoria_negocio_fecha ON auditoria (negocio_id, ocurrida_en DESC);
CREATE INDEX auditoria_actor_fecha ON auditoria (actor_id, ocurrida_en DESC);
COMMIT;
