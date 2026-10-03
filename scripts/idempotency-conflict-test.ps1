param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl
)

$ErrorActionPreference = "Stop"

$AdminToken = "idempotency-conflict-admin"
$TestUserToken = "idempotency-conflict-user"

$RequestCount = 2

# Generate a unique idempotency key for every test execution.
$IdempotencyKey = "idem-conflict-$(Get-Date -Format 'yyyyMMddHHmmssfff')"

$TempDir = Join-Path $env:TEMP "seat-idempotency-conflict-test"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

Write-Host "========================================="
Write-Host " IDEMPOTENCY CONFLICT TEST"
Write-Host "========================================="
Write-Host ""

# ---------------------------------------------------------
# 1. Create a fresh show
# ---------------------------------------------------------

$showRequest = @{
    name        = "Idempotency Conflict Show $(Get-Date -Format 'yyyyMMddHHmmssfff')"
    seats       = @("A1", "A2", "A3", "A4")
    price_paise = 10000
} | ConvertTo-Json -Compress

$showRequestFile = Join-Path $TempDir "show-request.json"
$showResponseFile = Join-Path $TempDir "show-response.json"
$showStatusFile = Join-Path $TempDir "show-status.txt"

$showRequest | Set-Content -Path $showRequestFile -Encoding UTF8

Write-Host "Creating test show..."

curl.exe `
    -s `
    -X POST `
    "$BaseUrl/shows" `
    -H "Content-Type: application/json" `
    -H "Authorization: Bearer $AdminToken" `
    --data-binary "@$showRequestFile" `
    -o $showResponseFile `
    -w "%{http_code}" |
        Set-Content -Path $showStatusFile

$showStatus = (Get-Content $showStatusFile -Raw).Trim()

if ($showStatus -ne "201") {
    Write-Host "FAIL: Show creation returned HTTP $showStatus" -ForegroundColor Red
    Get-Content $showResponseFile
    exit 1
}

$showResponse = Get-Content $showResponseFile -Raw | ConvertFrom-Json
$ShowId = $showResponse.id

Write-Host "Show created: $ShowId"
Write-Host "Idempotency Key: $IdempotencyKey"
Write-Host ""

# ---------------------------------------------------------
# 2. First request - A1
# ---------------------------------------------------------

Write-Host "Request 1:"
Write-Host "  Seat: A1"
Write-Host "  Idempotency Key: $IdempotencyKey"
Write-Host ""

$request1 = @{
    seats = @("A1")
    idempotency_key = $IdempotencyKey
} | ConvertTo-Json -Compress

$request1File = Join-Path $TempDir "request-1.json"
$response1File = Join-Path $TempDir "response-1.json"
$status1File = Join-Path $TempDir "status-1.txt"

$request1 | Set-Content -Path $request1File -Encoding UTF8

curl.exe `
    -s `
    -X POST `
    "$BaseUrl/shows/$ShowId/reserve" `
    -H "Content-Type: application/json" `
    -H "Authorization: Bearer $TestUserToken" `
    --data-binary "@$request1File" `
    -o $response1File `
    -w "%{http_code}" |
        Set-Content -Path $status1File

$status1 = (Get-Content $status1File -Raw).Trim()

Write-Host "Request 1 HTTP Status: $status1"

if (Test-Path $response1File) {
    Write-Host "Request 1 Response:"
    Get-Content $response1File
}

Write-Host ""

# ---------------------------------------------------------
# 3. Validate first request
# ---------------------------------------------------------

$failed = $false
$reservationId = $null

if ($status1 -ne "201") {
    Write-Host "FAIL: First request expected HTTP 201, got $status1." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: First request returned HTTP 201." -ForegroundColor Green

    try {
        $response1 = Get-Content $response1File -Raw | ConvertFrom-Json
        $reservationId = $response1.reservation_id
    }
    catch {
        Write-Host "FAIL: Could not parse first reservation response." -ForegroundColor Red
        $failed = $true
    }
}

if ($reservationId) {
    Write-Host "Reservation ID: $reservationId"
}
else {
    Write-Host "FAIL: Reservation ID missing from first response." -ForegroundColor Red
    $failed = $true
}

Write-Host ""

# ---------------------------------------------------------
# 4. Second request - A2 with SAME idempotency key
# ---------------------------------------------------------

Write-Host "Request 2:"
Write-Host "  Seat: A2"
Write-Host "  Idempotency Key: $IdempotencyKey"
Write-Host ""
Write-Host "Expected result: HTTP 409 IDEMPOTENCY_CONFLICT"
Write-Host ""

$request2 = @{
    seats = @("A2")
    idempotency_key = $IdempotencyKey
} | ConvertTo-Json -Compress

$request2File = Join-Path $TempDir "request-2.json"
$response2File = Join-Path $TempDir "response-2.json"
$status2File = Join-Path $TempDir "status-2.txt"

$request2 | Set-Content -Path $request2File -Encoding UTF8

curl.exe `
    -s `
    -X POST `
    "$BaseUrl/shows/$ShowId/reserve" `
    -H "Content-Type: application/json" `
    -H "Authorization: Bearer $TestUserToken" `
    --data-binary "@$request2File" `
    -o $response2File `
    -w "%{http_code}" |
        Set-Content -Path $status2File

$status2 = (Get-Content $status2File -Raw).Trim()

Write-Host "Request 2 HTTP Status: $status2"

if (Test-Path $response2File) {
    Write-Host "Request 2 Response:"
    Get-Content $response2File
}

Write-Host ""

# ---------------------------------------------------------
# 5. Validate conflict
# ---------------------------------------------------------

if ($status2 -ne "409") {
    Write-Host "FAIL: Second request expected HTTP 409, got $status2." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Second request returned HTTP 409." -ForegroundColor Green
}

$conflictResponse = $null

try {
    $conflictResponse = Get-Content $response2File -Raw | ConvertFrom-Json

    if ($conflictResponse.error -eq "IDEMPOTENCY_CONFLICT") {
        Write-Host "PASS: Error code is IDEMPOTENCY_CONFLICT." -ForegroundColor Green
    }
    else {
        Write-Host "WARNING: Expected error code IDEMPOTENCY_CONFLICT, got '$($conflictResponse.error)'." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "FAIL: Could not parse conflict response." -ForegroundColor Red
    $failed = $true
}

Write-Host ""

# ---------------------------------------------------------
# 6. Fetch final show state
# ---------------------------------------------------------

Write-Host "Fetching final show state..."

$finalShowFile = Join-Path $TempDir "final-show.json"

$finalStatus = curl.exe `
    -s `
    -X GET `
    "$BaseUrl/shows/$ShowId" `
    -o $finalShowFile `
    -w "%{http_code}"

Write-Host "GET /shows/$ShowId -> HTTP $finalStatus"
Write-Host ""

if ($finalStatus -ne "200") {
    Write-Host "FAIL: Could not retrieve final show state." -ForegroundColor Red
    Get-Content $finalShowFile
    exit 1
}

$finalShow = Get-Content $finalShowFile -Raw | ConvertFrom-Json

# ---------------------------------------------------------
# 7. Print final state
# ---------------------------------------------------------

Write-Host "Final Show State"
Write-Host "----------------"
Write-Host "Total Seats:     $($finalShow.total_seats)"
Write-Host "Available Seats: $($finalShow.available_seats)"
Write-Host "Held Seats:      $($finalShow.held_seats)"
Write-Host "Confirmed Seats: $($finalShow.confirmed_seats)"
Write-Host ""

$total = [int]$finalShow.total_seats
$available = [int]$finalShow.available_seats
$held = [int]$finalShow.held_seats
$confirmed = [int]$finalShow.confirmed_seats

# ---------------------------------------------------------
# 8. Validate final counts
# ---------------------------------------------------------

if ($confirmed -ne 1) {
    Write-Host "FAIL: Expected exactly 1 confirmed seat." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Exactly 1 seat is CONFIRMED." -ForegroundColor Green
}

if ($available -ne 3) {
    Write-Host "FAIL: Expected 3 available seats." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: 3 seats remain AVAILABLE." -ForegroundColor Green
}

if ($held -ne 0) {
    Write-Host "FAIL: Expected 0 held seats." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Held seat count is 0." -ForegroundColor Green
}

# ---------------------------------------------------------
# 9. Validate seat invariant
# ---------------------------------------------------------

$invariant = $available + $held + $confirmed

if ($invariant -ne $total) {
    Write-Host "FAIL: Seat invariant violated: $available + $held + $confirmed != $total" -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Seat invariant holds: $available + $held + $confirmed = $total" -ForegroundColor Green
}

# ---------------------------------------------------------
# 10. Validate A1 = CONFIRMED
# ---------------------------------------------------------

$a1 = $finalShow.seats |
        Where-Object { $_.seat -eq "A1" }

if ($null -eq $a1) {
    Write-Host "FAIL: Seat A1 not found." -ForegroundColor Red
    $failed = $true
}
elseif ($a1.status -ne "CONFIRMED") {
    Write-Host "FAIL: Seat A1 status is $($a1.status), expected CONFIRMED." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Seat A1 is CONFIRMED." -ForegroundColor Green
}

# ---------------------------------------------------------
# 11. Validate A2 = AVAILABLE
# ---------------------------------------------------------

$a2 = $finalShow.seats |
        Where-Object { $_.seat -eq "A2" }

if ($null -eq $a2) {
    Write-Host "FAIL: Seat A2 not found." -ForegroundColor Red
    $failed = $true
}
elseif ($a2.status -ne "AVAILABLE") {
    Write-Host "FAIL: Seat A2 status is $($a2.status), expected AVAILABLE." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Seat A2 remains AVAILABLE." -ForegroundColor Green
}

# ---------------------------------------------------------
# 12. Final result
# ---------------------------------------------------------

Write-Host ""
Write-Host "========================================="

if ($failed) {
    Write-Host " IDEMPOTENCY CONFLICT TEST FAILED" -ForegroundColor Red
    Write-Host "========================================="
    exit 1
}
else {
    Write-Host " IDEMPOTENCY CONFLICT TEST PASSED" -ForegroundColor Green
    Write-Host "========================================="
    exit 0
}