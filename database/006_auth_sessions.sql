BEGIN;
SET LOCAL search_path = contago, pg_catalog;

CREATE TABLE sesiones (
    token_hash bytea PRIMARY KEY CHECK (octet_length(token_hash) = 32),
    usuario_id uuid NOT NULL REFERENCES usuarios(id),
    creada_en timestamptz NOT NULL,
    expira_en timestamptz NOT NULL CHECK (expira_en > creada_en),
    revocada_en timestamptz
);
CREATE INDEX sesiones_activas_usuario ON sesiones(usuario_id) WHERE revocada_en IS NULL;
CREATE INDEX sesiones_expiracion ON sesiones(expira_en);
REVOKE ALL ON sesiones FROM PUBLIC, contago_auth, contago_app, contago_sa;

CREATE FUNCTION auth_crear_sesion(p_usuario uuid, p_hash_verificado text, p_token bytea)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE
    v_ahora timestamptz;
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'Use READ COMMITTED' USING ERRCODE = '25000';
    END IF;
    PERFORM 1 FROM usuarios WHERE id = p_usuario AND habilitado AND hash_contrasena = p_hash_verificado
        FOR NO KEY UPDATE;
    IF NOT FOUND THEN RETURN NULL; END IF;
    v_ahora := clock_timestamp();
    INSERT INTO sesiones (token_hash, usuario_id, creada_en, expira_en)
    VALUES (p_token, p_usuario, v_ahora, v_ahora + interval '8 hours');
    RETURN v_ahora + interval '8 hours';
END;
$$;

CREATE FUNCTION auth_identidad(p_token bytea) RETURNS TABLE (id uuid, correo text, es_sa boolean)
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
    SELECT u.id, u.correo, u.es_sa
    FROM sesiones s JOIN usuarios u ON u.id = s.usuario_id
    WHERE s.token_hash = p_token AND s.revocada_en IS NULL
      AND s.expira_en > clock_timestamp() AND u.habilitado;
$$;

-- Todas las escrituras de sesión por usuario toman primero este mismo bloqueo.
CREATE FUNCTION auth_bloquear_sesion(p_token bytea) RETURNS uuid
LANGUAGE plpgsql SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE v_usuario uuid;
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'Use READ COMMITTED' USING ERRCODE = '25000';
    END IF;
    SELECT u.id INTO v_usuario
    FROM usuarios u JOIN sesiones s ON s.usuario_id = u.id
    WHERE s.token_hash = p_token AND u.habilitado FOR NO KEY UPDATE OF u;
    IF NOT FOUND THEN RETURN NULL; END IF;
    PERFORM 1 FROM sesiones WHERE token_hash = p_token AND revocada_en IS NULL
        AND expira_en > clock_timestamp();
    IF NOT FOUND THEN RETURN NULL; END IF;
    RETURN v_usuario;
END;
$$;

CREATE FUNCTION auth_revocar(p_token bytea, p_todas boolean) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE v_usuario uuid := auth_bloquear_sesion(p_token);
BEGIN
    IF v_usuario IS NULL THEN RETURN false; END IF;
    UPDATE sesiones SET revocada_en = clock_timestamp()
    WHERE usuario_id = v_usuario AND revocada_en IS NULL AND (p_todas OR token_hash = p_token);
    RETURN true;
END;
$$;

CREATE FUNCTION auth_cambiar_contrasena(
    p_token bytea, p_hash_verificado text, p_hash_nuevo text, p_token_nuevo bytea
) RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
DECLARE v_usuario uuid := auth_bloquear_sesion(p_token);
BEGIN
    IF v_usuario IS NULL THEN RETURN NULL; END IF;
    UPDATE usuarios SET hash_contrasena = p_hash_nuevo
    WHERE id = v_usuario AND hash_contrasena = p_hash_verificado;
    IF NOT FOUND THEN RETURN NULL; END IF;
    UPDATE sesiones SET revocada_en = clock_timestamp() WHERE usuario_id = v_usuario AND revocada_en IS NULL;
    PERFORM registrar_auditoria(v_usuario, NULL, 'CONTRASENA_CAMBIADA', 'USUARIO', v_usuario);
    RETURN auth_crear_sesion(v_usuario, p_hash_nuevo, p_token_nuevo);
END;
$$;

CREATE FUNCTION auth_revocar_usuario_deshabilitado() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, contago, pg_temp AS $$
BEGIN
    UPDATE sesiones SET revocada_en = clock_timestamp() WHERE usuario_id = NEW.id AND revocada_en IS NULL;
    RETURN NEW;
END;
$$;
CREATE TRIGGER usuarios_revocar_sesiones AFTER UPDATE OF habilitado ON usuarios
    FOR EACH ROW WHEN (OLD.habilitado AND NOT NEW.habilitado)
    EXECUTE FUNCTION auth_revocar_usuario_deshabilitado();

REVOKE ALL ON FUNCTION auth_crear_sesion(uuid,text,bytea), auth_identidad(bytea),
    auth_bloquear_sesion(bytea), auth_revocar(bytea,boolean),
    auth_cambiar_contrasena(bytea,text,text,bytea), auth_revocar_usuario_deshabilitado() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth_crear_sesion(uuid,text,bytea), auth_identidad(bytea),
    auth_revocar(bytea,boolean), auth_cambiar_contrasena(bytea,text,text,bytea) TO contago_auth;
COMMIT;
