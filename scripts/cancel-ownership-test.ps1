$ErrorActionPreference = "Stop"

$BaseUrl = "http://localhost:8080"

$AdminToken = "cancel-test-admin-user"
$OwnerToken = "cancel-owner-user"
$AttackerToken = "cancel-attacker-user"

$Seat = "A1"

$TempDir = Join-Path $env:TEMP "seat-cancel-ownership-test"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

Write-Host ""
Write-Host "========================================"
Write-Host " Cancel Ownership & Correctness Test"
Write-Host "========================================"
Write-Host "Base URL : $BaseUrl"
Write-Host ""

$failed = $false

# ---------------------------------------------------------
# Helper function
# ---------------------------------------------------------

function Invoke-ApiRequest {
    param(
        [string]$Method,
        [string]$Url,
        [string]$Token,
        [string]$RequestFile,
        [string]$ResponseFile,
        [string]$StatusFile
    )

    $arguments = @(
        "-s"
        "-X"
        $Method
        $Url
        "-H"
        "Content-Type: application/json"
    )

    if ($Token) {
        $arguments += @(
            "-H"
            "Authorization: Bearer $Token"
        )
    }

    if ($RequestFile) {
        $arguments += @(
            "--data-binary"
            "@$RequestFile"
        )
    }

    $arguments += @(
        "-o"
        $ResponseFile
        "-w"
        "%{http_code}"
    )

    & curl.exe @arguments |
            Set-Content -Path $StatusFile
}

# ---------------------------------------------------------
# 1. Create a fresh show
# ---------------------------------------------------------

$showRequest = @{
    name        = "Cancel Ownership Show $(Get-Date -Format 'yyyyMMddHHmmssfff')"
    seats       = @("A1", "A2", "A3", "A4")
    price_paise = 10000
} | ConvertTo-Json -Compress

$showRequestFile = Join-Path $TempDir "show-request.json"
$showResponseFile = Join-Path $TempDir "show-response.json"
$showStatusFile = Join-Path $TempDir "show-status.txt"

$showRequest | Set-Content -Path $showRequestFile -Encoding UTF8

Write-Host "Creating test show..."

Invoke-ApiRequest `
    -Method "POST" `
    -Url "$BaseUrl/shows" `
    -Token $AdminToken `
    -RequestFile $showRequestFile `
    -ResponseFile $showResponseFile `
    -StatusFile $showStatusFile

$showStatus = (Get-Content $showStatusFile -Raw).Trim()

if ($showStatus -ne "201") {
    Write-Host "FAIL: Could not create test show." -ForegroundColor Red
    Get-Content $showResponseFile
    exit 1
}

$showResponse = Get-Content $showResponseFile -Raw | ConvertFrom-Json
$ShowId = $showResponse.id

Write-Host "PASS: Test show created. Show ID: $ShowId" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------
# 2. Owner creates reservation
# ---------------------------------------------------------

Write-Host "Owner creating reservation for $Seat..."

$ownerIdempotencyKey = "cancel-owner-key-$(Get-Date -Format 'yyyyMMddHHmmssfff')"

$reserveRequest = @{
    seats = @($Seat)
    idempotency_key = $ownerIdempotencyKey
} | ConvertTo-Json -Compress

$reserveRequestFile = Join-Path $TempDir "reserve-request.json"
$reserveResponseFile = Join-Path $TempDir "reserve-response.json"
$reserveStatusFile = Join-Path $TempDir "reserve-status.txt"

$reserveRequest | Set-Content -Path $reserveRequestFile -Encoding UTF8

Invoke-ApiRequest `
    -Method "POST" `
    -Url "$BaseUrl/shows/$ShowId/reserve" `
    -Token $OwnerToken `
    -RequestFile $reserveRequestFile `
    -ResponseFile $reserveResponseFile `
    -StatusFile $reserveStatusFile

$reserveStatus = (Get-Content $reserveStatusFile -Raw).Trim()

Write-Host "Owner reservation HTTP status: $reserveStatus"

if (Test-Path $reserveResponseFile) {
    Write-Host "Reservation response:"
    Get-Content $reserveResponseFile
}

Write-Host ""

if ($reserveStatus -ne "201") {
    Write-Host "FAIL: Owner reservation expected HTTP 201." -ForegroundColor Red
    exit 1
}

Write-Host "PASS: Owner successfully created reservation." -ForegroundColor Green

$reservationResponse = Get-Content $reserveResponseFile -Raw | ConvertFrom-Json
$ReservationId = $reservationResponse.reservation_id

if ([string]::IsNullOrWhiteSpace($ReservationId)) {
    Write-Host "FAIL: Reservation ID missing." -ForegroundColor Red
    exit 1
}

Write-Host "Reservation ID: $ReservationId"
Write-Host ""

# ---------------------------------------------------------
# 3. Attacker attempts cancellation
# ---------------------------------------------------------

Write-Host "Attacker attempting to cancel owner's reservation..."
Write-Host "Expected result: HTTP 403"
Write-Host ""

$attackerResponseFile = Join-Path $TempDir "attacker-cancel-response.json"
$attackerStatusFile = Join-Path $TempDir "attacker-cancel-status.txt"

Invoke-ApiRequest `
    -Method "POST" `
    -Url "$BaseUrl/reservations/$ReservationId/cancel" `
    -Token $AttackerToken `
    -ResponseFile $attackerResponseFile `
    -StatusFile $attackerStatusFile

$attackerStatus = (Get-Content $attackerStatusFile -Raw).Trim()

Write-Host "Attacker cancellation HTTP status: $attackerStatus"

if (Test-Path $attackerResponseFile) {
    Write-Host "Attacker response:"
    Get-Content $attackerResponseFile
}

Write-Host ""

if ($attackerStatus -ne "403") {
    Write-Host "FAIL: Attacker cancellation expected HTTP 403, got $attackerStatus." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Attacker received HTTP 403." -ForegroundColor Green
}

# ---------------------------------------------------------
# 4. Verify reservation still exists and A1 is confirmed
# ---------------------------------------------------------

Write-Host "Checking show state after attacker attempt..."

$showAfterAttackFile = Join-Path $TempDir "show-after-attack.json"
$showAfterAttackStatusFile = Join-Path $TempDir "show-after-attack-status.txt"

Invoke-ApiRequest `
    -Method "GET" `
    -Url "$BaseUrl/shows/$ShowId" `
    -ResponseFile $showAfterAttackFile `
    -StatusFile $showAfterAttackStatusFile

$showAfterAttackStatus = (Get-Content $showAfterAttackStatusFile -Raw).Trim()

Write-Host "GET /shows/$ShowId -> HTTP $showAfterAttackStatus"
Write-Host ""

if ($showAfterAttackStatus -ne "200") {
    Write-Host "FAIL: Could not retrieve show state." -ForegroundColor Red
    $failed = $true
}
else {
    $showAfterAttack = Get-Content $showAfterAttackFile -Raw | ConvertFrom-Json

    $a1 = $showAfterAttack.seats |
            Where-Object { $_.seat -eq $Seat }

    if ($null -eq $a1) {
        Write-Host "FAIL: Seat $Seat not found." -ForegroundColor Red
        $failed = $true
    }
    elseif ($a1.status -ne "CONFIRMED") {
        Write-Host "FAIL: Seat $Seat changed after unauthorized cancellation." -ForegroundColor Red
        Write-Host "Current status: $($a1.status)"
        $failed = $true
    }
    else {
        Write-Host "PASS: Seat $Seat remains CONFIRMED after attacker attempt." -ForegroundColor Green
    }

    $confirmedAfterAttack = [int]$showAfterAttack.confirmed_seats
    $availableAfterAttack = [int]$showAfterAttack.available_seats
    $heldAfterAttack = [int]$showAfterAttack.held_seats
    $totalAfterAttack = [int]$showAfterAttack.total_seats

    $invariantAfterAttack =
    $availableAfterAttack +
            $heldAfterAttack +
            $confirmedAfterAttack

    if ($invariantAfterAttack -ne $totalAfterAttack) {
        Write-Host "FAIL: Seat invariant violated after attacker attempt." -ForegroundColor Red
        $failed = $true
    }
    else {
        Write-Host "PASS: Seat invariant holds after attacker attempt: $availableAfterAttack + $heldAfterAttack + $confirmedAfterAttack = $totalAfterAttack" -ForegroundColor Green
    }
}

Write-Host ""

# ---------------------------------------------------------
# 5. Owner cancels reservation
# ---------------------------------------------------------

Write-Host "Owner cancelling reservation..."
Write-Host "Expected result: HTTP 200"
Write-Host ""

$ownerCancelResponseFile = Join-Path $TempDir "owner-cancel-response.json"
$ownerCancelStatusFile = Join-Path $TempDir "owner-cancel-status.txt"

Invoke-ApiRequest `
    -Method "POST" `
    -Url "$BaseUrl/reservations/$ReservationId/cancel" `
    -Token $OwnerToken `
    -ResponseFile $ownerCancelResponseFile `
    -StatusFile $ownerCancelStatusFile

$ownerCancelStatus = (Get-Content $ownerCancelStatusFile -Raw).Trim()

Write-Host "Owner cancellation HTTP status: $ownerCancelStatus"

if (Test-Path $ownerCancelResponseFile) {
    Write-Host "Owner cancellation response:"
    Get-Content $ownerCancelResponseFile
}

Write-Host ""

if ($ownerCancelStatus -ne "200") {
    Write-Host "FAIL: Owner cancellation expected HTTP 200, got $ownerCancelStatus." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Owner successfully cancelled reservation." -ForegroundColor Green
}

# ---------------------------------------------------------
# 6. Validate cancellation status
# ---------------------------------------------------------

if ($ownerCancelStatus -eq "200") {

    try {
        $cancelResponse = Get-Content $ownerCancelResponseFile -Raw | ConvertFrom-Json

        if ($cancelResponse.status -ne "CANCELLED") {
            Write-Host "FAIL: Expected reservation status CANCELLED, got $($cancelResponse.status)." -ForegroundColor Red
            $failed = $true
        }
        else {
            Write-Host "PASS: Reservation status is CANCELLED." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "FAIL: Could not parse cancellation response." -ForegroundColor Red
        $failed = $true
    }
}

Write-Host ""

# ---------------------------------------------------------
# 7. Verify A1 becomes available
# ---------------------------------------------------------

Write-Host "Checking final show state..."

$finalShowFile = Join-Path $TempDir "final-show.json"
$finalShowStatusFile = Join-Path $TempDir "final-show-status.txt"

Invoke-ApiRequest `
    -Method "GET" `
    -Url "$BaseUrl/shows/$ShowId" `
    -ResponseFile $finalShowFile `
    -StatusFile $finalShowStatusFile

$finalShowStatus = (Get-Content $finalShowStatusFile -Raw).Trim()

Write-Host "GET /shows/$ShowId -> HTTP $finalShowStatus"
Write-Host ""

if ($finalShowStatus -ne "200") {
    Write-Host "FAIL: Could not retrieve final show state." -ForegroundColor Red
    $failed = $true
}
else {

    $finalShow = Get-Content $finalShowFile -Raw | ConvertFrom-Json

    Write-Host "Final Show State"
    Write-Host "----------------"
    Write-Host "Total Seats:     $($finalShow.total_seats)"
    Write-Host "Available Seats: $($finalShow.available_seats)"
    Write-Host "Held Seats:      $($finalShow.held_seats)"
    Write-Host "Confirmed Seats: $($finalShow.confirmed_seats)"
    Write-Host ""

    # -----------------------------------------------------
    # Validate A1
    # -----------------------------------------------------

    $a1Final = $finalShow.seats |
            Where-Object { $_.seat -eq $Seat }

    if ($null -eq $a1Final) {
        Write-Host "FAIL: Seat $Seat not found in final state." -ForegroundColor Red
        $failed = $true
    }
    elseif ($a1Final.status -ne "AVAILABLE") {
        Write-Host "FAIL: Seat $Seat status is $($a1Final.status), expected AVAILABLE." -ForegroundColor Red
        $failed = $true
    }
    else {
        Write-Host "PASS: Seat $Seat is AVAILABLE after owner cancellation." -ForegroundColor Green
    }

    # -----------------------------------------------------
    # Validate counts
    # -----------------------------------------------------

    $total = [int]$finalShow.total_seats
    $available = [int]$finalShow.available_seats
    $held = [int]$finalShow.held_seats
    $confirmed = [int]$finalShow.confirmed_seats

    if ($available -ne 4) {
        Write-Host "FAIL: Expected 4 available seats, got $available." -ForegroundColor Red
        $failed = $true
    }
    else {
        Write-Host "PASS: All 4 seats are AVAILABLE." -ForegroundColor Green
    }

    if ($held -ne 0) {
        Write-Host "FAIL: Expected 0 held seats, got $held." -ForegroundColor Red
        $failed = $true
    }
    else {
        Write-Host "PASS: Held seat count is 0." -ForegroundColor Green
    }

    if ($confirmed -ne 0) {
        Write-Host "FAIL: Expected 0 confirmed seats, got $confirmed." -ForegroundColor Red
        $failed = $true
    }
    else {
        Write-Host "PASS: Confirmed seat count is 0." -ForegroundColor Green
    }

    # -----------------------------------------------------
    # Validate invariant
    # -----------------------------------------------------

    $invariant = $available + $held + $confirmed

    if ($invariant -ne $total) {
        Write-Host "FAIL: Seat invariant violated: $available + $held + $confirmed != $total" -ForegroundColor Red
        $failed = $true
    }
    else {
        Write-Host "PASS: Seat invariant holds: $available + $held + $confirmed = $total" -ForegroundColor Green
    }
}

Write-Host ""

# ---------------------------------------------------------
# 8. Repeat owner cancellation
# ---------------------------------------------------------

Write-Host "Testing repeated owner cancellation..."
Write-Host "Expected result: HTTP 200 (idempotent/safe)"
Write-Host ""

$repeatCancelResponseFile = Join-Path $TempDir "repeat-cancel-response.json"
$repeatCancelStatusFile = Join-Path $TempDir "repeat-cancel-status.txt"

Invoke-ApiRequest `
    -Method "POST" `
    -Url "$BaseUrl/reservations/$ReservationId/cancel" `
    -Token $OwnerToken `
    -ResponseFile $repeatCancelResponseFile `
    -StatusFile $repeatCancelStatusFile

$repeatCancelStatus = (Get-Content $repeatCancelStatusFile -Raw).Trim()

Write-Host "Repeated cancellation HTTP status: $repeatCancelStatus"

if (Test-Path $repeatCancelResponseFile) {
    Get-Content $repeatCancelResponseFile
}

Write-Host ""

if ($repeatCancelStatus -ne "200") {
    Write-Host "FAIL: Repeated cancellation expected HTTP 200, got $repeatCancelStatus." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Repeated owner cancellation is safe." -ForegroundColor Green
}

# ---------------------------------------------------------
# 9. Final result
# ---------------------------------------------------------

Write-Host ""
Write-Host "========================================"

if ($failed) {
    Write-Host " CANCEL OWNERSHIP TEST FAILED" -ForegroundColor Red
    Write-Host "========================================"
    exit 1
}
else {
    Write-Host " CANCEL OWNERSHIP TEST PASSED" -ForegroundColor Green
    Write-Host "========================================"
    exit 0
}