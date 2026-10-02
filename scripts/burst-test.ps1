param(
    [string]$BaseUrl = "http://localhost:8080",
    [int]$ConcurrentRequests = 20,
    [string]$Seat = "A1"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Seat Reservation Concurrency Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Base URL : $BaseUrl"
Write-Host "Requests : $ConcurrentRequests"
Write-Host "Seat     : $Seat"
Write-Host ""

# --------------------------------------------------
# 1. Create a fresh show
# --------------------------------------------------

$showName = "Burst-Test-" + [Guid]::NewGuid().ToString()

$showBody = @{
    name        = $showName
    seats       = @("A1", "A2", "A3", "A4")
    price_paise = 50000
} | ConvertTo-Json

$showFile = Join-Path $env:TEMP "burst-show-$([Guid]::NewGuid()).json"

$showBody | Set-Content -Encoding UTF8 $showFile

Write-Host "Creating test show..." -ForegroundColor Yellow

$showResponse = curl.exe `
    -s `
    -X POST `
    "$BaseUrl/shows" `
    -H "Content-Type: application/json" `
    --data-binary "@$showFile"

$show = $showResponse | ConvertFrom-Json
$showId = $show.id

Remove-Item $showFile -Force

Write-Host "Created show: $showId" -ForegroundColor Green
Write-Host ""

# --------------------------------------------------
# 2. Prepare temporary directory
# --------------------------------------------------

Write-Host "Launching $ConcurrentRequests concurrent reservations for $Seat..." -ForegroundColor Yellow
Write-Host ""

$tempDirectory = Join-Path `
    $env:TEMP `
    "seat-burst-$([Guid]::NewGuid())"

New-Item `
    -ItemType Directory `
    -Path $tempDirectory `
    -Force | Out-Null

$jobs = @()

# --------------------------------------------------
# 3. Create request files and background jobs
# --------------------------------------------------

for ($i = 1; $i -le $ConcurrentRequests; $i++) {

    $userId = "burst-user-$i"

    $idempotencyKey = `
        "burst-$i-$([Guid]::NewGuid())"

    $requestId = "burst-$i"

    $requestFile = Join-Path `
        $tempDirectory `
        "request-$i.json"

    $outputFile = Join-Path `
        $tempDirectory `
        "response-$i.txt"

    $requestJson = @"
{
  "seats": ["$Seat"],
  "idempotency_key": "$idempotencyKey"
}
"@

    # IMPORTANT:
    # Write JSON to a file instead of passing JSON
    # through PowerShell command-line quoting.

    $requestJson | Set-Content `
        -Encoding UTF8 `
        -Path $requestFile

    $job = Start-Job -ScriptBlock {

        param(
            $BaseUrl,
            $ShowId,
            $UserId,
            $RequestId,
            $RequestFile,
            $OutputFile
        )

        & curl.exe `
            -s `
            -i `
            -X POST `
            "$BaseUrl/shows/$ShowId/reserve" `
            -H "Authorization: Bearer $UserId" `
            -H "Content-Type: application/json" `
            -H "X-Request-ID: $RequestId" `
            --data-binary "@$RequestFile" `
            > $OutputFile

        [PSCustomObject]@{
            OutputFile = $OutputFile
        }

    } -ArgumentList `
        $BaseUrl,
        $showId,
        $userId,
        $requestId,
        $requestFile,
        $outputFile

    $jobs += [PSCustomObject]@{
        Number     = $i
        Job        = $job
        OutputFile = $outputFile
    }
}

# --------------------------------------------------
# 4. Wait for all requests
# --------------------------------------------------

Write-Host "Waiting for all requests..." -ForegroundColor Yellow

foreach ($item in $jobs) {

    Receive-Job `
        -Job $item.Job `
        -Wait `
        | Out-Null

    Remove-Job `
        -Job $item.Job `
        -Force
}

Write-Host "All requests completed." -ForegroundColor Green
Write-Host ""

# --------------------------------------------------
# 5. Parse responses
# --------------------------------------------------

$results = @()

foreach ($item in $jobs) {

    $content = ""

    if (Test-Path $item.OutputFile) {
        $content = Get-Content `
            $item.OutputFile `
            -Raw
    }

    $status = 0

    if ($content -match "HTTP/\S+\s+(\d+)") {
        $status = [int]$Matches[1]
    }

    $results += [PSCustomObject]@{
        Request  = $item.Number
        Status   = $status
        Response = $content
    }
}

# --------------------------------------------------
# 6. Results
# --------------------------------------------------

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$results |
    Group-Object Status |
    Sort-Object Name |
    ForEach-Object {
        Write-Host (
            "HTTP {0}: {1}" -f $_.Name, $_.Count
        )
    }

$successCount = @(
    $results |
        Where-Object { $_.Status -eq 201 }
).Count

$conflictCount = @(
    $results |
        Where-Object { $_.Status -eq 409 }
).Count

$errorCount = @(
    $results |
        Where-Object { $_.Status -ge 500 }
).Count

Write-Host ""
Write-Host "201 Created : $successCount"
Write-Host "409 Conflict: $conflictCount"
Write-Host "5xx Errors  : $errorCount"
Write-Host ""

# --------------------------------------------------
# 7. Final show state
# --------------------------------------------------

Write-Host "Final show state:" -ForegroundColor Yellow

$showStateResponse = curl.exe `
    -s `
    "$BaseUrl/shows/$showId"

$showState = $showStateResponse | ConvertFrom-Json

$showState |
    ConvertTo-Json `
        -Depth 5

Write-Host ""

$total     = $showState.total_seats
$available = $showState.available_seats
$held      = $showState.held_seats
$confirmed = $showState.confirmed_seats

$invariant = `
    $available +
    $held +
    $confirmed

# --------------------------------------------------
# 8. Assertions
# --------------------------------------------------

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Assertions" -ForegroundColor Cyan
Write-Host "========================================"

$allPassed = $true

if ($successCount -eq 1) {

    Write-Host `
        "PASS: Exactly one request succeeded." `
        -ForegroundColor Green
}
else {

    Write-Host `
        "FAIL: Expected exactly one successful reservation." `
        -ForegroundColor Red

    $allPassed = $false
}

if ($conflictCount -eq ($ConcurrentRequests - 1)) {

    Write-Host `
        "PASS: Remaining requests were rejected with 409." `
        -ForegroundColor Green
}
else {

    Write-Host `
        "FAIL: Unexpected conflict count." `
        -ForegroundColor Red

    $allPassed = $false
}

if ($errorCount -eq 0) {

    Write-Host `
        "PASS: Zero 5xx responses." `
        -ForegroundColor Green
}
else {

    Write-Host `
        "FAIL: 5xx responses detected." `
        -ForegroundColor Red

    $allPassed = $false
}

if ($invariant -eq $total) {

    Write-Host `
        "PASS: Seat invariant holds: $available + $held + $confirmed = $total" `
        -ForegroundColor Green
}
else {

    Write-Host `
        "FAIL: Seat invariant violated." `
        -ForegroundColor Red

    $allPassed = $false
}

Write-Host ""
Write-Host "Show ID: $showId"

if ($allPassed) {

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " CONCURRENCY TEST PASSED" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
}
else {

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host " CONCURRENCY TEST FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
}

Write-Host ""

# --------------------------------------------------
# 9. Cleanup
# --------------------------------------------------

Remove-Item `
    $tempDirectory `
    -Recurse `
    -Force
