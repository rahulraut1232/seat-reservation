$ErrorActionPreference = "Stop"

$BaseUrl = "http://localhost:8080"

$AdminToken = "multi-seat-admin-user"

$Seat1 = "A1"
$Seat2 = "A2"

$RequestCount = 10

$TempDir = Join-Path $env:TEMP "seat-multi-seat-atomicity-test"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

Write-Host "========================================="
Write-Host " MULTI-SEAT ATOMICITY TEST"
Write-Host "========================================="
Write-Host ""

# ---------------------------------------------------------
# 1. Create a fresh show
# ---------------------------------------------------------

$showRequest = @{
    name        = "Multi Seat Atomicity Show $(Get-Date -Format 'yyyyMMddHHmmssfff')"
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
Write-Host ""

# ---------------------------------------------------------
# 2. Prepare concurrent requests
# ---------------------------------------------------------

Write-Host "Preparing $RequestCount concurrent requests..."
Write-Host "Seats: $Seat1 + $Seat2"
Write-Host ""

$jobs = @()

for ($i = 1; $i -le $RequestCount; $i++) {

    $userToken = "multi-seat-user-$i"
    $idempotencyKey = "multi-seat-key-$i"

    $requestBody = @{
        seats = @($Seat1, $Seat2)
        idempotency_key = $idempotencyKey
    } | ConvertTo-Json -Compress

    $requestFile = Join-Path $TempDir "request-$i.json"
    $responseFile = Join-Path $TempDir "response-$i.json"
    $statusFile = Join-Path $TempDir "status-$i.txt"

    $requestBody | Set-Content -Path $requestFile -Encoding UTF8

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
    $userToken,
    $requestFile,
    $responseFile,
    $statusFile

    $jobs += $job
}

# ---------------------------------------------------------
# 3. Wait for all requests
# ---------------------------------------------------------

$jobs | Wait-Job | Out-Null
$jobs | Remove-Job

Write-Host "All requests completed."
Write-Host ""

# ---------------------------------------------------------
# 4. Collect results
# ---------------------------------------------------------

$results = @()

for ($i = 1; $i -le $RequestCount; $i++) {

    $statusFile = Join-Path $TempDir "status-$i.txt"
    $responseFile = Join-Path $TempDir "response-$i.json"

    if (-not (Test-Path $statusFile)) {

        $results += [PSCustomObject]@{
            Request = $i
            User = "multi-seat-user-$i"
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
        User = "multi-seat-user-$i"
        Status = [int]$status
        ReservationId = $reservationId
    }
}

# ---------------------------------------------------------
# 5. Response summary
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
# 6. Validate concurrency result
# ---------------------------------------------------------

$failed = $false

if ($http201 -ne 1) {
    Write-Host "FAIL: Expected exactly 1 successful reservation." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Exactly 1 request returned HTTP 201." -ForegroundColor Green
}

if ($http409 -ne ($RequestCount - 1)) {
    Write-Host "FAIL: Expected $($RequestCount - 1) conflict responses." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Expected conflict count: $($RequestCount - 1)." -ForegroundColor Green
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

if ($other -ne 0) {
    Write-Host "FAIL: Unexpected HTTP responses detected." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: No unexpected responses." -ForegroundColor Green
}

# ---------------------------------------------------------
# 7. Validate exactly one reservation
# ---------------------------------------------------------

$reservationIds = @(
$results |
        Where-Object {
            $_.Status -eq 201 -and
                    $_.ReservationId
        } |
        Select-Object -ExpandProperty ReservationId -Unique
)

if ($reservationIds.Count -ne 1) {
    Write-Host "FAIL: Expected exactly one reservation ID." -ForegroundColor Red
    Write-Host "Unique reservation IDs found: $($reservationIds.Count)"
    $failed = $true
}
else {
    Write-Host "PASS: Exactly one reservation was created." -ForegroundColor Green
    Write-Host "Reservation ID: $($reservationIds[0])"
}

Write-Host ""

# ---------------------------------------------------------
# 8. Fetch final show state
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
# 9. Print final state
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
# 10. Validate final counts
# ---------------------------------------------------------

if ($confirmed -ne 2) {
    Write-Host "FAIL: Expected exactly 2 confirmed seats." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Exactly 2 seats are CONFIRMED." -ForegroundColor Green
}

if ($available -ne 2) {
    Write-Host "FAIL: Expected 2 available seats." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: 2 seats remain AVAILABLE." -ForegroundColor Green
}

if ($held -ne 0) {
    Write-Host "FAIL: Expected 0 held seats." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Held seat count is 0." -ForegroundColor Green
}

# ---------------------------------------------------------
# 11. Validate reconciliation invariant
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
# 12. Validate A1
# ---------------------------------------------------------

$a1 = $finalShow.seats |
        Where-Object { $_.seat -eq $Seat1 }

if ($null -eq $a1) {
    Write-Host "FAIL: Seat $Seat1 not found." -ForegroundColor Red
    $failed = $true
}
elseif ($a1.status -ne "CONFIRMED") {
    Write-Host "FAIL: Seat $Seat1 status is $($a1.status), expected CONFIRMED." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Seat $Seat1 is CONFIRMED." -ForegroundColor Green
}

# ---------------------------------------------------------
# 13. Validate A2
# ---------------------------------------------------------

$a2 = $finalShow.seats |
        Where-Object { $_.seat -eq $Seat2 }

if ($null -eq $a2) {
    Write-Host "FAIL: Seat $Seat2 not found." -ForegroundColor Red
    $failed = $true
}
elseif ($a2.status -ne "CONFIRMED") {
    Write-Host "FAIL: Seat $Seat2 status is $($a2.status), expected CONFIRMED." -ForegroundColor Red
    $failed = $true
}
else {
    Write-Host "PASS: Seat $Seat2 is CONFIRMED." -ForegroundColor Green
}

# ---------------------------------------------------------
# 14. Validate A3 and A4 remain available
# ---------------------------------------------------------

foreach ($seatNumber in @("A3", "A4")) {

    $seat = $finalShow.seats |
            Where-Object { $_.seat -eq $seatNumber }

    if ($null -eq $seat) {
        Write-Host "FAIL: Seat $seatNumber not found." -ForegroundColor Red
        $failed = $true
    }
    elseif ($seat.status -ne "AVAILABLE") {
        Write-Host "FAIL: Seat $seatNumber status is $($seat.status), expected AVAILABLE." -ForegroundColor Red
        $failed = $true
    }
    else {
        Write-Host "PASS: Seat $seatNumber remains AVAILABLE." -ForegroundColor Green
    }
}

# ---------------------------------------------------------
# 15. Final result
# ---------------------------------------------------------

Write-Host ""
Write-Host "========================================="

if ($failed) {
    Write-Host " MULTI-SEAT ATOMICITY TEST FAILED" -ForegroundColor Red
    Write-Host "========================================="
    exit 1
}
else {
    Write-Host " MULTI-SEAT ATOMICITY TEST PASSED" -ForegroundColor Green
    Write-Host "========================================="
    exit 0
}