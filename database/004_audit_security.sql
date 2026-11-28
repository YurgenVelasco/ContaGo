BEGIN;
SET LOCAL search_path = contago, pg_catalog;

DO $$
DECLARE v_rol text;
BEGIN
    FOREACH v_rol IN ARRAY ARRAY['contago_app', 'contago_auth', 'contago_sa'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_rol) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', v_rol);
        END IF;
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_rol AND
                   (rolcanlogin OR rolsuper OR rolcreaterole OR rolcreatedb OR rolreplication OR rolbypassrls)) THEN
            RAISE EXCEPTION 'Rol incompatible: %', v_rol;
        END IF;
    END LOOP;
END;
$$;

CREATE FUNCTION registrar_usuario(p_correo text, p_hash text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE v_id uuid;
BEGIN
    INSERT INTO usuarios (correo, hash_contrasena) VALUES (lower(btrim(p_correo)), p_hash)
    RETURNING id INTO v_id;
    PERFORM registrar_auditoria(v_id, NULL, 'REGISTRADO', 'USUARIO', v_id);
    RETURN v_id;
END;
$$;

CREATE FUNCTION buscar_credencial(p_correo text)
RETURNS TABLE (id uuid, hash_contrasena text, es_sa boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
    SELECT u.id, u.hash_contrasena, u.es_sa FROM usuarios u
     WHERE u.correo = lower(btrim(p_correo)) AND u.habilitado;
$$;

CREATE FUNCTION crear_negocio(p_actor uuid, p_nombre text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE v_id uuid;
BEGIN
    PERFORM exigir_usuario(p_actor, false);
    INSERT INTO negocios (nombre) VALUES (p_nombre) RETURNING id INTO v_id;
    INSERT INTO membresias_negocio (negocio_id, usuario_id, rol) VALUES (v_id, p_actor, 'ADMINISTRADOR');
    PERFORM registrar_auditoria(p_actor, v_id, 'CREADO', 'NEGOCIO', v_id);
    RETURN v_id;
END;
$$;

CREATE FUNCTION renombrar_negocio(p_actor uuid, p_negocio uuid, p_nombre text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    -- Obtener el bloqueo de escritura antes de comprobar el acceso al negocio.
    PERFORM exigir_usuario(p_actor, false);
    PERFORM 1 FROM negocios WHERE id = p_negocio FOR NO KEY UPDATE;
    PERFORM exigir_acceso(p_actor, p_negocio, true);
    UPDATE negocios SET nombre = p_nombre WHERE id = p_negocio;
    PERFORM registrar_auditoria(p_actor, p_negocio, 'RENOMBRADO', 'NEGOCIO', p_negocio);
END;
$$;

CREATE FUNCTION gestionar_membresia(
    p_actor uuid, p_negocio uuid, p_usuario uuid, p_rol rol_negocio, p_activa boolean
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    PERFORM exigir_acceso(p_actor, p_negocio, true);
    IF p_usuario = p_actor THEN
        RAISE EXCEPTION 'Un administrador no modifica su propia membresia' USING ERRCODE = '42501';
    END IF;
    PERFORM 1 FROM usuarios WHERE id = p_usuario AND NOT es_sa;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuario no incorporable' USING ERRCODE = '42501';
    END IF;
    INSERT INTO membresias_negocio (negocio_id, usuario_id, rol, activa)
    VALUES (p_negocio, p_usuario, p_rol, p_activa)
    ON CONFLICT (negocio_id, usuario_id) DO UPDATE SET rol = EXCLUDED.rol, activa = EXCLUDED.activa;
    IF p_rol <> 'MIEMBRO' OR NOT p_activa THEN
        DELETE FROM accesos_cuenta WHERE negocio_id = p_negocio AND usuario_id = p_usuario;
    END IF;
    PERFORM registrar_auditoria(p_actor, p_negocio, 'CONFIGURADA', 'MEMBRESIA', p_usuario,
                               jsonb_build_object('rol', p_rol, 'activa', p_activa));
END;
$$;

CREATE FUNCTION autorizar_cuenta(
    p_actor uuid, p_negocio uuid, p_usuario uuid, p_cuenta uuid, p_permiso boolean
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    PERFORM exigir_acceso(p_actor, p_negocio, true);
    PERFORM 1 FROM membresias_negocio
     WHERE negocio_id = p_negocio AND usuario_id = p_usuario AND activa AND rol = 'MIEMBRO' FOR SHARE;
    IF NOT FOUND OR p_permiso IS NULL THEN
        RAISE EXCEPTION 'Permiso o membresia invalida' USING ERRCODE = '42501';
    END IF;
    PERFORM 1 FROM cuentas_financieras WHERE negocio_id = p_negocio AND id = p_cuenta;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cuenta fuera del negocio' USING ERRCODE = '23503';
    END IF;
    IF p_permiso THEN
        INSERT INTO accesos_cuenta VALUES (p_negocio, p_usuario, p_cuenta) ON CONFLICT DO NOTHING;
    ELSE
        DELETE FROM accesos_cuenta
         WHERE negocio_id = p_negocio AND usuario_id = p_usuario AND cuenta_id = p_cuenta;
    END IF;
    PERFORM registrar_auditoria(p_actor, p_negocio, 'CONFIGURADO', 'ACCESO_CUENTA', p_cuenta,
                               jsonb_build_object('usuario_id', p_usuario, 'autorizado', p_permiso));
END;
$$;

CREATE FUNCTION crear_cuenta(p_actor uuid, p_negocio uuid, p_nombre text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE v_id uuid;
BEGIN
    PERFORM exigir_acceso(p_actor, p_negocio, true);
    INSERT INTO cuentas_financieras (negocio_id, nombre) VALUES (p_negocio, p_nombre) RETURNING id INTO v_id;
    PERFORM registrar_auditoria(p_actor, p_negocio, 'CREADA', 'CUENTA', v_id);
    RETURN v_id;
END;
$$;

CREATE FUNCTION crear_categoria(p_actor uuid, p_negocio uuid, p_tipo tipo_categoria, p_nombre text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE v_id uuid;
BEGIN
    PERFORM exigir_acceso(p_actor, p_negocio, true);
    INSERT INTO categorias (negocio_id, tipo, nombre) VALUES (p_negocio, p_tipo, p_nombre) RETURNING id INTO v_id;
    PERFORM registrar_auditoria(p_actor, p_negocio, 'CREADA', 'CATEGORIA', v_id);
    RETURN v_id;
END;
$$;

CREATE FUNCTION crear_tercero(p_actor uuid, p_negocio uuid, p_nombre text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE v_id uuid;
BEGIN
    PERFORM exigir_acceso(p_actor, p_negocio, true);
    INSERT INTO terceros (negocio_id, nombre) VALUES (p_negocio, p_nombre) RETURNING id INTO v_id;
    PERFORM registrar_auditoria(p_actor, p_negocio, 'CREADO', 'TERCERO', v_id);
    RETURN v_id;
END;
$$;

CREATE FUNCTION listar_negocios(p_actor uuid)
RETURNS TABLE (id uuid, nombre text, habilitado boolean, rol rol_negocio)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    PERFORM exigir_usuario(p_actor, false);
    RETURN QUERY SELECT n.id, n.nombre, n.habilitado, m.rol FROM negocios n
        JOIN membresias_negocio m ON m.negocio_id = n.id
        WHERE m.usuario_id = p_actor AND m.activa ORDER BY n.nombre, n.id;
END;
$$;

CREATE FUNCTION listar_movimientos(
    p_actor uuid, p_negocio uuid, p_limite integer DEFAULT 100,
    p_antes timestamptz DEFAULT NULL, p_antes_id uuid DEFAULT NULL
) RETURNS SETOF operaciones_financieras
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE v_rol rol_negocio;
BEGIN
    v_rol := exigir_acceso(p_actor, p_negocio, false);
    IF p_limite IS NULL OR p_limite NOT BETWEEN 1 AND 500
       OR (p_antes IS NULL) <> (p_antes_id IS NULL) THEN
        RAISE EXCEPTION 'Paginacion invalida' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY SELECT o.* FROM operaciones_financieras o
     WHERE o.negocio_id = p_negocio AND (v_rol = 'ADMINISTRADOR' OR o.registrado_por = p_actor)
       AND (p_antes IS NULL OR (o.registrado_en, o.id) < (p_antes, p_antes_id))
     ORDER BY o.registrado_en DESC, o.id DESC LIMIT p_limite;
END;
$$;

CREATE FUNCTION listar_cuentas(p_actor uuid, p_negocio uuid)
RETURNS TABLE (id uuid, nombre text, saldo numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE v_rol rol_negocio;
BEGIN
    v_rol := exigir_acceso(p_actor, p_negocio, false);
    IF v_rol = 'ADMINISTRADOR' THEN
        RETURN QUERY SELECT c.id, c.nombre, coalesce(sum(a.variacion), 0)
          FROM cuentas_financieras c LEFT JOIN apuntes_cuenta a
            ON a.negocio_id = c.negocio_id AND a.cuenta_id = c.id
         WHERE c.negocio_id = p_negocio GROUP BY c.negocio_id, c.id ORDER BY c.id;
    ELSE
        RETURN QUERY SELECT c.id, c.nombre, NULL::numeric FROM cuentas_financieras c
          JOIN accesos_cuenta a ON a.negocio_id = c.negocio_id AND a.cuenta_id = c.id
         WHERE c.negocio_id = p_negocio AND a.usuario_id = p_actor ORDER BY c.id;
    END IF;
END;
$$;

CREATE FUNCTION listar_catalogos(p_actor uuid, p_negocio uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    PERFORM exigir_acceso(p_actor, p_negocio, false);
    RETURN jsonb_build_object(
        'categorias', (SELECT coalesce(jsonb_agg(to_jsonb(c) - 'negocio_id' ORDER BY c.id), '[]')
                       FROM categorias c WHERE c.negocio_id = p_negocio),
        'terceros', (SELECT coalesce(jsonb_agg(to_jsonb(t) - 'negocio_id' ORDER BY t.id), '[]')
                     FROM terceros t WHERE t.negocio_id = p_negocio)
    );
END;
$$;

CREATE FUNCTION listar_membresias(p_actor uuid, p_negocio uuid)
RETURNS TABLE (usuario_id uuid, correo text, rol rol_negocio, activa boolean, cuentas uuid[])
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    PERFORM exigir_acceso(p_actor, p_negocio, true);
    RETURN QUERY SELECT m.usuario_id, u.correo, m.rol, m.activa, ARRAY(
        SELECT a.cuenta_id FROM accesos_cuenta a
         WHERE a.negocio_id = m.negocio_id AND a.usuario_id = m.usuario_id ORDER BY a.cuenta_id
    ) FROM membresias_negocio m JOIN usuarios u ON u.id = m.usuario_id
      WHERE m.negocio_id = p_negocio ORDER BY u.correo;
END;
$$;

CREATE FUNCTION listar_obligaciones(p_actor uuid, p_negocio uuid)
RETURNS TABLE (obligacion obligaciones, pendiente numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    PERFORM exigir_acceso(p_actor, p_negocio, true);
    RETURN QUERY SELECT o, pendiente_obligacion(o.negocio_id, o.id)
      FROM obligaciones o WHERE o.negocio_id = p_negocio ORDER BY o.vence_el, o.id;
END;
$$;

CREATE FUNCTION listar_aplicaciones(p_actor uuid, p_negocio uuid, p_obligacion uuid)
RETURNS TABLE (aplicacion aplicaciones_pago, reversada boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    PERFORM exigir_acceso(p_actor, p_negocio, true);
    RETURN QUERY SELECT a, EXISTS (
        SELECT 1 FROM operaciones_financieras r
        WHERE r.negocio_id = a.negocio_id AND r.reversa_a_id = a.operacion_id
    ) FROM aplicaciones_pago a WHERE a.negocio_id = p_negocio AND a.obligacion_id = p_obligacion
      ORDER BY a.aplicada_en, a.id;
END;
$$;

CREATE FUNCTION sa_listar_usuarios(p_actor uuid, p_usuario uuid DEFAULT NULL)
RETURNS TABLE (usuario_id uuid, correo text, usuario_habilitado boolean,
               negocio_id uuid, negocio_nombre text, negocio_habilitado boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    PERFORM exigir_usuario(p_actor, true);
    RETURN QUERY SELECT u.id, u.correo, u.habilitado, n.id, n.nombre, n.habilitado FROM usuarios u
      LEFT JOIN membresias_negocio m ON m.usuario_id = u.id
      LEFT JOIN negocios n ON n.id = m.negocio_id
     WHERE p_usuario IS NULL OR u.id = p_usuario ORDER BY u.id, n.id;
END;
$$;

CREATE FUNCTION sa_estado_usuario(p_actor uuid, p_usuario uuid, p_estado boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    IF p_actor = p_usuario THEN
        RAISE EXCEPTION 'Un SA no modifica su propio estado' USING ERRCODE = '42501';
    END IF;
    PERFORM exigir_usuario(p_actor, true);
    UPDATE usuarios SET habilitado = p_estado WHERE id = p_usuario;
    IF NOT FOUND THEN RAISE EXCEPTION 'Usuario inexistente' USING ERRCODE = '22023'; END IF;
    PERFORM registrar_auditoria(p_actor, NULL, 'ESTADO_CAMBIADO', 'USUARIO', p_usuario,
                               jsonb_build_object('habilitado', p_estado));
END;
$$;

CREATE FUNCTION sa_estado_negocio(p_actor uuid, p_negocio uuid, p_estado boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    PERFORM exigir_usuario(p_actor, true);
    UPDATE negocios SET habilitado = p_estado WHERE id = p_negocio;
    IF NOT FOUND THEN RAISE EXCEPTION 'Negocio inexistente' USING ERRCODE = '22023'; END IF;
    PERFORM registrar_auditoria(p_actor, p_negocio, 'ESTADO_CAMBIADO', 'NEGOCIO', p_negocio,
                               jsonb_build_object('habilitado', p_estado));
END;
$$;

CREATE FUNCTION impedir_cambio_historico() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    RAISE EXCEPTION 'El historial es inmutable' USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER apuntes_inmutables BEFORE UPDATE OR DELETE ON apuntes_cuenta
    FOR EACH ROW EXECUTE FUNCTION impedir_cambio_historico();
CREATE TRIGGER aplicaciones_inmutables BEFORE UPDATE OR DELETE ON aplicaciones_pago
    FOR EACH ROW EXECUTE FUNCTION impedir_cambio_historico();
CREATE TRIGGER auditoria_inmutable BEFORE UPDATE OR DELETE ON auditoria
    FOR EACH ROW EXECUTE FUNCTION impedir_cambio_historico();
CREATE TRIGGER usuarios_sin_borrado BEFORE DELETE ON usuarios
    FOR EACH ROW EXECUTE FUNCTION impedir_cambio_historico();
CREATE TRIGGER negocios_sin_borrado BEFORE DELETE ON negocios
    FOR EACH ROW EXECUTE FUNCTION impedir_cambio_historico();
CREATE TRIGGER operaciones_sin_borrado BEFORE DELETE ON operaciones_financieras
    FOR EACH ROW EXECUTE FUNCTION impedir_cambio_historico();

CREATE FUNCTION validar_transicion_operacion() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    IF OLD.estado <> 'PENDIENTE_APROBACION' OR NEW.estado NOT IN ('CONFIRMADA', 'RECHAZADA')
       OR (to_jsonb(OLD) - ARRAY['estado', 'resuelto_por', 'resuelto_en', 'motivo_rechazo'])
          IS DISTINCT FROM
          (to_jsonb(NEW) - ARRAY['estado', 'resuelto_por', 'resuelto_en', 'motivo_rechazo']) THEN
        RAISE EXCEPTION 'Transicion de operacion invalida' USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER operaciones_transicion BEFORE UPDATE ON operaciones_financieras
    FOR EACH ROW EXECUTE FUNCTION validar_transicion_operacion();

CREATE FUNCTION verificar_apuntes() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE
    v_op operaciones_financieras;
    v_id uuid;
    v_total bigint;
    v_validos bigint;
    v_esperados integer := 0;
BEGIN
    IF TG_TABLE_NAME = 'apuntes_cuenta' THEN
        v_id := NEW.operacion_id;
    ELSE
        v_id := NEW.id;
    END IF;
    SELECT * INTO STRICT v_op FROM operaciones_financieras
     WHERE negocio_id = NEW.negocio_id AND id = v_id;
    IF v_op.estado = 'CONFIRMADA' THEN
        v_esperados := (v_op.cuenta_origen_id IS NOT NULL)::integer
                     + (v_op.cuenta_destino_id IS NOT NULL)::integer;
    END IF;
    SELECT count(*), count(*) FILTER (WHERE
        (cuenta_id = v_op.cuenta_origen_id AND variacion = -v_op.monto)
        OR (cuenta_id = v_op.cuenta_destino_id AND variacion = v_op.monto))
      INTO v_total, v_validos FROM apuntes_cuenta
     WHERE negocio_id = v_op.negocio_id AND operacion_id = v_id;
    IF v_total <> v_esperados OR v_validos <> v_esperados THEN
        RAISE EXCEPTION 'Apuntes inconsistentes con la operacion' USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER operaciones_apuntes AFTER INSERT OR UPDATE ON operaciones_financieras
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verificar_apuntes();
CREATE CONSTRAINT TRIGGER apuntes_operacion AFTER INSERT ON apuntes_cuenta
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION verificar_apuntes();

REVOKE ALL ON ALL TABLES IN SCHEMA contago FROM PUBLIC, contago_auth, contago_app, contago_sa;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA contago FROM PUBLIC, contago_auth, contago_app, contago_sa;
REVOKE ALL ON SCHEMA contago FROM PUBLIC, contago_auth, contago_app, contago_sa;
GRANT USAGE ON SCHEMA contago TO contago_auth, contago_app, contago_sa;
GRANT EXECUTE ON FUNCTION registrar_usuario(text, text), buscar_credencial(text) TO contago_auth;
GRANT EXECUTE ON FUNCTION sa_listar_usuarios(uuid, uuid), sa_estado_usuario(uuid, uuid, boolean),
    sa_estado_negocio(uuid, uuid, boolean) TO contago_sa;
GRANT EXECUTE ON FUNCTION
    crear_negocio(uuid, text), renombrar_negocio(uuid, uuid, text),
    gestionar_membresia(uuid, uuid, uuid, rol_negocio, boolean),
    autorizar_cuenta(uuid, uuid, uuid, uuid, boolean), crear_cuenta(uuid, uuid, text),
    crear_categoria(uuid, uuid, tipo_categoria, text), crear_tercero(uuid, uuid, text),
    listar_negocios(uuid), listar_movimientos(uuid, uuid, integer, timestamptz, uuid),
    listar_cuentas(uuid, uuid), listar_catalogos(uuid, uuid), listar_membresias(uuid, uuid),
    listar_obligaciones(uuid, uuid), listar_aplicaciones(uuid, uuid, uuid),
    registrar_operacion(uuid, uuid, uuid, tipo_operacion, numeric, uuid, uuid, uuid, uuid),
    resolver_gasto(uuid, uuid, uuid, boolean, text),
    crear_obligacion(uuid, uuid, uuid, tipo_obligacion, text, numeric, date),
    aplicar_pago(uuid, uuid, uuid, uuid, uuid, numeric), reversar_operacion(uuid, uuid, uuid, uuid)
    TO contago_app;
COMMIT;

