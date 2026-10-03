$ErrorActionPreference = "Stop"

$BaseUrl = "http://localhost:8080"

$OwnerUser = "cancel-owner-user"
$AttackerUser = "cancel-attacker-user"

Write-Host ""
Write-Host "========================================"
Write-Host " Cancel Ownership & Correctness Test"
Write-Host "========================================"
Write-Host "Base URL : $BaseUrl"
Write-Host ""

# ------------------------------------------------------------
# Helpers
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

function Get-ResponseBody {
    param(
        [string]$Response
    )

    $jsonStart = $Response.IndexOf("{")

    if ($jsonStart -ge 0) {
        return $Response.Substring($jsonStart).Trim()
    }

    return ""
}

function Invoke-JsonRequest {
    param(
        [string]$Method,
        [string]$Url,
        [string]$Body,
        [string]$UserId
    )

    $requestFile = Join-Path `
        $env:TEMP `
        "cancel-test-$([guid]::NewGuid()).json"

    try {

        [System.IO.File]::WriteAllText(
                $requestFile,
                $Body,
                [System.Text.UTF8Encoding]::new($false)
        )

        $response = curl.exe -s -i `
            -X $Method `
            $Url `
            -H "Authorization: Bearer $UserId" `
            -H "Content-Type: application/json" `
            --data-binary "@$requestFile"

        $status = Get-HttpStatus $response
        $responseBody = Get-ResponseBody $response

        return [PSCustomObject]@{
            Status = $status
            Body   = $responseBody
            Raw    = $response
        }
    }
    finally {

        if (Test-Path $requestFile) {
            Remove-Item $requestFile -Force
        }
    }
}

# ------------------------------------------------------------
# 1. Create fresh show
# ------------------------------------------------------------

Write-Host "Creating test show..."

$showName = "Cancel-Ownership-Test-" + [guid]::NewGuid()

$createBody = @{
    name        = $showName
    seats       = @("A1", "A2", "A3", "A4")
    price_paise = 50000
} | ConvertTo-Json

$createFile = Join-Path `
    $env:TEMP `
    "create-cancel-show-$([guid]::NewGuid()).json"

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

    $show = $createResponse | ConvertFrom-Json

    if (-not $show.id) {
        Write-Host "FAIL: Could not create test show."
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
# 2. Owner creates reservation
# ------------------------------------------------------------

Write-Host ""
Write-Host "Step 1: Owner reserves A1..."

$reservationBody = @{
    seats = @("A1")
    idempotency_key = "cancel-test-$([guid]::NewGuid())"
} | ConvertTo-Json

$reservation = Invoke-JsonRequest `
    -Method "POST" `
    -Url "$BaseUrl/shows/$ShowId/reserve" `
    -Body $reservationBody `
    -UserId $OwnerUser

Write-Host "Reservation HTTP status: $($reservation.Status)"

if ($reservation.Status -ne 201) {

    Write-Host "FAIL: Owner reservation should return 201."
    Write-Host $reservation.Body
    exit 1
}

$reservationJson = $reservation.Body | ConvertFrom-Json

$ReservationId = $reservationJson.reservation_id

if ([string]::IsNullOrWhiteSpace($ReservationId)) {

    Write-Host "FAIL: Reservation ID missing."
    Write-Host $reservation.Body
    exit 1
}

Write-Host "Reservation ID: $ReservationId"

# ------------------------------------------------------------
# 3. Verify reservation is confirmed
# ------------------------------------------------------------

Write-Host ""
Write-Host "Step 2: Verify reservation is confirmed..."

$showBeforeAttackJson = curl.exe -s `
    "$BaseUrl/shows/$ShowId"

$showBeforeAttack = $showBeforeAttackJson | ConvertFrom-Json

$a1BeforeAttack = $showBeforeAttack.seats |
        Where-Object { $_.seat -eq "A1" }

if ($a1BeforeAttack.status -eq "CONFIRMED") {
    Write-Host "PASS: A1 is CONFIRMED."
}
else {
    Write-Host "FAIL: A1 is not CONFIRMED."
    exit 1
}

# ------------------------------------------------------------
# 4. Attacker attempts cancellation
# ------------------------------------------------------------

Write-Host ""
Write-Host "Step 3: Attacker attempts to cancel owner's reservation..."

$cancelBody = "{}"

$attackerCancel = Invoke-JsonRequest `
    -Method "POST" `
    -Url "$BaseUrl/reservations/$ReservationId/cancel" `
    -Body $cancelBody `
    -UserId $AttackerUser

Write-Host "Attacker cancel HTTP status: $($attackerCancel.Status)"
Write-Host "Response:"
Write-Host $attackerCancel.Body

# ------------------------------------------------------------
# 5. Verify attacker receives 403
# ------------------------------------------------------------

$failed = $false

Write-Host ""
Write-Host "Assertions:"

if ($attackerCancel.Status -eq 403) {

    Write-Host "PASS: Non-owner receives HTTP 403."
}
else {

    Write-Host "FAIL: Expected HTTP 403, got $($attackerCancel.Status)."
    $failed = $true
}

$attackerError = $null

if (-not [string]::IsNullOrWhiteSpace($attackerCancel.Body)) {

    try {
        $attackerError = $attackerCancel.Body | ConvertFrom-Json
    }
    catch {
        $attackerError = $null
    }
}

if ($null -ne $attackerError -and
        $attackerError.errorCode -eq "RESERVATION_NOT_OWNED") {

    Write-Host "PASS: Error code is RESERVATION_NOT_OWNED."
}
else {

    Write-Host "FAIL: Expected RESERVATION_NOT_OWNED."
    $failed = $true
}

# ------------------------------------------------------------
# 6. Verify attacker did not release the seat
# ------------------------------------------------------------

Write-Host ""
Write-Host "Step 4: Verify attacker did not release A1..."

$showAfterAttackJson = curl.exe -s `
    "$BaseUrl/shows/$ShowId"

$showAfterAttack = $showAfterAttackJson | ConvertFrom-Json

$a1AfterAttack = $showAfterAttack.seats |
        Where-Object { $_.seat -eq "A1" }

if ($a1AfterAttack.status -eq "CONFIRMED") {

    Write-Host "PASS: A1 remains CONFIRMED."
}
else {

    Write-Host "FAIL: A1 changed after unauthorized cancellation."
    $failed = $true
}

if ($showAfterAttack.confirmed_seats -eq 1) {

    Write-Host "PASS: Confirmed seat count remains 1."
}
else {

    Write-Host "FAIL: Expected 1 confirmed seat."
    $failed = $true
}

# ------------------------------------------------------------
# 7. Owner cancels reservation
# ------------------------------------------------------------

Write-Host ""
Write-Host "Step 5: Owner cancels reservation..."

$ownerCancel = Invoke-JsonRequest `
    -Method "POST" `
    -Url "$BaseUrl/reservations/$ReservationId/cancel" `
    -Body $cancelBody `
    -UserId $OwnerUser

Write-Host "Owner cancel HTTP status: $($ownerCancel.Status)"
Write-Host "Response:"
Write-Host $ownerCancel.Body

if ($ownerCancel.Status -eq 200) {

    Write-Host "PASS: Owner cancellation returned HTTP 200."
}
else {

    Write-Host "FAIL: Expected HTTP 200 from owner cancellation."
    $failed = $true
}

# ------------------------------------------------------------
# 8. Verify seat released
# ------------------------------------------------------------

Write-Host ""
Write-Host "Step 6: Verify A1 is AVAILABLE..."

$showAfterOwnerCancelJson = curl.exe -s `
    "$BaseUrl/shows/$ShowId"

$showAfterOwnerCancel = $showAfterOwnerCancelJson | ConvertFrom-Json

$a1AfterOwnerCancel = $showAfterOwnerCancel.seats |
        Where-Object { $_.seat -eq "A1" }

if ($a1AfterOwnerCancel.status -eq "AVAILABLE") {

    Write-Host "PASS: A1 is AVAILABLE after owner cancellation."
}
else {

    Write-Host "FAIL: A1 was not released."
    $failed = $true
}

if ($showAfterOwnerCancel.available_seats -eq 4) {

    Write-Host "PASS: Available seat count returned to 4."
}
else {

    Write-Host "FAIL: Expected 4 available seats."
    $failed = $true
}

if ($showAfterOwnerCancel.confirmed_seats -eq 0) {

    Write-Host "PASS: Confirmed seat count returned to 0."
}
else {

    Write-Host "FAIL: Expected 0 confirmed seats."
    $failed = $true
}

if ($showAfterOwnerCancel.held_seats -eq 0) {

    Write-Host "PASS: Held seat count is 0."
}
else {

    Write-Host "FAIL: Expected 0 held seats."
    $failed = $true
}

# ------------------------------------------------------------
# 9. Verify reconciliation invariant
# ------------------------------------------------------------

Write-Host ""
Write-Host "Step 7: Verify seat reconciliation invariant..."

$invariant =
$showAfterOwnerCancel.available_seats +
        $showAfterOwnerCancel.held_seats +
        $showAfterOwnerCancel.confirmed_seats

if ($invariant -eq $showAfterOwnerCancel.total_seats) {

    Write-Host "PASS: Seat invariant holds:"
    Write-Host "      $($showAfterOwnerCancel.available_seats) + $($showAfterOwnerCancel.held_seats) + $($showAfterOwnerCancel.confirmed_seats) = $($showAfterOwnerCancel.total_seats)"
}
else {

    Write-Host "FAIL: Seat invariant violated."
    $failed = $true
}

# ------------------------------------------------------------
# 10. Repeat cancellation
# ------------------------------------------------------------

Write-Host ""
Write-Host "Step 8: Repeat owner cancellation..."

$repeatCancel = Invoke-JsonRequest `
    -Method "POST" `
    -Url "$BaseUrl/reservations/$ReservationId/cancel" `
    -Body $cancelBody `
    -UserId $OwnerUser

Write-Host "Repeated cancel HTTP status: $($repeatCancel.Status)"

if ($repeatCancel.Status -eq 200) {

    Write-Host "PASS: Repeated cancellation is safely idempotent."
}
else {

    Write-Host "FAIL: Repeated cancellation returned $($repeatCancel.Status)."
    $failed = $true
}

# ------------------------------------------------------------
# 11. Final state check
# ------------------------------------------------------------

Write-Host ""
Write-Host "Final show state:"

$finalShowJson = curl.exe -s `
    "$BaseUrl/shows/$ShowId"

$finalShow = $finalShowJson | ConvertFrom-Json

$finalShow | ConvertTo-Json -Depth 10

$finalInvariant =
$finalShow.available_seats +
        $finalShow.held_seats +
        $finalShow.confirmed_seats

if ($finalInvariant -eq $finalShow.total_seats) {

    Write-Host ""
    Write-Host "PASS: Final seat invariant holds."
}
else {

    Write-Host ""
    Write-Host "FAIL: Final seat invariant violated."
    $failed = $true
}

# ------------------------------------------------------------
# 12. Final result
# ------------------------------------------------------------

Write-Host ""

if ($failed) {

    Write-Host "========================================"
    Write-Host " CANCEL OWNERSHIP TEST FAILED"
    Write-Host "========================================"

    exit 1
}
else {

    Write-Host "========================================"
    Write-Host " CANCEL OWNERSHIP TEST PASSED"
    Write-Host "========================================"

    Write-Host ""
    Write-Host "Verified:"
    Write-Host "  - Non-owner cannot cancel reservation"
    Write-Host "  - Unauthorized cancellation returns 403"
    Write-Host "  - Owner can cancel reservation"
    Write-Host "  - Cancellation releases seats"
    Write-Host "  - Repeated cancellation is safe"
    Write-Host "  - Seat reconciliation invariant holds"
    Write-Host ""
    Write-Host "Show ID: $ShowId"
}