$ErrorActionPreference = "Stop"

$BaseUrl = "http://localhost:8080"
$RequestCount = 10
$UserPrefix = "multi-seat-user"

Write-Host ""
Write-Host "========================================"
Write-Host " Multi-Seat Atomicity Concurrency Test"
Write-Host "========================================"
Write-Host "Base URL : $BaseUrl"
Write-Host "Requests : $RequestCount"
Write-Host "Seats    : A1 + A2"
Write-Host ""

# ------------------------------------------------------------
# Helper: extract HTTP status
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
# Helper: extract JSON body
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# 1. Create fresh show
# ------------------------------------------------------------

Write-Host "Creating test show..."

$showName = "MultiSeat-Atomicity-Test-" + [guid]::NewGuid()

$createBody = @{
    name        = $showName
    seats       = @("A1", "A2", "A3", "A4")
    price_paise = 50000
} | ConvertTo-Json

$createFile = Join-Path `
    $env:TEMP `
    "create-multiseat-show-$([guid]::NewGuid()).json"

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
# 2. Temporary test directory
# ------------------------------------------------------------

$TestDir = Join-Path `
    $env:TEMP `
    "multiseat-atomicity-$([guid]::NewGuid())"

New-Item -ItemType Directory -Path $TestDir | Out-Null

$jobs = @()

try {

    # --------------------------------------------------------
    # 3. Launch concurrent multi-seat reservations
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Launching $RequestCount concurrent requests..."
    Write-Host ""
    Write-Host "Every request attempts:"
    Write-Host "  A1 + A2"
    Write-Host ""
    Write-Host "Each request uses a different user and idempotency key."
    Write-Host ""

    for ($i = 1; $i -le $RequestCount; $i++) {

        $userId = "$UserPrefix-$i"
        $idempotencyKey = "multiseat-$i-$([guid]::NewGuid())"

        $requestBody = @{
            seats = @("A1", "A2")
            idempotency_key = $idempotencyKey
        } | ConvertTo-Json

        $requestFile = Join-Path `
            $TestDir `
            "request-$i.json"

        $responseFile = Join-Path `
            $TestDir `
            "response-$i.txt"

        [System.IO.File]::WriteAllText(
                $requestFile,
                $requestBody,
                [System.Text.UTF8Encoding]::new($false)
        )

        $job = Start-Job -ScriptBlock {

            param(
                $BaseUrl,
                $ShowId,
                $UserId,
                $RequestFile,
                $ResponseFile
            )

            curl.exe -s -i `
                -X POST `
                "$BaseUrl/shows/$ShowId/reserve" `
                -H "Authorization: Bearer $UserId" `
                -H "Content-Type: application/json" `
                --data-binary "@$RequestFile" `
                > $ResponseFile

        } -ArgumentList `
            $BaseUrl,
        $ShowId,
        $userId,
        $requestFile,
        $responseFile

        $jobs += $job
    }

    # --------------------------------------------------------
    # 4. Wait for all requests
    # --------------------------------------------------------

    Write-Host "Waiting for all requests..."

    Wait-Job -Job $jobs | Out-Null

    Write-Host "All requests completed."

    # --------------------------------------------------------
    # 5. Parse responses
    # --------------------------------------------------------

    $responses = @()

    $responseFiles = Get-ChildItem `
        $TestDir `
        -Filter "response-*.txt"

    foreach ($file in $responseFiles) {

        $content = Get-Content `
            $file.FullName `
            -Raw

        if ([string]::IsNullOrWhiteSpace($content)) {
            continue
        }

        $status = Get-HttpStatus $content
        $body = Get-ResponseBody $content

        $responses += [PSCustomObject]@{
            File   = $file.Name
            Status = $status
            Body   = $body
        }
    }

    # --------------------------------------------------------
    # 6. Count statuses
    # --------------------------------------------------------

    $http201 = @(
    $responses |
            Where-Object { $_.Status -eq 201 }
    ).Count

    $http409 = @(
    $responses |
            Where-Object { $_.Status -eq 409 }
    ).Count

    $http5xx = @(
    $responses |
            Where-Object {
                $_.Status -ge 500 -and
                        $_.Status -le 599
            }
    ).Count

    $otherStatus = @(
    $responses |
            Where-Object {
                $_.Status -ne 201 -and
                        $_.Status -ne 409
            }
    ).Count

    # --------------------------------------------------------
    # 7. Results
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "========================================"
    Write-Host " Results"
    Write-Host "========================================"
    Write-Host "HTTP 201 : $http201"
    Write-Host "HTTP 409 : $http409"
    Write-Host "5xx      : $http5xx"
    Write-Host "Other    : $otherStatus"

    # --------------------------------------------------------
    # 8. Fetch final show state
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Final show state:"

    $finalShowJson = curl.exe -s `
        "$BaseUrl/shows/$ShowId"

    if ([string]::IsNullOrWhiteSpace($finalShowJson)) {

        Write-Host "FAIL: Could not retrieve final show state."
        exit 1
    }

    $finalShow = $finalShowJson | ConvertFrom-Json

    $finalShow | ConvertTo-Json -Depth 10

    # --------------------------------------------------------
    # 9. Locate A1 and A2
    # --------------------------------------------------------

    $a1 = $finalShow.seats |
            Where-Object { $_.seat -eq "A1" }

    $a2 = $finalShow.seats |
            Where-Object { $_.seat -eq "A2" }

    # --------------------------------------------------------
    # 10. Assertions
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Assertions:"

    $failed = $false

    # Exactly one request should succeed.
    if ($http201 -eq 1) {
        Write-Host "PASS: Exactly one multi-seat reservation succeeded."
    }
    else {
        Write-Host "FAIL: Expected exactly 1 successful reservation, got $http201."
        $failed = $true
    }

    # Remaining requests should conflict.
    $expected409 = $RequestCount - 1

    if ($http409 -eq $expected409) {
        Write-Host "PASS: Remaining $expected409 requests returned 409."
    }
    else {
        Write-Host "FAIL: Expected $expected409 conflicts, got $http409."
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

    # --------------------------------------------------------
    # Atomicity checks
    # --------------------------------------------------------

    if ($null -ne $a1 -and $a1.status -eq "CONFIRMED") {
        Write-Host "PASS: A1 is CONFIRMED."
    }
    else {
        Write-Host "FAIL: A1 is not CONFIRMED."
        $failed = $true
    }

    if ($null -ne $a2 -and $a2.status -eq "CONFIRMED") {
        Write-Host "PASS: A2 is CONFIRMED."
    }
    else {
        Write-Host "FAIL: A2 is not CONFIRMED."
        $failed = $true
    }

    # Both seats must be confirmed together.
    $confirmedTargetSeats = @(
    $finalShow.seats |
            Where-Object {
                ($_.seat -eq "A1" -or $_.seat -eq "A2") -and
                        $_.status -eq "CONFIRMED"
            }
    ).Count

    if ($confirmedTargetSeats -eq 2) {
        Write-Host "PASS: A1 and A2 were confirmed atomically."
    }
    else {
        Write-Host "FAIL: Expected both A1 and A2 to be confirmed."
        $failed = $true
    }

    # Exactly two seats should be confirmed.
    if ($finalShow.confirmed_seats -eq 2) {
        Write-Host "PASS: Exactly two seats are confirmed."
    }
    else {
        Write-Host "FAIL: Expected 2 confirmed seats, got $($finalShow.confirmed_seats)."
        $failed = $true
    }

    # A3 and A4 should remain untouched.
    $a3 = $finalShow.seats |
            Where-Object { $_.seat -eq "A3" }

    $a4 = $finalShow.seats |
            Where-Object { $_.seat -eq "A4" }

    if ($null -ne $a3 -and $a3.status -eq "AVAILABLE") {
        Write-Host "PASS: A3 remains AVAILABLE."
    }
    else {
        Write-Host "FAIL: A3 was unexpectedly changed."
        $failed = $true
    }

    if ($null -ne $a4 -and $a4.status -eq "AVAILABLE") {
        Write-Host "PASS: A4 remains AVAILABLE."
    }
    else {
        Write-Host "FAIL: A4 was unexpectedly changed."
        $failed = $true
    }

    # --------------------------------------------------------
    # Seat reconciliation invariant
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # 11. Final result
    # --------------------------------------------------------

    Write-Host ""

    if ($failed) {

        Write-Host "========================================"
        Write-Host " MULTI-SEAT ATOMICITY TEST FAILED"
        Write-Host "========================================"

        exit 1
    }
    else {

        Write-Host "========================================"
        Write-Host " MULTI-SEAT ATOMICITY TEST PASSED"
        Write-Host "========================================"

        Write-Host ""
        Write-Host "Show ID: $ShowId"
        Write-Host ""
        Write-Host "A1 = CONFIRMED"
        Write-Host "A2 = CONFIRMED"
        Write-Host "A3 = AVAILABLE"
        Write-Host "A4 = AVAILABLE"
        Write-Host ""
        Write-Host "Multi-seat reservation is atomic."
    }

}
finally {

    foreach ($job in $jobs) {
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $TestDir) {
        Remove-Item `
            $TestDir `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}