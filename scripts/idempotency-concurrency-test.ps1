$ErrorActionPreference = "Stop"

$BaseUrl = "http://localhost:8080"

$AdminToken = "idempotency-admin-user"
$TestUserToken = "idempotency-test-user"

$Seat = "A1"
$IdempotencyKey = "idem-concurrent-key-$(Get-Date -Format 'yyyyMMddHHmmssfff')"

$RequestCount = 20

$TempDir = Join-Path $env:TEMP "seat-idempotency-test"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

Write-Host "========================================="
Write-Host " IDEMPOTENCY CONCURRENCY TEST"
Write-Host "========================================="
Write-Host ""

# ---------------------------------------------------------
# 1. Create a fresh show
# ---------------------------------------------------------

$showRequest = @{
    name       = "Idempotency Concurrency Show $(Get-Date -Format 'yyyyMMddHHmmssfff')"
    seats      = @("A1", "A2", "A3", "A4")
    price_paise = 10000
} | ConvertTo-Json -Compress

$showRequestFile = Join-Path $TempDir "show-request.json"
$showRequest | Set-Content -Path $showRequestFile -Encoding UTF8

Write-Host "Creating test show..."

$showResponseFile = Join-Path $TempDir "show-response.json"

curl.exe `
    -s `
    -X POST `
    "$BaseUrl/shows" `
    -H "Content-Type: application/json" `
    -H "Authorization: Bearer $AdminToken" `
    --data-binary "@$showRequestFile" `
    -o $showResponseFile `
    -w "%{http_code}" | Set-Content -Path (Join-Path $TempDir "show-status.txt")

$showStatus = Get-Content (Join-Path $TempDir "show-status.txt") -Raw
$showStatus = $showStatus.Trim()

if ($showStatus -ne "201") {
    Write-Host "FAILED: Show creation returned HTTP $showStatus" -ForegroundColor Red
    Get-Content $showResponseFile
    exit 1
}

$showResponse = Get-Content $showResponseFile -Raw | ConvertFrom-Json
$ShowId = $showResponse.id

Write-Host "Show created: $ShowId"
Write-Host ""

# ---------------------------------------------------------
# 2. Prepare 20 identical requests
# ---------------------------------------------------------

$requestBody = @{
    seats = @($Seat)
    idempotency_key = $IdempotencyKey
} | ConvertTo-Json -Compress

$requestFile = Join-Path $TempDir "reserve-request.json"
$requestBody | Set-Content -Path $requestFile -Encoding UTF8

Write-Host "Sending $RequestCount concurrent requests..."
Write-Host "User: $TestUserToken"
Write-Host "Seat: $Seat"
Write-Host "Idempotency Key: $IdempotencyKey"
Write-Host ""

# ---------------------------------------------------------
# 3. Start concurrent PowerShell 5.1 jobs
# ---------------------------------------------------------

$jobs = @()

for ($i = 1; $i -le $RequestCount; $i++) {

    $responseFile = Join-Path $TempDir "response-$i.json"
    $statusFile = Join-Path $TempDir "status-$i.txt"

    $job = Start-Job -ScriptBlock {
        param(
            $BaseUrl,
            $ShowId,
            $Token,
            $RequestFile,
            $ResponseFile,
            $StatusFile
        )

        curl.exe `
            -s `
            -X POST `
            "$BaseUrl/shows/$ShowId/reserve" `
            -H "Content-Type: application/json" `
            -H "Authorization: Bearer $Token" `
            --data-binary "@$RequestFile" `
            -o $ResponseFile `
            -w "%{http_code}" |
                Set-Content -Path $StatusFile

    } -ArgumentList `
        $BaseUrl,
    $ShowId,
    $TestUserToken,
    $requestFile,
    $responseFile,
    $statusFile

    $jobs += $job
}

# ---------------------------------------------------------
# 4. Wait for all jobs
# ---------------------------------------------------------

$jobs | Wait-Job | Out-Null
$jobs | Remove-Job

Write-Host "All requests completed."
Write-Host ""

# ---------------------------------------------------------
# 5. Collect results
# ---------------------------------------------------------

$results = @()

for ($i = 1; $i -le $RequestCount; $i++) {

    $statusFile = Join-Path $TempDir "status-$i.txt"
    $responseFile = Join-Path $TempDir "response-$i.json"

    if (-not (Test-Path $statusFile)) {
        $results += [PSCustomObject]@{
            Request = $i
            Status = 0
            ReservationId = $null
        }
        continue
    }

    $status = (Get-Content $statusFile -Raw).Trim()

    $reservationId = $null

    if (Test-Path $responseFile) {
        try {
            $response = Get-Content $responseFile -Raw | ConvertFrom-Json

            if ($response.reservation_id) {
                $reservationId = $response.reservation_id
            }
        }
        catch {
            # Ignore invalid/non-JSON response
        }
    }

    $results += [PSCustomObject]@{
        Request = $i
        Status = [int]$status
        ReservationId = $reservationId
    }
}

# ---------------------------------------------------------
# 6. Print response summary
# ---------------------------------------------------------

Write-Host "Response Summary"
Write-Host "----------------"

$results | Group-Object Status | Sort-Object Name | ForEach-Object {
    Write-Host "HTTP $($_.Name): $($_.Count)"
}

Write-Host ""

$http201 = @($results | Where-Object { $_.Status -eq 201 }).Count
$http409 = @($results | Where-Object { $_.Status -eq 409 }).Count
$http401 = @($results | Where-Object { $_.Status -eq 401 }).Count
$http403 = @($results | Where-Object { $_.Status -eq 403 }).Count
$http5xx = @($results | Where-Object { $_.Status -ge 500 }).Count
$other = @(
$results |
        Where-Object {
            $_.Status -ne 201 -and
                    $_.Status -ne 409 -and
                    $_.Status -ne 401 -and
                    $_.Status -ne 403 -and
                    ($_.Status -lt 500 -or $_.Status -eq 0)
        }
).Count

Write-Host "HTTP 201: $http201"
Write-Host "HTTP 409: $http409"
Write-Host "HTTP 401: $http401"
Write-Host "HTTP 403: $http403"
Write-Host "5xx Errors: $http5xx"
Write-Host "Other: $other"
Write-Host ""

# ---------------------------------------------------------
# 7. Validate idempotency behavior
# ---------------------------------------------------------

$failed = $false

if ($http201 -ne $RequestCount) {
    Write-Host "FAIL: Expected ALL $RequestCount requests to return 201 for same idempotency key." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: All $RequestCount requests returned HTTP 201." -ForegroundColor Green
}

if ($http409 -ne 0) {
    Write-Host "FAIL: Same idempotency key should not produce 409 under concurrent replay." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: No idempotency conflicts occurred." -ForegroundColor Green
}

if ($http401 -ne 0) {
    Write-Host "FAIL: Some requests were unauthenticated." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: All requests were authenticated." -ForegroundColor Green
}

if ($http403 -ne 0) {
    Write-Host "FAIL: Some requests returned 403." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: No authorization failures." -ForegroundColor Green
}

if ($http5xx -ne 0) {
    Write-Host "FAIL: 5xx responses detected." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Zero 5xx responses." -ForegroundColor Green
}

# ---------------------------------------------------------
# 8. Validate all responses have same reservation ID
# ---------------------------------------------------------

$reservationIds = @(
$results |
        Where-Object { $_.Status -eq 201 -and $_.ReservationId } |
        Select-Object -ExpandProperty ReservationId -Unique
)

if ($reservationIds.Count -ne 1) {
    Write-Host "FAIL: Expected exactly ONE unique reservation ID." -ForegroundColor Red
    Write-Host "Unique reservation IDs found: $($reservationIds.Count)"
    $reservationIds | ForEach-Object {
        Write-Host "  $_"
    }
    $failed = $true
}
else {
    $ReservationId = $reservationIds[0]

    Write-Host "PASS: Exactly one unique reservation was created." -ForegroundColor Green
    Write-Host "Reservation ID: $ReservationId"
}

Write-Host ""

# ---------------------------------------------------------
# 9. Fetch final show state
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
# 10. Validate seat counts
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
# 11. Validate exactly one seat sold
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
# 12. Validate reconciliation invariant
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
# 13. Validate A1 is confirmed
# ---------------------------------------------------------

$a1 = $finalShow.seats |
        Where-Object {
            $_.seat_number -eq $Seat -or
                    $_.seatNumber -eq $Seat -or
                    $_.seat -eq $Seat
        }

if ($null -eq $a1) {
    Write-Host "FAIL: Seat $Seat not found." -ForegroundColor Red

    Write-Host ""
    Write-Host "Returned seat objects:"
    $finalShow.seats | ConvertTo-Json -Depth 5

    $failed = $true
}
elseif (
$a1.status -ne "CONFIRMED" -and
        $a1.Status -ne "CONFIRMED"
) {
    Write-Host "FAIL: Seat $Seat status is $($a1.status), expected CONFIRMED." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Seat $Seat is CONFIRMED." -ForegroundColor Green
}

# ---------------------------------------------------------
# 14. Final result
# ---------------------------------------------------------

Write-Host ""
Write-Host "========================================="

if ($failed) {
    Write-Host " IDEMPOTENCY CONCURRENCY TEST FAILED" -ForegroundColor Red
    Write-Host "========================================="
    exit 1
}
else {
    Write-Host " IDEMPOTENCY CONCURRENCY TEST PASSED" -ForegroundColor Green
    Write-Host "========================================="
    exit 0
}