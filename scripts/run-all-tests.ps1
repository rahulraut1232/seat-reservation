$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "============================================="
Write-Host " SEAT RESERVATION - FULL TEST SUITE"
Write-Host "============================================="
Write-Host ""

$tests = @(
    @{
        Name = "Authentication"
        Script = ".\scripts\authentication-test.ps1"
    },
    @{
        Name = "Burst / No Double Sell"
        Script = ".\scripts\burst-test.ps1"
    },
    @{
        Name = "Per User Limit"
        Script = ".\scripts\per-user-limit-test.ps1"
    },
    @{
        Name = "Idempotency Concurrency"
        Script = ".\scripts\idempotency-concurrency-test.ps1"
    },
    @{
        Name = "Idempotency Conflict"
        Script = ".\scripts\idempotency-conflict-test.ps1"
    },
    @{
        Name = "Multi Seat Atomicity"
        Script = ".\scripts\multi-seat-atomicity-test.ps1"
    },
    @{
        Name = "Cancel Ownership"
        Script = ".\scripts\cancel-ownership-test.ps1"
    }
)

$passed = 0
$failed = 0

$results = @()

foreach ($test in $tests) {

    Write-Host ""
    Write-Host "---------------------------------------------"
    Write-Host "Running: $($test.Name)"
    Write-Host "---------------------------------------------"

    try {

        & powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $test.Script

        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {

            Write-Host ""
            Write-Host "PASS: $($test.Name)" -ForegroundColor Green

            $passed++

            $results += [PSCustomObject]@{
                Test = $test.Name
                Result = "PASS"
            }
        }
        else {

            Write-Host ""
            Write-Host "FAIL: $($test.Name)" -ForegroundColor Red

            $failed++

            $results += [PSCustomObject]@{
                Test = $test.Name
                Result = "FAIL"
            }
        }
    }
    catch {

        Write-Host ""
        Write-Host "FAIL: $($test.Name)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        $failed++

        $results += [PSCustomObject]@{
            Test = $test.Name
            Result = "FAIL"
        }
    }
}

Write-Host ""
Write-Host "============================================="
Write-Host " TEST SUITE SUMMARY"
Write-Host "============================================="
Write-Host ""

$results | Format-Table -AutoSize

Write-Host "Passed: $passed"
Write-Host "Failed: $failed"
Write-Host "Total : $($tests.Count)"
Write-Host ""

if ($failed -eq 0) {

    Write-Host "============================================="
    Write-Host " ALL TESTS PASSED" -ForegroundColor Green
    Write-Host "============================================="

    exit 0
}
else {

    Write-Host "============================================="
    Write-Host " TEST SUITE FAILED" -ForegroundColor Red
    Write-Host "============================================="

    exit 1
}