$ErrorActionPreference = "Stop"

$BaseUrl = "http://localhost:8080"
$RequestCount = 20
$UserId = "idempotency-test-user"
$Seat = "A1"
$IdempotencyKey = "idem-concurrent-$([guid]::NewGuid())"

Write-Host ""
Write-Host "========================================"
Write-Host " Idempotency Concurrency Test"
Write-Host "========================================"
Write-Host "Base URL        : $BaseUrl"
Write-Host "Requests        : $RequestCount"
Write-Host "User            : $UserId"
Write-Host "Seat            : $Seat"
Write-Host "Idempotency Key : $IdempotencyKey"
Write-Host ""

# ------------------------------------------------------------
# 1. Create a fresh show
# ------------------------------------------------------------

Write-Host "Creating test show..."

$showName = "Idempotency-Test-" + [guid]::NewGuid()

$createBody = @{
    name        = $showName
    seats       = @("A1", "A2", "A3", "A4")
    price_paise = 50000
} | ConvertTo-Json

$createFile = Join-Path $env:TEMP "create-idem-show-$([guid]::NewGuid()).json"

try {
    [System.IO.File]::WriteAllText(
            $createFile,
            $createBody,
            [System.Text.UTF8Encoding]::new($false)
    )

    $createResponse = curl.exe -s -X POST "$BaseUrl/shows" `
        -H "Content-Type: application/json" `
        --data-binary "@$createFile"

    $show = $createResponse | ConvertFrom-Json
    $ShowId = $show.id

    Write-Host "Created show: $ShowId"
}
finally {
    if (Test-Path $createFile) {
        Remove-Item $createFile -Force
    }
}

# ------------------------------------------------------------
# 2. Temporary directory
# ------------------------------------------------------------

$TestDir = Join-Path $env:TEMP "idempotency-test-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $TestDir | Out-Null

$jobs = @()

try {

    # --------------------------------------------------------
    # 3. Build ONE identical request body
    # --------------------------------------------------------

    $requestBody = @{
        seats = @($Seat)
        idempotency_key = $IdempotencyKey
    } | ConvertTo-Json

    Write-Host ""
    Write-Host "Request body used by ALL $RequestCount requests:"
    Write-Host $requestBody
    Write-Host ""

    # --------------------------------------------------------
    # 4. Create separate request files
    # --------------------------------------------------------

    for ($i = 1; $i -le $RequestCount; $i++) {

        $requestFile = Join-Path $TestDir "request-$i.json"
        $responseFile = Join-Path $TestDir "response-$i.txt"

        [System.IO.File]::WriteAllText(
                $requestFile,
                $requestBody,
                [System.Text.UTF8Encoding]::new($false)
        )

        # ----------------------------------------------------
        # Launch concurrent request
        # ----------------------------------------------------

        $job = Start-Job -ScriptBlock {

            param(
                $BaseUrl,
                $ShowId,
                $UserId,
                $RequestFile,
                $ResponseFile
            )

            curl.exe -s -i -X POST `
                "$BaseUrl/shows/$ShowId/reserve" `
                -H "Authorization: Bearer $UserId" `
                -H "Content-Type: application/json" `
                --data-binary "@$RequestFile" `
                > $ResponseFile

        } -ArgumentList `
            $BaseUrl,
        $ShowId,
        $UserId,
        $requestFile,
        $responseFile

        $jobs += $job
    }

    # --------------------------------------------------------
    # 5. Wait for all requests
    # --------------------------------------------------------

    Write-Host "Launching $RequestCount concurrent requests..."
    Write-Host "All requests use the SAME user, seat and idempotency key."
    Write-Host ""
    Write-Host "Waiting for all requests..."

    Wait-Job -Job $jobs | Out-Null

    Write-Host "All requests completed."

    # --------------------------------------------------------
    # 6. Parse responses
    # --------------------------------------------------------

    $responses = @()

    $responseFiles = Get-ChildItem $TestDir -Filter "response-*.txt"

    foreach ($file in $responseFiles) {

        $content = Get-Content $file.FullName -Raw

        if ([string]::IsNullOrWhiteSpace($content)) {
            continue
        }

        $status = $null

        if ($content -match "HTTP/1\.[01]\s+(\d{3})") {
            $status = [int]$matches[1]
        }

        $body = ""

        # HTTP headers and JSON body are separated by a blank line.
        $parts = $content -split "\r?\n\r?\n", 2

        if ($parts.Count -eq 2) {
            $body = $parts[1].Trim()
        }

        $responses += [PSCustomObject]@{
            File   = $file.Name
            Status = $status
            Body   = $body
        }
    }

    # --------------------------------------------------------
    # 7. Count HTTP responses
    # --------------------------------------------------------

    $http201 = @(
    $responses | Where-Object { $_.Status -eq 201 }
    ).Count

    $http409 = @(
    $responses | Where-Object { $_.Status -eq 409 }
    ).Count

    $http5xx = @(
    $responses | Where-Object {
        $_.Status -ge 500 -and $_.Status -le 599
    }
    ).Count

    $otherStatus = @(
    $responses | Where-Object {
        $_.Status -ne 201 -and
                $_.Status -ne 409
    }
    ).Count

    Write-Host ""
    Write-Host "========================================"
    Write-Host " Results"
    Write-Host "========================================"
    Write-Host "HTTP 201 : $http201"
    Write-Host "HTTP 409 : $http409"
    Write-Host "5xx      : $http5xx"
    Write-Host "Other    : $otherStatus"

    # --------------------------------------------------------
    # 8. Extract reservation IDs
    # --------------------------------------------------------

    $reservationIds = @()

    foreach ($response in $responses) {

        if ($response.Status -eq 201 -and
                -not [string]::IsNullOrWhiteSpace($response.Body)) {

            try {
                $json = $response.Body | ConvertFrom-Json

                if ($json.reservation_id) {
                    $reservationIds += $json.reservation_id
                }
            }
            catch {
                Write-Host "WARNING: Could not parse response from $($response.File)"
            }
        }
    }

    $uniqueReservationIds = @(
    $reservationIds | Sort-Object -Unique
    )

    Write-Host ""
    Write-Host "Successful reservation IDs:"

    foreach ($id in $uniqueReservationIds) {
        Write-Host "  $id"
    }

    # --------------------------------------------------------
    # 9. Fetch final show state
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Final show state:"

    $finalShowJson = curl.exe -s "$BaseUrl/shows/$ShowId"
    $finalShow = $finalShowJson | ConvertFrom-Json

    $finalShow | ConvertTo-Json -Depth 10

    $totalSeats = $finalShow.total_seats
    $availableSeats = $finalShow.available_seats
    $heldSeats = $finalShow.held_seats
    $confirmedSeats = $finalShow.confirmed_seats

    # --------------------------------------------------------
    # 10. Assertions
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Assertions:"

    $failed = $false

    # We expect all concurrent requests to return the same
    # successful reservation result.
    if ($http201 -eq $RequestCount) {
        Write-Host "PASS: All $RequestCount requests returned 201."
    }
    else {
        Write-Host "FAIL: Expected $RequestCount successful responses, got $http201."
        $failed = $true
    }

    # There should be exactly ONE reservation ID.
    if ($uniqueReservationIds.Count -eq 1) {
        Write-Host "PASS: All requests returned the same reservation ID."
    }
    else {
        Write-Host "FAIL: Expected exactly 1 unique reservation ID, got $($uniqueReservationIds.Count)."
        $failed = $true
    }

    # No conflicts should occur because the same idempotency
    # request is a valid replay.
    if ($http409 -eq 0) {
        Write-Host "PASS: Zero 409 responses for identical idempotent requests."
    }
    else {
        Write-Host "FAIL: Expected 0 conflicts, got $http409."
        $failed = $true
    }

    # No server errors.
    if ($http5xx -eq 0) {
        Write-Host "PASS: Zero 5xx responses."
    }
    else {
        Write-Host "FAIL: Found $http5xx 5xx responses."
        $failed = $true
    }

    # No unexpected statuses.
    if ($otherStatus -eq 0) {
        Write-Host "PASS: No unexpected HTTP statuses."
    }
    else {
        Write-Host "FAIL: Found $otherStatus unexpected responses."
        $failed = $true
    }

    # Exactly one physical reservation must exist.
    if ($confirmedSeats -eq 1) {
        Write-Host "PASS: Exactly one seat is physically confirmed."
    }
    else {
        Write-Host "FAIL: Expected exactly 1 confirmed seat, got $confirmedSeats."
        $failed = $true
    }

    # Seat should only be sold once.
    if ($availableSeats -eq ($totalSeats - 1)) {
        Write-Host "PASS: Only one seat was consumed."
    }
    else {
        Write-Host "FAIL: Unexpected available seat count."
        $failed = $true
    }

    # Reconciliation invariant.
    $invariant = $availableSeats + $heldSeats + $confirmedSeats

    if ($invariant -eq $totalSeats) {
        Write-Host "PASS: Seat invariant holds: $availableSeats + $heldSeats + $confirmedSeats = $totalSeats"
    }
    else {
        Write-Host "FAIL: Seat invariant violated: $availableSeats + $heldSeats + $confirmedSeats != $totalSeats"
        $failed = $true
    }

    # --------------------------------------------------------
    # 11. Final result
    # --------------------------------------------------------

    Write-Host ""

    if ($failed) {
        Write-Host "IDEMPOTENCY CONCURRENCY TEST FAILED"
        exit 1
    }
    else {
        Write-Host "Show ID: $ShowId"
        Write-Host "Reservation ID: $($uniqueReservationIds[0])"
        Write-Host ""
        Write-Host "IDEMPOTENCY CONCURRENCY TEST PASSED"
    }

}
finally {

    foreach ($job in $jobs) {
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $TestDir) {
        Remove-Item $TestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}