# Ejecutar con PowerShell 7 y una conexion a una base de mantenimiento.
param([string]$Psql = 'psql')
$ErrorActionPreference = 'Stop'
$database = 'contago_pruebas_' + [guid]::NewGuid().ToString('N')
$maintenance = if ($env:PGDATABASE) { $env:PGDATABASE } else { 'postgres' }

function Invoke-Sql([string]$Target, [string]$Sql) {
    $result = & $Psql -X -qAt -v ON_ERROR_STOP=1 -d $Target -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "psql fallo en $Target (salida $LASTEXITCODE)" }
    return $result
}

function Start-Session([string]$Name) {
    $start = [System.Diagnostics.ProcessStartInfo]::new($Psql)
    foreach ($arg in @('-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-d', $database)) {
        $start.ArgumentList.Add($arg)
    }
    $start.Environment['PGAPPNAME'] = $Name
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    return [System.Diagnostics.Process]::Start($start)
}

function Wait-Session([string]$Name, [string]$Condition) {
    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        if ((Invoke-Sql $database "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name='$Name' AND $Condition);") -eq 't') {
            return
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "No se observo la condicion de concurrencia en $Name"
}

function Assert-Blocked([string]$FirstSql, [string]$SecondSql) {
    $first = $null
    $second = $null
    try {
        $first = Start-Session 'contago_prueba_a'
        $first.StandardInput.WriteLine("SET statement_timeout='20s'; SET ROLE contago_app; BEGIN; $FirstSql")
        Wait-Session 'contago_prueba_a' "state='idle in transaction'"
        $second = Start-Session 'contago_prueba_b'
        $second.StandardInput.WriteLine("SET statement_timeout='20s'; SET ROLE contago_app; $SecondSql")
        Wait-Session 'contago_prueba_b' "wait_event_type='Lock'"
        $first.StandardInput.WriteLine('COMMIT;')
        $first.StandardInput.WriteLine('\q')
        $second.StandardInput.WriteLine('\q')
        foreach ($session in @($first, $second)) {
            if (-not $session.WaitForExit(25000)) { throw 'psql no termino' }
            if ($session.ExitCode -ne 0) { throw $session.StandardError.ReadToEnd() }
        }
    } finally {
        foreach ($session in @($first, $second)) {
            if ($null -ne $session) {
                if (-not $session.HasExited) { $session.Kill(); $session.WaitForExit() }
                $session.Dispose()
            }
        }
    }
}

function Expect-Error([string]$Sql, [string]$Code) {
    return 'DO $prueba$ BEGIN ' + $Sql + "; RAISE EXCEPTION 'Se esperaba $Code'; EXCEPTION WHEN SQLSTATE '$Code' THEN NULL; END; " + '$prueba$;'
}

$created = $false
try {
    Invoke-Sql $maintenance "CREATE DATABASE $database;" | Out-Null
    $created = $true
    Get-ChildItem (Join-Path $PSScriptRoot '../00*.sql') | Sort-Object Name | ForEach-Object {
        & $Psql -X -q -v ON_ERROR_STOP=1 -d $database -f $_.FullName
        if ($LASTEXITCODE -ne 0) { throw "No se pudo instalar $($_.Name)" }
    }

    $a = "'10000000-0000-0000-0000-000000000001'"
    $m = "'10000000-0000-0000-0000-000000000002'"
    $n = "'20000000-0000-0000-0000-000000000001'"
    $c = "'30000000-0000-0000-0000-000000000001'"
    $t = "'40000000-0000-0000-0000-000000000001'"
    $o = "'50000000-0000-0000-0000-000000000001'"
    $op = "'60000000-0000-0000-0000-000000000001'"
    $income = "'60000000-0000-0000-0000-000000000002'"
    $otherIncome = "'60000000-0000-0000-0000-000000000003'"
    $expense = "'60000000-0000-0000-0000-000000000004'"
    Invoke-Sql $database @"
        INSERT INTO contago.usuarios(id, correo, hash_contrasena) VALUES
            ($a,'admin@example.invalid','hash_ficticio'), ($m,'miembro@example.invalid','hash_ficticio');
        INSERT INTO contago.negocios(id, nombre) VALUES ($n,'Negocio de prueba');
        INSERT INTO contago.membresias_negocio(negocio_id, usuario_id, rol) VALUES
            ($n,$a,'ADMINISTRADOR'), ($n,$m,'MIEMBRO');
        INSERT INTO contago.cuentas_financieras(negocio_id,id,nombre) VALUES ($n,$c,'Caja');
        INSERT INTO contago.terceros(negocio_id,id,nombre) VALUES ($n,$t,'Tercero');
        INSERT INTO contago.obligaciones(negocio_id,id,tercero_id,creada_por,tipo,concepto,monto)
            VALUES ($n,$o,$t,$a,'POR_COBRAR','Por cobrar',70);
        SELECT contago.registrar_operacion($a,$n,gen_random_uuid(),'APERTURA',100,NULL,$c);
"@ | Out-Null

    $spend = "SELECT contago.registrar_operacion($a,$n,$op,'GASTO',70,$c);"
    $overspend = "PERFORM contago.registrar_operacion($a,$n,gen_random_uuid(),'GASTO',70,$c)"
    Assert-Blocked $spend (Expect-Error $overspend '23514')

    $retry = "SELECT contago.registrar_operacion($a,$n,$income,'INGRESO',50,NULL,$c,NULL,$t);"
    Assert-Blocked $retry $retry

    Invoke-Sql $database @"
        SELECT contago.registrar_operacion($a,$n,$otherIncome,'INGRESO',50,NULL,$c,NULL,$t);
        SELECT contago.autorizar_cuenta($a,$n,$m,$c,true);
        SELECT contago.registrar_operacion($m,$n,$expense,'GASTO',10,$c);
"@ | Out-Null
    Assert-Blocked "SELECT contago.resolver_gasto($a,$n,$expense,true);" (
        Expect-Error "PERFORM contago.resolver_gasto($a,$n,$expense,true)" '55000'
    )
    Assert-Blocked "SELECT contago.aplicar_pago($a,$n,gen_random_uuid(),$income,$o,50);" (
        Expect-Error "PERFORM contago.aplicar_pago($a,$n,gen_random_uuid(),$otherIncome,$o,50)" '23514'
    )

    $valid = Invoke-Sql $database @"
        SELECT (SELECT saldo = 120 FROM contago.listar_cuentas($a,$n) WHERE id=$c)
            AND (SELECT count(*) = 1 FROM contago.apuntes_cuenta WHERE negocio_id=$n AND operacion_id=$income)
            AND (SELECT count(*) = 1 FROM contago.apuntes_cuenta WHERE negocio_id=$n AND operacion_id=$expense)
            AND contago.pendiente_obligacion($n,$o) = 20;
"@
    if ($valid -ne 't') { throw 'El estado final de las carreras no coincide' }
    Write-Output 'OK concurrencia: saldo, idempotencia, aprobacion y limite de obligacion'
} finally {
    if ($created) {
        Invoke-Sql $maintenance "DROP DATABASE $database WITH (FORCE);" | Out-Null
    }
}

