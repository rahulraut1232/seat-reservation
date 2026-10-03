$ErrorActionPreference = "Stop"

$BaseUrl = "http://localhost:8080"
$RequestCount = 10
$PerUserLimit = 4
$UserId = "limit-test-user"

Write-Host ""
Write-Host "========================================"
Write-Host " Per-User Booking Limit Concurrency Test"
Write-Host "========================================"
Write-Host "Base URL : $BaseUrl"
Write-Host "Requests : $RequestCount"
Write-Host "User     : $UserId"
Write-Host "Limit    : $PerUserLimit"
Write-Host ""

# ------------------------------------------------------------
# 1. Create a fresh show with 10 different seats
# ------------------------------------------------------------

Write-Host "Creating test show..."

$showName = "PerUserLimit-Test-" + [guid]::NewGuid()

$createBody = @{
    name       = $showName
    seats      = @(
        "A1", "A2", "A3", "A4", "A5",
        "A6", "A7", "A8", "A9", "A10"
    )
    price_paise = 50000
} | ConvertTo-Json

$createFile = Join-Path $env:TEMP "create-show-$([guid]::NewGuid()).json"

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
# 2. Create temporary directory for concurrent requests
# ------------------------------------------------------------

$TestDir = Join-Path $env:TEMP "per-user-limit-test-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $TestDir | Out-Null

$jobs = @()

try {

    Write-Host ""
    Write-Host "Launching $RequestCount concurrent reservations..."
    Write-Host "All requests use the same user but different seats."
    Write-Host ""

    # --------------------------------------------------------
    # 3. Launch concurrent requests
    # --------------------------------------------------------

    for ($i = 1; $i -le $RequestCount; $i++) {

        $seat = "A$i"
        $idempotencyKey = "per-user-limit-$i-$([guid]::NewGuid())"

        $requestBody = @{
            seats = @($seat)
            idempotency_key = $idempotencyKey
        } | ConvertTo-Json

        $requestFile = Join-Path $TestDir "request-$i.json"
        $responseFile = Join-Path $TestDir "response-$i.txt"

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
    # 4. Wait for all requests
    # --------------------------------------------------------

    Write-Host "Waiting for all requests..."

    Wait-Job -Job $jobs | Out-Null

    Write-Host "All requests completed."

    # --------------------------------------------------------
    # 5. Parse HTTP responses
    # --------------------------------------------------------

    $statusCodes = @()
    $successfulReservations = @()
    $declinedReservations = @()

    foreach ($job in $jobs) {

        $jobInfo = $job.ChildJobs[0]

        if ($jobInfo.State -ne "Completed") {
            Write-Host "ERROR: Job did not complete successfully."
            Receive-Job $job
            continue
        }

        $responseFile = $null

        # Find the response file associated with this job.
        # We identify it from the job's arguments by checking
        # all generated response files.
        $responseFiles = Get-ChildItem $TestDir -Filter "response-*.txt"

        foreach ($file in $responseFiles) {

            $content = Get-Content $file.FullName -Raw

            if ([string]::IsNullOrWhiteSpace($content)) {
                continue
            }

            if ($content -match "HTTP/1\.[01]\s+(\d{3})") {

                $status = [int]$matches[1]

                if (-not ($statusCodes | Where-Object {
                    $_.File -eq $file.FullName
                })) {
                    $statusCodes += [PSCustomObject]@{
                        File   = $file.FullName
                        Status = $status
                        Body   = $content
                    }
                }
            }
        }
    }

    # --------------------------------------------------------
    # 6. Results
    # --------------------------------------------------------

    $http201 = @($statusCodes | Where-Object { $_.Status -eq 201 }).Count
    $http409 = @($statusCodes | Where-Object { $_.Status -eq 409 }).Count
    $http5xx = @($statusCodes | Where-Object {
        $_.Status -ge 500 -and $_.Status -le 599
    }).Count

    Write-Host ""
    Write-Host "========================================"
    Write-Host " Results"
    Write-Host "========================================"
    Write-Host "HTTP 201: $http201"
    Write-Host "HTTP 409: $http409"
    Write-Host "5xx     : $http5xx"
    Write-Host ""

    # --------------------------------------------------------
    # 7. Fetch final show state
    # --------------------------------------------------------

    Write-Host "Final show state:"

    $finalShowJson = curl.exe -s "$BaseUrl/shows/$ShowId"
    $finalShow = $finalShowJson | ConvertFrom-Json

    $finalShow | ConvertTo-Json -Depth 10

    $totalSeats = $finalShow.total_seats
    $availableSeats = $finalShow.available_seats
    $heldSeats = $finalShow.held_seats
    $confirmedSeats = $finalShow.confirmed_seats

    # --------------------------------------------------------
    # 8. Assertions
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Assertions:"

    $failed = $false

    if ($http201 -eq $PerUserLimit) {
        Write-Host "PASS: Exactly $PerUserLimit reservations succeeded."
    }
    else {
        Write-Host "FAIL: Expected $PerUserLimit successful reservations, got $http201."
        $failed = $true
    }

    $expected409 = $RequestCount - $PerUserLimit

    if ($http409 -eq $expected409) {
        Write-Host "PASS: Remaining requests were rejected with 409."
    }
    else {
        Write-Host "FAIL: Expected $expected409 conflicts, got $http409."
        $failed = $true
    }

    if ($http5xx -eq 0) {
        Write-Host "PASS: Zero 5xx responses."
    }
    else {
        Write-Host "FAIL: Found $http5xx 5xx responses."
        $failed = $true
    }

    if ($confirmedSeats -eq $PerUserLimit) {
        Write-Host "PASS: Final confirmed seat count is $PerUserLimit."
    }
    else {
        Write-Host "FAIL: Expected $PerUserLimit confirmed seats, got $confirmedSeats."
        $failed = $true
    }

    if ($availableSeats -eq ($RequestCount - $PerUserLimit)) {
        Write-Host "PASS: Remaining seats are available."
    }
    else {
        Write-Host "FAIL: Unexpected available seat count."
        $failed = $true
    }

    $invariant = $availableSeats + $heldSeats + $confirmedSeats

    if ($invariant -eq $totalSeats) {
        Write-Host "PASS: Seat invariant holds: $availableSeats + $heldSeats + $confirmedSeats = $totalSeats"
    }
    else {
        Write-Host "FAIL: Seat invariant violated: $availableSeats + $heldSeats + $confirmedSeats != $totalSeats"
        $failed = $true
    }

    # --------------------------------------------------------
    # 9. Final result
    # --------------------------------------------------------

    Write-Host ""

    if ($failed) {
        Write-Host "PER-USER LIMIT TEST FAILED"
        exit 1
    }
    else {
        Write-Host "Show ID: $ShowId"
        Write-Host "PER-USER LIMIT TEST PASSED"
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