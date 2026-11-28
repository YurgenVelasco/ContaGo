BEGIN;
SET LOCAL search_path = contago, pg_catalog;

CREATE FUNCTION exigir_usuario(p_actor uuid, p_sa boolean) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'Use READ COMMITTED' USING ERRCODE = '25000';
    END IF;
    PERFORM 1 FROM usuarios WHERE id = p_actor AND habilitado AND es_sa = p_sa FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuario sin acceso' USING ERRCODE = '42501';
    END IF;
END;
$$;

CREATE FUNCTION exigir_acceso(p_actor uuid, p_negocio uuid, p_admin boolean)
RETURNS rol_negocio LANGUAGE plpgsql SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE v_rol rol_negocio;
BEGIN
    PERFORM exigir_usuario(p_actor, false);
    PERFORM 1 FROM negocios WHERE id = p_negocio AND habilitado FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Negocio sin acceso' USING ERRCODE = '42501';
    END IF;
    SELECT rol INTO v_rol FROM membresias_negocio
     WHERE negocio_id = p_negocio AND usuario_id = p_actor AND activa FOR SHARE;
    IF NOT FOUND OR (p_admin AND v_rol <> 'ADMINISTRADOR') THEN
        RAISE EXCEPTION 'Membresia sin acceso' USING ERRCODE = '42501';
    END IF;
    RETURN v_rol;
END;
$$;

CREATE FUNCTION validar_monto(p_monto numeric) RETURNS monto_positivo
LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    IF p_monto IS NULL OR NOT (p_monto > 0 AND p_monto < 10000000000000000)
       OR p_monto <> round(p_monto, 2) THEN
        RAISE EXCEPTION 'Monto invalido' USING ERRCODE = '23514';
    END IF;
    RETURN p_monto::monto_positivo;
END;
$$;

CREATE FUNCTION registrar_auditoria(
    p_actor uuid, p_negocio uuid, p_accion text, p_entidad text, p_id uuid, p_detalle jsonb DEFAULT '{}'
) RETURNS void LANGUAGE sql SET search_path = pg_catalog, contago, pg_temp AS $$
    INSERT INTO auditoria (actor_id, negocio_id, accion, entidad, entidad_id, detalle)
    VALUES (p_actor, p_negocio, p_accion, p_entidad, p_id, p_detalle);
$$;

CREATE FUNCTION exigir_cuenta_autorizada(p_actor uuid, p_negocio uuid, p_cuenta uuid)
RETURNS void LANGUAGE plpgsql SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    PERFORM 1 FROM accesos_cuenta
     WHERE negocio_id = p_negocio AND usuario_id = p_actor AND cuenta_id = p_cuenta FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cuenta no autorizada' USING ERRCODE = '42501';
    END IF;
END;
$$;

CREATE FUNCTION contabilizar(p_op operaciones_financieras) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE v_saldo numeric;
BEGIN
    IF p_op.estado <> 'CONFIRMADA' THEN
        RAISE EXCEPTION 'Operacion sin confirmar' USING ERRCODE = '23514';
    END IF;
    -- Calcular el saldo en una sentencia separada tras bloquear las cuentas.
    PERFORM id FROM cuentas_financieras
     WHERE negocio_id = p_op.negocio_id AND id IN (p_op.cuenta_origen_id, p_op.cuenta_destino_id)
     ORDER BY id FOR NO KEY UPDATE;
    IF p_op.cuenta_origen_id IS NOT NULL THEN
        SELECT coalesce(sum(variacion), 0) INTO v_saldo FROM apuntes_cuenta
         WHERE negocio_id = p_op.negocio_id AND cuenta_id = p_op.cuenta_origen_id;
        IF v_saldo < p_op.monto THEN
            RAISE EXCEPTION 'Saldo insuficiente' USING ERRCODE = '23514';
        END IF;
        INSERT INTO apuntes_cuenta VALUES (p_op.negocio_id, p_op.id, p_op.cuenta_origen_id, -p_op.monto);
    END IF;
    IF p_op.cuenta_destino_id IS NOT NULL THEN
        INSERT INTO apuntes_cuenta VALUES (p_op.negocio_id, p_op.id, p_op.cuenta_destino_id, p_op.monto);
    END IF;
END;
$$;

CREATE FUNCTION registrar_operacion(
    p_actor uuid, p_negocio uuid, p_id uuid, p_tipo tipo_operacion, p_monto numeric,
    p_origen uuid DEFAULT NULL, p_destino uuid DEFAULT NULL,
    p_categoria uuid DEFAULT NULL, p_tercero uuid DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE
    v_rol rol_negocio;
    v_op operaciones_financieras;
    v_monto monto_positivo := validar_monto(p_monto);
    v_estado estado_operacion := 'CONFIRMADA';
BEGIN
    v_rol := exigir_acceso(p_actor, p_negocio, false);
    IF p_id IS NULL OR p_tipo IS NULL OR p_tipo = 'REVERSO' THEN
        RAISE EXCEPTION 'Identificador o tipo invalido' USING ERRCODE = '23514';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(p_negocio::text || p_id::text, 0));
    SELECT * INTO v_op FROM operaciones_financieras WHERE negocio_id = p_negocio AND id = p_id;
    IF FOUND THEN
        IF ROW(v_op.registrado_por, v_op.tipo, v_op.monto, v_op.cuenta_origen_id, v_op.cuenta_destino_id,
               v_op.categoria_id, v_op.tercero_id)
           IS DISTINCT FROM ROW(p_actor, p_tipo, v_monto, p_origen, p_destino, p_categoria, p_tercero) THEN
            RAISE EXCEPTION 'Identificador ocupado por otra solicitud' USING ERRCODE = '23505';
        END IF;
        RETURN p_id;
    END IF;
    IF v_rol = 'MIEMBRO' THEN
        IF p_tipo NOT IN ('INGRESO', 'GASTO') THEN
            RAISE EXCEPTION 'Tipo reservado al administrador' USING ERRCODE = '42501';
        END IF;
        PERFORM exigir_cuenta_autorizada(p_actor, p_negocio, coalesce(p_origen, p_destino));
        IF p_tipo = 'GASTO' THEN
            v_estado := 'PENDIENTE_APROBACION';
        END IF;
    END IF;
    IF p_categoria IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM categorias WHERE negocio_id = p_negocio AND id = p_categoria AND tipo::text = p_tipo::text
    ) THEN
        RAISE EXCEPTION 'Categoria incompatible o fuera del negocio' USING ERRCODE = '23514';
    END IF;
    INSERT INTO operaciones_financieras
        (negocio_id, id, tipo, estado, monto, cuenta_origen_id, cuenta_destino_id, categoria_id, tercero_id,
         registrado_por, resuelto_por, resuelto_en)
    VALUES (p_negocio, p_id, p_tipo, v_estado, v_monto, p_origen, p_destino, p_categoria, p_tercero,
            p_actor, CASE WHEN v_estado = 'CONFIRMADA' THEN p_actor END,
            CASE WHEN v_estado = 'CONFIRMADA' THEN clock_timestamp() END)
    RETURNING * INTO v_op;
    IF v_estado = 'CONFIRMADA' THEN
        PERFORM contabilizar(v_op);
    END IF;
    PERFORM registrar_auditoria(p_actor, p_negocio, v_estado::text, 'OPERACION', p_id);
    RETURN p_id;
END;
$$;

CREATE FUNCTION resolver_gasto(
    p_actor uuid, p_negocio uuid, p_id uuid, p_aprobar boolean, p_motivo text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE
    v_op operaciones_financieras;
    v_estado estado_operacion;
BEGIN
    PERFORM exigir_acceso(p_actor, p_negocio, true);
    IF p_aprobar IS NULL OR (p_aprobar AND p_motivo IS NOT NULL)
       OR (NOT p_aprobar AND nullif(btrim(p_motivo), '') IS NULL) THEN
        RAISE EXCEPTION 'Resolucion invalida' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO v_op FROM operaciones_financieras
     WHERE negocio_id = p_negocio AND id = p_id FOR NO KEY UPDATE;
    IF NOT FOUND OR v_op.estado <> 'PENDIENTE_APROBACION' THEN
        RAISE EXCEPTION 'Solicitud no pendiente' USING ERRCODE = '55000';
    END IF;
    IF p_aprobar THEN
        IF exigir_acceso(v_op.registrado_por, p_negocio, false) = 'MIEMBRO' THEN
            PERFORM exigir_cuenta_autorizada(v_op.registrado_por, p_negocio, v_op.cuenta_origen_id);
        END IF;
        v_estado := 'CONFIRMADA';
    ELSE
        v_estado := 'RECHAZADA';
    END IF;
    UPDATE operaciones_financieras
       SET estado = v_estado, resuelto_por = p_actor, resuelto_en = clock_timestamp(), motivo_rechazo = p_motivo
     WHERE negocio_id = p_negocio AND id = p_id RETURNING * INTO v_op;
    IF p_aprobar THEN
        PERFORM contabilizar(v_op);
    END IF;
    PERFORM registrar_auditoria(p_actor, p_negocio, v_estado::text, 'OPERACION', p_id);
END;
$$;

CREATE FUNCTION crear_obligacion(
    p_actor uuid, p_negocio uuid, p_tercero uuid, p_tipo tipo_obligacion,
    p_concepto text, p_monto numeric, p_vence date DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE v_id uuid;
BEGIN
    PERFORM exigir_acceso(p_actor, p_negocio, true);
    INSERT INTO obligaciones (negocio_id, tercero_id, creada_por, tipo, concepto, monto, vence_el)
    VALUES (p_negocio, p_tercero, p_actor, p_tipo, p_concepto, validar_monto(p_monto), p_vence)
    RETURNING id INTO v_id;
    PERFORM registrar_auditoria(p_actor, p_negocio, 'CREADA', 'OBLIGACION', v_id);
    RETURN v_id;
END;
$$;

CREATE FUNCTION pendiente_obligacion(p_negocio uuid, p_id uuid) RETURNS numeric
LANGUAGE sql SET search_path = pg_catalog, contago, pg_temp AS $$
    SELECT o.monto - coalesce((
        SELECT sum(a.monto) FROM aplicaciones_pago a
        WHERE a.negocio_id = o.negocio_id AND a.obligacion_id = o.id
          AND NOT EXISTS (
              SELECT 1 FROM operaciones_financieras r
              WHERE r.negocio_id = a.negocio_id AND r.reversa_a_id = a.operacion_id
          )
    ), 0)
    FROM obligaciones o WHERE o.negocio_id = p_negocio AND o.id = p_id;
$$;

CREATE FUNCTION aplicar_pago(
    p_actor uuid, p_negocio uuid, p_id uuid, p_operacion uuid, p_obligacion uuid, p_monto numeric
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE
    v_op operaciones_financieras;
    v_ob obligaciones;
    v_ap aplicaciones_pago;
    v_monto monto_positivo := validar_monto(p_monto);
    v_usado numeric;
BEGIN
    PERFORM exigir_acceso(p_actor, p_negocio, true);
    IF p_id IS NULL THEN
        RAISE EXCEPTION 'Identificador obligatorio' USING ERRCODE = '23502';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(p_negocio::text || p_id::text, 1));
    SELECT * INTO v_ap FROM aplicaciones_pago WHERE negocio_id = p_negocio AND id = p_id;
    IF FOUND THEN
        IF ROW(v_ap.aplicada_por, v_ap.operacion_id, v_ap.obligacion_id, v_ap.monto)
           IS DISTINCT FROM ROW(p_actor, p_operacion, p_obligacion, v_monto) THEN
            RAISE EXCEPTION 'Identificador de pago ocupado' USING ERRCODE = '23505';
        END IF;
        RETURN p_id;
    END IF;
    SELECT * INTO v_op FROM operaciones_financieras
     WHERE negocio_id = p_negocio AND id = p_operacion FOR NO KEY UPDATE;
    IF NOT FOUND OR v_op.estado <> 'CONFIRMADA' OR v_op.tipo NOT IN ('INGRESO', 'GASTO')
       OR EXISTS (SELECT 1 FROM operaciones_financieras
                  WHERE negocio_id = p_negocio AND reversa_a_id = p_operacion) THEN
        RAISE EXCEPTION 'Operacion no aplicable' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO v_ob FROM obligaciones WHERE negocio_id = p_negocio AND id = p_obligacion FOR NO KEY UPDATE;
    IF NOT FOUND OR v_op.tercero_id IS DISTINCT FROM v_ob.tercero_id
       OR (v_op.tipo = 'INGRESO') <> (v_ob.tipo = 'POR_COBRAR') THEN
        RAISE EXCEPTION 'Obligacion incompatible' USING ERRCODE = '23514';
    END IF;
    SELECT coalesce(sum(monto), 0) INTO v_usado FROM aplicaciones_pago
     WHERE negocio_id = p_negocio AND operacion_id = p_operacion;
    IF v_usado + v_monto > v_op.monto OR v_monto > pendiente_obligacion(p_negocio, p_obligacion) THEN
        RAISE EXCEPTION 'Pago excede importe disponible o pendiente' USING ERRCODE = '23514';
    END IF;
    INSERT INTO aplicaciones_pago (negocio_id, id, operacion_id, obligacion_id, monto, aplicada_por)
    VALUES (p_negocio, p_id, p_operacion, p_obligacion, v_monto, p_actor);
    PERFORM registrar_auditoria(p_actor, p_negocio, 'APLICADO', 'APLICACION_PAGO', p_id);
    RETURN p_id;
END;
$$;

CREATE FUNCTION reversar_operacion(p_actor uuid, p_negocio uuid, p_id uuid, p_original uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE
    v_original operaciones_financieras;
    v_reverso operaciones_financieras;
BEGIN
    PERFORM exigir_acceso(p_actor, p_negocio, true);
    IF p_id IS NULL OR p_original IS NULL OR p_id = p_original THEN
        RAISE EXCEPTION 'Identificador de reverso invalido' USING ERRCODE = '23514';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(p_negocio::text || p_id::text, 0));
    SELECT * INTO v_reverso FROM operaciones_financieras WHERE negocio_id = p_negocio AND id = p_id;
    IF FOUND THEN
        IF v_reverso.reversa_a_id IS DISTINCT FROM p_original OR v_reverso.registrado_por <> p_actor THEN
            RAISE EXCEPTION 'Identificador ocupado por otra solicitud' USING ERRCODE = '23505';
        END IF;
        RETURN p_id;
    END IF;
    SELECT * INTO v_original FROM operaciones_financieras
     WHERE negocio_id = p_negocio AND id = p_original FOR NO KEY UPDATE;
    IF NOT FOUND OR v_original.estado <> 'CONFIRMADA' OR v_original.tipo = 'REVERSO' THEN
        RAISE EXCEPTION 'Operacion no reversible' USING ERRCODE = '23514';
    END IF;
    PERFORM o.id FROM obligaciones o
     WHERE o.negocio_id = p_negocio AND EXISTS (
         SELECT 1 FROM aplicaciones_pago a
          WHERE a.negocio_id = o.negocio_id AND a.obligacion_id = o.id AND a.operacion_id = p_original
     )
     ORDER BY o.id FOR NO KEY UPDATE;
    INSERT INTO operaciones_financieras
        (negocio_id, id, tipo, estado, monto, cuenta_origen_id, cuenta_destino_id,
         reversa_a_id, registrado_por, resuelto_por, resuelto_en)
    VALUES (p_negocio, p_id, 'REVERSO', 'CONFIRMADA', v_original.monto,
            v_original.cuenta_destino_id, v_original.cuenta_origen_id, p_original, p_actor, p_actor, clock_timestamp())
    RETURNING * INTO v_reverso;
    PERFORM contabilizar(v_reverso);
    PERFORM registrar_auditoria(p_actor, p_negocio, 'REVERSADA', 'OPERACION', p_original,
                               jsonb_build_object('reverso_id', p_id));
    RETURN p_id;
END;
$$;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA contago FROM PUBLIC;
COMMIT;
