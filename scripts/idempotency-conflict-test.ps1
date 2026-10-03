$ErrorActionPreference = "Stop"

$BaseUrl = "http://localhost:8080"
$UserId = "idempotency-conflict-user"
$IdempotencyKey = "idem-conflict-$([guid]::NewGuid())"

Write-Host ""
Write-Host "========================================"
Write-Host " Idempotency Key Conflict Test"
Write-Host "========================================"
Write-Host "Base URL        : $BaseUrl"
Write-Host "User            : $UserId"
Write-Host "Idempotency Key : $IdempotencyKey"
Write-Host ""

# ------------------------------------------------------------
# Helper: extract HTTP status from curl response
# ------------------------------------------------------------

function Get-HttpStatus {
    param(
        [string]$Response
    )

    if ($Response -match "HTTP/1\.[01]\s+(\d{3})\b") {
        return [int]$matches[1]
    }

    return 0
}

# ------------------------------------------------------------
# Helper: extract JSON body from curl response
# ------------------------------------------------------------

function Get-ResponseBody {
    param(
        [string]$Response
    )

    # Find the beginning of the JSON response.
    # Spring's response body starts with {.
    $jsonStart = $Response.IndexOf("{")

    if ($jsonStart -ge 0) {
        return $Response.Substring($jsonStart).Trim()
    }

    return ""
}

# ------------------------------------------------------------
# 1. Create a fresh show
# ------------------------------------------------------------

Write-Host "Creating test show..."

$showName = "Idempotency-Conflict-Test-" + [guid]::NewGuid()

$createBody = @{
    name        = $showName
    seats       = @("A1", "A2", "A3", "A4")
    price_paise = 50000
} | ConvertTo-Json

$createFile = Join-Path `
    $env:TEMP `
    "create-conflict-show-$([guid]::NewGuid()).json"

try {

    [System.IO.File]::WriteAllText(
            $createFile,
            $createBody,
            [System.Text.UTF8Encoding]::new($false)
    )

    $createResponse = curl.exe -s `
        -X POST `
        "$BaseUrl/shows" `
        -H "Content-Type: application/json" `
        --data-binary "@$createFile"

    if ([string]::IsNullOrWhiteSpace($createResponse)) {
        Write-Host "FAIL: Create show returned an empty response."
        exit 1
    }

    $show = $createResponse | ConvertFrom-Json

    if (-not $show.id) {
        Write-Host "FAIL: Could not determine created show ID."
        Write-Host $createResponse
        exit 1
    }

    $ShowId = $show.id

    Write-Host "Created show: $ShowId"
}
finally {

    if (Test-Path $createFile) {
        Remove-Item $createFile -Force
    }
}

# ------------------------------------------------------------
# 2. First request
#
# Same idempotency key will be reused later,
# but the first request books A1.
# ------------------------------------------------------------

$request1 = @{
    seats = @("A1")
    idempotency_key = $IdempotencyKey
} | ConvertTo-Json

$request1File = Join-Path `
    $env:TEMP `
    "idem-conflict-request1-$([guid]::NewGuid()).json"

[System.IO.File]::WriteAllText(
        $request1File,
        $request1,
        [System.Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "Request 1:"
Write-Host "  Seat: A1"
Write-Host "  Key : $IdempotencyKey"
Write-Host ""

$response1 = curl.exe -s -i `
    -X POST `
    "$BaseUrl/shows/$ShowId/reserve" `
    -H "Authorization: Bearer $UserId" `
    -H "Content-Type: application/json" `
    --data-binary "@$request1File"

$status1 = Get-HttpStatus $response1
$body1 = Get-ResponseBody $response1

Write-Host "Response 1:"
Write-Host $response1
Write-Host ""
Write-Host "Parsed HTTP status: $status1"

# ------------------------------------------------------------
# 3. Validate first request
# ------------------------------------------------------------

if ($status1 -ne 201) {

    Write-Host ""
    Write-Host "FAIL: First request expected HTTP 201 but received $status1."
    Write-Host "Response:"
    Write-Host $response1

    Remove-Item $request1File -Force -ErrorAction SilentlyContinue

    exit 1
}

Write-Host "PASS: First request returned 201."

# ------------------------------------------------------------
# 4. Extract reservation ID
# ------------------------------------------------------------

$reservationId = $null

if (-not [string]::IsNullOrWhiteSpace($body1)) {

    try {
        $json1 = $body1 | ConvertFrom-Json

        if ($json1.reservation_id) {
            $reservationId = $json1.reservation_id
        }
    }
    catch {
        Write-Host "WARNING: Could not parse first response JSON."
    }
}

if ($reservationId) {
    Write-Host "Reservation ID: $reservationId"
}
else {
    Write-Host "WARNING: Reservation ID could not be extracted."
}

# ------------------------------------------------------------
# 5. Second request
#
# IMPORTANT:
# Same user
# Same idempotency key
# DIFFERENT seat
#
# This must return 409 IDEMPOTENCY_CONFLICT.
# ------------------------------------------------------------

$request2 = @{
    seats = @("A2")
    idempotency_key = $IdempotencyKey
} | ConvertTo-Json

$request2File = Join-Path `
    $env:TEMP `
    "idem-conflict-request2-$([guid]::NewGuid()).json"

[System.IO.File]::WriteAllText(
        $request2File,
        $request2,
        [System.Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "Request 2:"
Write-Host "  Seat: A2"
Write-Host "  Key : $IdempotencyKey"
Write-Host ""
Write-Host "Same idempotency key, DIFFERENT request body."
Write-Host ""

$response2 = curl.exe -s -i `
    -X POST `
    "$BaseUrl/shows/$ShowId/reserve" `
    -H "Authorization: Bearer $UserId" `
    -H "Content-Type: application/json" `
    --data-binary "@$request2File"

$status2 = Get-HttpStatus $response2
$body2 = Get-ResponseBody $response2

Write-Host "Response 2:"
Write-Host $response2
Write-Host ""
Write-Host "Parsed HTTP status: $status2"

# ------------------------------------------------------------
# 6. Fetch final show state
# ------------------------------------------------------------

Write-Host ""
Write-Host "Fetching final show state..."

$finalShowJson = curl.exe -s "$BaseUrl/shows/$ShowId"

if ([string]::IsNullOrWhiteSpace($finalShowJson)) {

    Write-Host "FAIL: Could not retrieve final show state."

    Remove-Item $request1File -Force -ErrorAction SilentlyContinue
    Remove-Item $request2File -Force -ErrorAction SilentlyContinue

    exit 1
}

try {
    $finalShow = $finalShowJson | ConvertFrom-Json
}
catch {

    Write-Host "FAIL: Could not parse final show JSON."
    Write-Host $finalShowJson

    Remove-Item $request1File -Force -ErrorAction SilentlyContinue
    Remove-Item $request2File -Force -ErrorAction SilentlyContinue

    exit 1
}

Write-Host ""
Write-Host "Final show state:"
$finalShow | ConvertTo-Json -Depth 10

# ------------------------------------------------------------
# 7. Assertions
# ------------------------------------------------------------

Write-Host ""
Write-Host "Assertions:"

$failed = $false

# ------------------------------------------------------------
# Assertion 1
# First request = 201
# ------------------------------------------------------------

if ($status1 -eq 201) {
    Write-Host "PASS: First request returned 201."
}
else {
    Write-Host "FAIL: First request returned $status1 instead of 201."
    $failed = $true
}

# ------------------------------------------------------------
# Assertion 2
# Second request = 409
# ------------------------------------------------------------

if ($status2 -eq 409) {
    Write-Host "PASS: Second request returned 409."
}
else {
    Write-Host "FAIL: Second request returned $status2 instead of 409."
    $failed = $true
}

# ------------------------------------------------------------
# Assertion 3
# Correct error code
# ------------------------------------------------------------

if ($body2 -match '"errorCode"\s*:\s*"IDEMPOTENCY_CONFLICT"') {
    Write-Host "PASS: Error code is IDEMPOTENCY_CONFLICT."
}
else {
    Write-Host "FAIL: Expected IDEMPOTENCY_CONFLICT error code."

    if (-not [string]::IsNullOrWhiteSpace($body2)) {
        Write-Host "Response body:"
        Write-Host $body2
    }

    $failed = $true
}

# ------------------------------------------------------------
# Assertion 4
# A1 must be confirmed
# ------------------------------------------------------------

$a1 = $finalShow.seats |
        Where-Object { $_.seat -eq "A1" }

if ($null -ne $a1 -and $a1.status -eq "CONFIRMED") {
    Write-Host "PASS: A1 remains CONFIRMED."
}
else {
    Write-Host "FAIL: A1 is not CONFIRMED."
    $failed = $true
}

# ------------------------------------------------------------
# Assertion 5
# A2 must remain available
# ------------------------------------------------------------

$a2 = $finalShow.seats |
        Where-Object { $_.seat -eq "A2" }

if ($null -ne $a2 -and $a2.status -eq "AVAILABLE") {
    Write-Host "PASS: A2 remains AVAILABLE."
}
else {
    Write-Host "FAIL: A2 was incorrectly changed."
    $failed = $true
}

# ------------------------------------------------------------
# Assertion 6
# Exactly one confirmed seat
# ------------------------------------------------------------

if ($finalShow.confirmed_seats -eq 1) {
    Write-Host "PASS: Exactly one seat is confirmed."
}
else {
    Write-Host "FAIL: Expected exactly 1 confirmed seat, got $($finalShow.confirmed_seats)."
    $failed = $true
}

# ------------------------------------------------------------
# Assertion 7
# No held seats
# ------------------------------------------------------------

if ($finalShow.held_seats -eq 0) {
    Write-Host "PASS: No seats are unexpectedly held."
}
else {
    Write-Host "FAIL: Expected 0 held seats, got $($finalShow.held_seats)."
    $failed = $true
}

# ------------------------------------------------------------
# Assertion 8
# Seat reconciliation invariant
# ------------------------------------------------------------

$invariant =
$finalShow.available_seats +
        $finalShow.held_seats +
        $finalShow.confirmed_seats

if ($invariant -eq $finalShow.total_seats) {

    Write-Host "PASS: Seat invariant holds: $($finalShow.available_seats) + $($finalShow.held_seats) + $($finalShow.confirmed_seats) = $($finalShow.total_seats)"
}
else {

    Write-Host "FAIL: Seat invariant violated."
    Write-Host "      $($finalShow.available_seats) + $($finalShow.held_seats) + $($finalShow.confirmed_seats) != $($finalShow.total_seats)"

    $failed = $true
}

# ------------------------------------------------------------
# 9. Cleanup
# ------------------------------------------------------------

Remove-Item $request1File -Force -ErrorAction SilentlyContinue
Remove-Item $request2File -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------
# 10. Final result
# ------------------------------------------------------------

Write-Host ""

if ($failed) {

    Write-Host "========================================"
    Write-Host " IDEMPOTENCY CONFLICT TEST FAILED"
    Write-Host "========================================"

    exit 1
}
else {

    Write-Host "========================================"
    Write-Host " IDEMPOTENCY CONFLICT TEST PASSED"
    Write-Host "========================================"

    Write-Host ""
    Write-Host "Show ID             : $ShowId"
    Write-Host "Original Reservation: $reservationId"
    Write-Host ""
    Write-Host "A1 = CONFIRMED"
    Write-Host "A2 = AVAILABLE"
    Write-Host "Same key + different body = 409"
}