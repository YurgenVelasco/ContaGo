\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = contago, pg_catalog;

CREATE FUNCTION pg_temp.comprobar(p_valor boolean, p_caso text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF p_valor IS DISTINCT FROM true THEN RAISE EXCEPTION 'Fallo: %', p_caso; END IF;
END;
$$;

CREATE FUNCTION pg_temp.rechaza(p_sql text, p_esperado text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'Se esperaba SQLSTATE % en %', p_esperado, p_sql;
EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> p_esperado THEN RAISE; END IF;
END;
$$;

DO $$
DECLARE
    a uuid := registrar_usuario('admin@example.invalid', 'hash_ficticio');
    m uuid := registrar_usuario('miembro@example.invalid', 'hash_ficticio');
    s uuid;
    n uuid := crear_negocio(a, 'Negocio de prueba');
    otro uuid := crear_negocio(m, 'Otro negocio');
    c uuid := crear_cuenta(a, n, 'Caja');
    d uuid := crear_cuenta(a, n, 'Banco');
    ajena uuid := crear_cuenta(m, otro, 'Cuenta ajena');
    cat uuid := crear_categoria(a, n, 'INGRESO', 'Ventas');
    cat_ajena uuid := crear_categoria(m, otro, 'INGRESO', 'Ventas');
    t uuid := crear_tercero(a, n, 'Tercero');
    t_ajeno uuid := crear_tercero(m, otro, 'Otro tercero');
    apertura uuid := gen_random_uuid();
    ingreso uuid := gen_random_uuid();
    gasto uuid := gen_random_uuid();
    rechazo uuid := gen_random_uuid();
    tx uuid := gen_random_uuid();
    reverso uuid := gen_random_uuid();
    rev_ingreso uuid := gen_random_uuid();
    gasto_directo uuid := gen_random_uuid();
    ob uuid := crear_obligacion(a, n, t, 'POR_COBRAR', 'Recibo', 40);
    ob_grande uuid := crear_obligacion(a, n, t, 'POR_COBRAR', 'Recibo mayor', 80);
    ob_pagar uuid := crear_obligacion(a, n, t, 'POR_PAGAR', 'Factura', 12);
    ob_ajena uuid := crear_obligacion(m, otro, t_ajeno, 'POR_COBRAR', 'Recibo ajeno', 50);
    pago uuid := gen_random_uuid();
BEGIN
    PERFORM pg_temp.comprobar((SELECT count(*) = 13 FROM pg_tables WHERE schemaname = 'contago' AND tablename <> 'sesiones'), '13 tablas de fase 1');
    PERFORM pg_temp.comprobar((SELECT count(*) = 13 FROM pg_constraint k JOIN pg_namespace ns ON ns.oid = k.connamespace
        WHERE ns.nspname = 'contago' AND k.contype = 'p'
          AND k.conrelid <> coalesce(to_regclass('contago.sesiones')::oid, 0::oid)), 'claves primarias de fase 1');
    PERFORM pg_temp.comprobar((SELECT count(*) >= 20 AND bool_and(k.convalidated)
        FROM pg_constraint k JOIN pg_namespace ns ON ns.oid = k.connamespace
        WHERE ns.nspname = 'contago' AND k.contype = 'f'), 'claves foraneas validadas');
    PERFORM pg_temp.comprobar((SELECT count(*) = 6 FROM pg_indexes WHERE schemaname = 'contago'
        AND indexname IN ('operaciones_fecha','operaciones_usuario_fecha','operaciones_estado_fecha',
                          'apuntes_cuenta_saldo','aplicaciones_operacion','aplicaciones_obligacion')), 'indices principales');
    INSERT INTO usuarios (correo, hash_contrasena, es_sa) VALUES ('sa@example.invalid', 'hash_ficticio', true)
    RETURNING id INTO s;

    PERFORM gestionar_membresia(a, n, m, 'MIEMBRO', true);
    PERFORM autorizar_cuenta(a, n, m, c, true);
    PERFORM pg_temp.comprobar((SELECT count(*) = 2 FROM listar_negocios(m)), 'roles distintos por negocio');
    PERFORM registrar_operacion(a, n, apertura, 'APERTURA', 100, NULL, c);
    PERFORM registrar_operacion(a, n, apertura, 'APERTURA', 100, NULL, c);
    PERFORM pg_temp.rechaza(format('SELECT registrar_operacion(%L,%L,%L,%L,101,NULL,%L)',
        a,n,apertura,'APERTURA',c), '23505');
    PERFORM pg_temp.rechaza(format('SELECT registrar_operacion(%L,%L,gen_random_uuid(),%L,1,NULL,%L)',
        a,n,'APERTURA',c), '23505');
    PERFORM pg_temp.rechaza(format('SELECT registrar_operacion(%L,%L,gen_random_uuid(),%L,1.001,NULL,%L)',
        a,n,'INGRESO',c), '23514');
    PERFORM pg_temp.rechaza(format('SELECT registrar_operacion(%L,%L,gen_random_uuid(),%L,%L,NULL,%L)',
        a,n,'INGRESO','NaN',c), '23514');

    PERFORM pg_temp.rechaza(format('SELECT registrar_operacion(%L,%L,gen_random_uuid(),%L,1,NULL,%L)',
        m,n,'INGRESO',d), '42501');
    PERFORM pg_temp.rechaza(format('SELECT registrar_operacion(%L,%L,gen_random_uuid(),%L,1,%L,%L)',
        m,n,'TRANSFERENCIA',c,d), '42501');
    PERFORM pg_temp.rechaza(format('SELECT registrar_operacion(%L,%L,gen_random_uuid(),%L,1,NULL,%L)',
        a,n,'INGRESO',ajena), '23503');
    PERFORM pg_temp.rechaza(format('SELECT registrar_operacion(%L,%L,gen_random_uuid(),%L,1,NULL,%L,%L)',
        a,n,'INGRESO',c,cat_ajena), '23514');
    PERFORM pg_temp.rechaza(format('SELECT registrar_operacion(%L,%L,gen_random_uuid(),%L,1,NULL,%L,NULL,%L)',
        a,n,'INGRESO',c,t_ajeno), '23503');
    PERFORM pg_temp.rechaza(format('SELECT * FROM listar_cuentas(%L,%L)', a,otro), '42501');

    PERFORM registrar_operacion(m, n, ingreso, 'INGRESO', 50, NULL, c, cat, t);
    PERFORM registrar_operacion(m, n, gasto, 'GASTO', 40, c);
    PERFORM registrar_operacion(m, n, rechazo, 'GASTO', 20, c);
    PERFORM pg_temp.comprobar((SELECT saldo = 150 FROM listar_cuentas(a,n) WHERE id = c), 'saldo antes de resolver');
    PERFORM pg_temp.comprobar((SELECT count(*) = 1 AND bool_and(saldo IS NULL) FROM listar_cuentas(m,n)),
        'miembro ve solo cuenta autorizada sin saldo');
    PERFORM pg_temp.comprobar((SELECT count(*) = 3 AND bool_and(registrado_por = m) FROM listar_movimientos(m,n)),
        'solo historial propio');
    PERFORM pg_temp.rechaza(format('SELECT resolver_gasto(%L,%L,%L,true)', m,n,gasto), '42501');

    PERFORM sa_estado_usuario(s, m, false);
    PERFORM pg_temp.comprobar(NOT EXISTS (SELECT 1 FROM buscar_credencial('miembro@example.invalid')),
        'autenticacion deshabilitada');
    PERFORM pg_temp.rechaza(format('SELECT resolver_gasto(%L,%L,%L,true)', a,n,gasto), '42501');
    PERFORM pg_temp.comprobar((SELECT habilitado FROM negocios WHERE id = otro), 'usuario no cambia negocios');
    PERFORM sa_estado_usuario(s, m, true);

    PERFORM sa_estado_negocio(s, n, false);
    PERFORM pg_temp.rechaza(format('SELECT resolver_gasto(%L,%L,%L,true)', a,n,gasto), '42501');
    PERFORM pg_temp.comprobar((SELECT habilitado FROM usuarios WHERE id = a)
        AND (SELECT habilitado FROM negocios WHERE id = otro), 'bloqueo del negocio independiente');
    PERFORM crear_cuenta(m, otro, 'Negocio sigue operativo');
    PERFORM sa_estado_negocio(s, n, true);

    PERFORM resolver_gasto(a, n, gasto, true);
    PERFORM resolver_gasto(a, n, rechazo, false, 'Motivo de prueba');
    PERFORM pg_temp.rechaza(format('SELECT resolver_gasto(%L,%L,%L,true)', a,n,gasto), '55000');
    PERFORM pg_temp.comprobar(NOT EXISTS (SELECT 1 FROM apuntes_cuenta WHERE negocio_id = n AND operacion_id = rechazo),
        'rechazo sin apuntes');
    PERFORM pg_temp.comprobar((SELECT estado = 'RECHAZADA' AND resuelto_por = a AND resuelto_en IS NOT NULL
        AND motivo_rechazo = 'Motivo de prueba' FROM operaciones_financieras WHERE negocio_id = n AND id = rechazo),
        'registro de rechazo');
    PERFORM pg_temp.rechaza(format('SELECT registrar_operacion(%L,%L,gen_random_uuid(),%L,111,%L)',
        a,n,'GASTO',c), '23514');

    PERFORM registrar_operacion(a, n, tx, 'TRANSFERENCIA', 30, c, d);
    PERFORM pg_temp.comprobar((SELECT count(*) = 2 AND sum(variacion) = 0 FROM apuntes_cuenta
        WHERE negocio_id = n AND operacion_id = tx), 'transferencia compensada');
    PERFORM reversar_operacion(a, n, reverso, tx);
    PERFORM reversar_operacion(a, n, reverso, tx);
    PERFORM pg_temp.rechaza(format('SELECT reversar_operacion(%L,%L,gen_random_uuid(),%L)', a,n,tx), '23505');
    PERFORM pg_temp.comprobar((SELECT saldo = 0 FROM listar_cuentas(a,n) WHERE id = d), 'reverso de transferencia');

    PERFORM aplicar_pago(a, n, pago, ingreso, ob, 20);
    PERFORM aplicar_pago(a, n, pago, ingreso, ob, 20);
    PERFORM pg_temp.comprobar((SELECT pendiente = 20 FROM listar_obligaciones(a,n) WHERE (obligacion).id = ob),
        'abono parcial');
    PERFORM pg_temp.rechaza(format('SELECT aplicar_pago(%L,%L,gen_random_uuid(),%L,%L,21)',
        a,n,ingreso,ob), '23514');
    PERFORM pg_temp.rechaza(format('SELECT aplicar_pago(%L,%L,gen_random_uuid(),%L,%L,31)',
        a,n,ingreso,ob_grande), '23514');
    PERFORM pg_temp.rechaza(format('SELECT aplicar_pago(%L,%L,gen_random_uuid(),%L,%L,1)',
        a,n,ingreso,ob_ajena), '23514');
    PERFORM registrar_operacion(a,n,gasto_directo,'GASTO',10,c,NULL,NULL,t);
    PERFORM aplicar_pago(a, n, gen_random_uuid(), gasto_directo, ob_pagar, 7);
    PERFORM pg_temp.comprobar(pendiente_obligacion(n,ob_pagar) = 5, 'cuenta por pagar');
    PERFORM reversar_operacion(a, n, rev_ingreso, ingreso);
    PERFORM pg_temp.comprobar(pendiente_obligacion(n, ob) = 40
        AND (SELECT reversada FROM listar_aplicaciones(a,n,ob)), 'reverso reabre la obligacion');
    PERFORM pg_temp.rechaza(format('SELECT aplicar_pago(%L,%L,gen_random_uuid(),%L,%L,1)',
        a,n,ingreso,ob), '23514');
    PERFORM pg_temp.comprobar((SELECT saldo = 50 FROM listar_cuentas(a,n) WHERE id = c), 'saldo final');
    PERFORM pg_temp.rechaza(format('UPDATE apuntes_cuenta SET variacion = 1 WHERE operacion_id = %L', ingreso), '55000');
    PERFORM pg_temp.rechaza(format('DELETE FROM usuarios WHERE id = %L', s), '55000');
    PERFORM pg_temp.comprobar(EXISTS (SELECT 1 FROM auditoria
        WHERE actor_id = a AND entidad_id = tx AND accion = 'REVERSADA'), 'auditoria de reverso');

    PERFORM set_config('contago.test_sa', s::text, true);
    PERFORM set_config('contago.test_admin', a::text, true);
    PERFORM set_config('contago.test_negocio', n::text, true);
END;
$$;

SET CONSTRAINTS ALL IMMEDIATE;
DO $$
DECLARE
    n uuid := current_setting('contago.test_negocio')::uuid;
    a uuid := current_setting('contago.test_admin')::uuid;
    c uuid;
BEGIN
    SELECT id INTO c FROM cuentas_financieras WHERE negocio_id = n LIMIT 1;
    PERFORM pg_temp.rechaza(format(
        'INSERT INTO operaciones_financieras (negocio_id,id,tipo,estado,monto,cuenta_destino_id,registrado_por,resuelto_por,resuelto_en)
         VALUES (%L,gen_random_uuid(),%L,%L,1,%L,%L,%L,now())', n,'INGRESO','CONFIRMADA',c,a,a), '23514');
END;
$$;
SET CONSTRAINTS ALL DEFERRED;

SET LOCAL ROLE contago_sa;
DO $$
DECLARE
    s uuid := current_setting('contago.test_sa')::uuid;
    n uuid := current_setting('contago.test_negocio')::uuid;
BEGIN
    IF (SELECT count(*) FROM sa_listar_usuarios(s)) < 3 THEN RAISE EXCEPTION 'Listado SA incompleto'; END IF;
    BEGIN PERFORM * FROM listar_cuentas(s,n); RAISE EXCEPTION 'SA obtuvo acceso financiero';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN PERFORM * FROM apuntes_cuenta; RAISE EXCEPTION 'SA obtuvo lectura directa';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$$;
RESET ROLE;

SET LOCAL ROLE contago_app;
DO $$
DECLARE
    a uuid := current_setting('contago.test_admin')::uuid;
    n uuid := current_setting('contago.test_negocio')::uuid;
    c uuid;
BEGIN
    c := crear_cuenta(a,n,'Prueba con rol de servicio');
    PERFORM registrar_operacion(a,n,gen_random_uuid(),'APERTURA',13,NULL,c);
    BEGIN UPDATE cuentas_financieras SET nombre = 'Cambio directo'; RAISE EXCEPTION 'DML directo autorizado';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN PERFORM * FROM buscar_credencial('admin@example.invalid'); RAISE EXCEPTION 'Acceso a credenciales';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$$;
SET CONSTRAINTS ALL IMMEDIATE;
RESET ROLE;

SET LOCAL ROLE contago_auth;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM buscar_credencial('ADMIN@example.invalid')) THEN
        RAISE EXCEPTION 'No se encontro credencial';
    END IF;
    BEGIN PERFORM crear_negocio(gen_random_uuid(),'Prohibido'); RAISE EXCEPTION 'Auth obtuvo permisos de negocio';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$$;
RESET ROLE;
ROLLBACK;
\echo OK pruebas de integridad y permisos; datos de prueba revertidos

