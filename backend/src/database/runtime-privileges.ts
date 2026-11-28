// Consultar solo el catálogo. Esta comprobación no ejecuta funciones de negocio.
export const CHECK_RUNTIME_PRIVILEGES = `
  WITH app_functions(signature) AS (
    VALUES
      ('contago.crear_negocio(uuid,text)'),
      ('contago.renombrar_negocio(uuid,uuid,text)'),
      ('contago.gestionar_membresia(uuid,uuid,uuid,contago.rol_negocio,boolean)'),
      ('contago.autorizar_cuenta(uuid,uuid,uuid,uuid,boolean)'),
      ('contago.crear_cuenta(uuid,uuid,text)'),
      ('contago.crear_categoria(uuid,uuid,contago.tipo_categoria,text)'),
      ('contago.crear_tercero(uuid,uuid,text)'),
      ('contago.listar_negocios(uuid)'),
      ('contago.listar_movimientos(uuid,uuid,integer,timestamptz,uuid)'),
      ('contago.listar_cuentas(uuid,uuid)'),
      ('contago.listar_catalogos(uuid,uuid)'),
      ('contago.listar_membresias(uuid,uuid)'),
      ('contago.listar_obligaciones(uuid,uuid)'),
      ('contago.listar_aplicaciones(uuid,uuid,uuid)'),
      ('contago.registrar_operacion(uuid,uuid,uuid,contago.tipo_operacion,numeric,uuid,uuid,uuid,uuid)'),
      ('contago.resolver_gasto(uuid,uuid,uuid,boolean,text)'),
      ('contago.crear_obligacion(uuid,uuid,uuid,contago.tipo_obligacion,text,numeric,date)'),
      ('contago.aplicar_pago(uuid,uuid,uuid,uuid,uuid,numeric)'),
      ('contago.reversar_operacion(uuid,uuid,uuid,uuid)')
  ), expected AS (
    SELECT to_regprocedure(signature)::oid AS oid FROM app_functions
  ), app_schema AS (
    SELECT oid, nspowner FROM pg_namespace WHERE nspname = 'contago'
  )
  SELECT
    EXISTS (SELECT 1 FROM pg_roles AS r WHERE r.rolname = current_user
      AND r.rolcanlogin AND NOT (
        r.rolsuper OR r.rolcreatedb OR r.rolcreaterole OR r.rolreplication OR r.rolbypassrls
      ))
    AND current_user = session_user
    AND current_setting('transaction_isolation') = 'read committed'
    AND NOT has_database_privilege(current_database(), 'CREATE')
    AND EXISTS (SELECT 1 FROM pg_roles AS r WHERE r.rolname = 'contago_app'
      AND NOT (r.rolcanlogin OR r.rolsuper OR r.rolcreatedb OR r.rolcreaterole OR r.rolreplication OR r.rolbypassrls)
      AND pg_has_role(r.oid, 'USAGE'))
    AND NOT EXISTS (SELECT 1 FROM pg_roles AS r
      WHERE r.rolname NOT IN (current_user, 'contago_app') AND pg_has_role(r.oid, 'MEMBER'))
    AND NOT EXISTS (SELECT 1 FROM pg_auth_members AS m JOIN pg_roles AS r ON r.oid = m.member
      WHERE r.rolname IN (current_user, 'contago_app') AND m.admin_option)
    AND NOT EXISTS (SELECT 1 FROM pg_database AS d
      WHERE d.datname = current_database() AND pg_has_role(d.datdba, 'MEMBER'))
    AND EXISTS (SELECT 1 FROM app_schema s
      WHERE has_schema_privilege(s.oid, 'USAGE')
        AND NOT has_schema_privilege(s.oid, 'CREATE,USAGE WITH GRANT OPTION')
        AND NOT pg_has_role(s.nspowner, 'MEMBER'))
    AND NOT EXISTS (
      SELECT 1 FROM pg_class AS c JOIN app_schema AS s ON s.oid = c.relnamespace
      WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f')
        AND (has_table_privilege(c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
          OR has_any_column_privilege(c.oid, 'SELECT,INSERT,UPDATE,REFERENCES')
          OR CASE WHEN current_setting('server_version_num')::integer >= 170000
               THEN has_table_privilege(c.oid, 'MAINTAIN') ELSE false END)
    )
    AND NOT EXISTS (SELECT 1 FROM expected AS e
      WHERE e.oid IS NULL OR NOT has_function_privilege(e.oid, 'EXECUTE')
        OR has_function_privilege(e.oid, 'EXECUTE WITH GRANT OPTION'))
    AND NOT EXISTS (
      SELECT 1 FROM pg_proc AS p JOIN app_schema AS s ON s.oid = p.pronamespace
      WHERE has_function_privilege(p.oid, 'EXECUTE') AND NOT EXISTS (
        SELECT 1 FROM expected AS e WHERE e.oid = p.oid
      )
    ) AS valid;
`;
