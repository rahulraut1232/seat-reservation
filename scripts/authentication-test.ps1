$ErrorActionPreference = "Stop"

$BaseUrl = "http://localhost:8080"

Write-Host ""
Write-Host "========================================"
Write-Host " Authentication Security Test"
Write-Host "========================================"
Write-Host "Base URL : $BaseUrl"
Write-Host ""

# --------------------------------------------------
# Create a show
# --------------------------------------------------

Write-Host "Creating test show..."

$ShowRequest = @{
    name = "Auth-Test-$(New-Guid)"
    seats = @("A1", "A2", "A3", "A4")
    price_paise = 50000
} | ConvertTo-Json -Compress

$ShowFile = Join-Path $env:TEMP "auth-show-request.json"
$ShowRequest | Set-Content -Path $ShowFile -Encoding UTF8

$ShowResponse = curl.exe `
    -s `
    -X POST `
    "$BaseUrl/shows" `
    -H "Authorization: Bearer auth-admin-user" `
    -H "Content-Type: application/json" `
    --data-binary "@$ShowFile"

$Show = $ShowResponse | ConvertFrom-Json
$ShowId = $Show.id

Write-Host "Created show: $ShowId"
Write-Host ""

# --------------------------------------------------
# Test unauthenticated reservation
# --------------------------------------------------

Write-Host "Step 1: Unauthenticated reservation..."

$ReserveRequest = @{
    seats = @("A1")
    idempotency_key = "auth-test-$(New-Guid)"
} | ConvertTo-Json -Compress

$ReserveFile = Join-Path $env:TEMP "auth-reserve-request.json"
$ReserveRequest | Set-Content -Path $ReserveFile -Encoding UTF8

$ResponseFile = Join-Path $env:TEMP "auth-reserve-response.txt"

& curl.exe `
    -s `
    -o $ResponseFile `
    -w "%{http_code}" `
    -X POST `
    "$BaseUrl/shows/$ShowId/reserve" `
    -H "Content-Type: application/json" `
    --data-binary "@$ReserveFile" |
        Set-Content -Path (Join-Path $env:TEMP "auth-status.txt")

$Status = Get-Content (Join-Path $env:TEMP "auth-status.txt") -Raw
$Status = $Status.Trim()

Write-Host "HTTP status: $Status"

if ($Status -eq "401") {
    Write-Host "PASS: Unauthenticated reservation rejected."
} else {
    Write-Host "FAIL: Expected HTTP 401, got $Status"
    exit 1
}

# --------------------------------------------------
# Test authenticated reservation
# --------------------------------------------------

Write-Host ""
Write-Host "Step 2: Authenticated reservation..."

$AuthenticatedResponseFile =
Join-Path $env:TEMP "auth-reserve-authenticated-response.txt"

$AuthenticatedStatusFile =
Join-Path $env:TEMP "auth-reserve-authenticated-status.txt"

& curl.exe `
    -s `
    -o $AuthenticatedResponseFile `
    -w "%{http_code}" `
    -X POST `
    "$BaseUrl/shows/$ShowId/reserve" `
    -H "Authorization: Bearer auth-user-1" `
    -H "Content-Type: application/json" `
    --data-binary "@$ReserveFile" |
        Set-Content -Path $AuthenticatedStatusFile

$AuthenticatedStatus =
(Get-Content $AuthenticatedStatusFile -Raw).Trim()

Write-Host "HTTP status: $AuthenticatedStatus"

if ($AuthenticatedStatus -eq "201") {
    Write-Host "PASS: Authenticated reservation succeeded."
} else {
    Write-Host "FAIL: Expected HTTP 201, got $AuthenticatedStatus"
    Get-Content $AuthenticatedResponseFile
    exit 1
}

# --------------------------------------------------
# Public GET test
# --------------------------------------------------

Write-Host ""
Write-Host "Step 3: Public GET /shows/{id}..."

$GetStatus = curl.exe `
    -s `
    -o NUL `
    -w "%{http_code}" `
    "$BaseUrl/shows/$ShowId"

$GetStatus = $GetStatus.Trim()

Write-Host "HTTP status: $GetStatus"

if ($GetStatus -eq "200") {
    Write-Host "PASS: Public show lookup works."
} else {
    Write-Host "FAIL: Expected HTTP 200, got $GetStatus"
    exit 1
}

Write-Host ""
Write-Host "========================================"
Write-Host " AUTHENTICATION TEST PASSED"
Write-Host "========================================"