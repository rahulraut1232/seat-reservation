param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl
)

$tests = @(
    @{ Name = "Authentication"; Script = ".\scripts\authentication-test.ps1" },
    @{ Name = "Burst / No Double Sell"; Script = ".\scripts\burst-test.ps1" },
    @{ Name = "Per User Limit"; Script = ".\scripts\per-user-limit-test.ps1" },
    @{ Name = "Idempotency Concurrency"; Script = ".\scripts\idempotency-concurrency-test.ps1" },
    @{ Name = "Idempotency Conflict"; Script = ".\scripts\idempotency-conflict-test.ps1" },
    @{ Name = "Multi Seat Atomicity"; Script = ".\scripts\multi-seat-atomicity-test.ps1" },
    @{ Name = "Cancel Ownership"; Script = ".\scripts\cancel-ownership-test.ps1" }
)

$results = @()

foreach ($test in $tests) {

    Write-Host ""
    Write-Host "---------------------------------------------"
    Write-Host "Running: $($test.Name)"
    Write-Host "---------------------------------------------"

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $test.Script `
        -BaseUrl $BaseUrl

    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "PASS: $($test.Name)"
        $results += [PSCustomObject]@{
            Test   = $test.Name
            Result = "PASS"
        }
    }
    else {
        Write-Host ""
        Write-Host "FAIL: $($test.Name)"
        $results += [PSCustomObject]@{
            Test   = $test.Name
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

$passed = ($results | Where-Object { $_.Result -eq "PASS" }).Count
$failed = ($results | Where-Object { $_.Result -eq "FAIL" }).Count
$total  = $results.Count

Write-Host ""
Write-Host "Passed: $passed"
Write-Host "Failed: $failed"
Write-Host "Total : $total"

Write-Host ""
Write-Host "============================================="

if ($failed -eq 0) {
    Write-Host " ALL TESTS PASSED"
    Write-Host "============================================="
    exit 0
}
else {
    Write-Host " TEST SUITE FAILED"
    Write-Host "============================================="
    exit 1
}