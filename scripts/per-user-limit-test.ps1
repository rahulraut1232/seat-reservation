$ErrorActionPreference = "Stop"

$BaseUrl = "http://localhost:8080"
$RequestCount = 10
$PerUserLimit = 4

$UserId = "per-user-limit-test-user"

Write-Host ""
Write-Host "========================================"
Write-Host " Per-User Booking Limit Concurrency Test"
Write-Host "========================================"
Write-Host "Base URL      : $BaseUrl"
Write-Host "Requests      : $RequestCount"
Write-Host "Per-user limit: $PerUserLimit"
Write-Host "User          : $UserId"
Write-Host ""

# ------------------------------------------------------------
# Helper: execute authenticated curl request
# ------------------------------------------------------------

function Invoke-CurlRequest {
    param(
        [string]$Url,
        [string]$Method,
        [string]$RequestFile,
        [string]$ResponseFile,
        [string]$Token
    )

    $StatusFile = "$ResponseFile.status"

    if (Test-Path $ResponseFile) {
        Remove-Item $ResponseFile -Force
    }

    if (Test-Path $StatusFile) {
        Remove-Item $StatusFile -Force
    }

    & curl.exe `
        -s `
        -o $ResponseFile `
        -w "%{http_code}" `
        -X $Method `
        $Url `
        -H "Authorization: Bearer $Token" `
        -H "Content-Type: application/json" `
        --data-binary "@$RequestFile" |
            Set-Content -Path $StatusFile

    $Status = (Get-Content $StatusFile -Raw).Trim()

    if (-not $Status) {
        $Status = "000"
    }

    $Body = ""

    if (Test-Path $ResponseFile) {
        $Body = Get-Content $ResponseFile -Raw
    }

    return @{
        Status = $Status
        Body   = $Body
    }
}

# ------------------------------------------------------------
# Create a unique show
# ------------------------------------------------------------

Write-Host "Creating test show..."

$ShowName = "PerUserLimit-Test-$(New-Guid)"

$Seats = @(
    "A1",
    "A2",
    "A3",
    "A4",
    "A5",
    "A6",
    "A7",
    "A8",
    "A9",
    "A10"
)

$ShowRequest = @{
    name        = $ShowName
    seats       = $Seats
    price_paise = 50000
} | ConvertTo-Json -Compress

$ShowRequestFile = Join-Path $env:TEMP "per-user-limit-show-request.json"
$ShowResponseFile = Join-Path $env:TEMP "per-user-limit-show-response.json"

$ShowRequest | Set-Content -Path $ShowRequestFile -Encoding UTF8

$ShowResult = Invoke-CurlRequest `
    -Url "$BaseUrl/shows" `
    -Method "POST" `
    -RequestFile $ShowRequestFile `
    -ResponseFile $ShowResponseFile `
    -Token "per-user-limit-admin"

Write-Host "Create show HTTP status: $($ShowResult.Status)"

if ($ShowResult.Status -ne "200" -and $ShowResult.Status -ne "201") {
    Write-Host "FAIL: Could not create test show."
    Write-Host "Response:"
    Write-Host $ShowResult.Body
    exit 1
}

$Show = $ShowResult.Body | ConvertFrom-Json
$ShowId = $Show.id

if (-not $ShowId) {
    Write-Host "FAIL: Show ID was not returned."
    Write-Host $ShowResult.Body
    exit 1
}

Write-Host "Created show: $ShowId"
Write-Host ""

# ------------------------------------------------------------
# Prepare concurrent requests
# ------------------------------------------------------------

$TempDirectory = Join-Path $env:TEMP "per-user-limit-$([Guid]::NewGuid())"

New-Item `
    -ItemType Directory `
    -Path $TempDirectory `
    -Force |
        Out-Null

Write-Host "Launching $RequestCount concurrent reservations..."
Write-Host "All requests use the SAME authenticated user."
Write-Host ""

$Jobs = @()

for ($i = 1; $i -le $RequestCount; $i++) {

    $SeatNumber = "A$i"
    $IdempotencyKey = "per-user-limit-$ShowId-$i"

    $RequestFile = Join-Path $TempDirectory "request-$i.json"
    $ResponseFile = Join-Path $TempDirectory "response-$i.json"
    $StatusFile = Join-Path $TempDirectory "status-$i.txt"

    $RequestBody = @{
        seats           = @($SeatNumber)
        idempotency_key = $IdempotencyKey
    } | ConvertTo-Json -Compress

    $RequestBody |
            Set-Content `
            -Path $RequestFile `
            -Encoding UTF8

    $Jobs += Start-Job -ScriptBlock {
        param(
            $BaseUrl,
            $ShowId,
            $RequestFile,
            $ResponseFile,
            $StatusFile,
            $UserId
        )

        try {

            & curl.exe `
                -s `
                -o $ResponseFile `
                -w "%{http_code}" `
                -X POST `
                "$BaseUrl/shows/$ShowId/reserve" `
                -H "Authorization: Bearer $UserId" `
                -H "Content-Type: application/json" `
                --data-binary "@$RequestFile" |
                    Set-Content -Path $StatusFile

        }
        catch {

            "000" |
                    Set-Content `
                    -Path $StatusFile

            $_.Exception.Message |
                    Set-Content `
                    -Path $ResponseFile
        }

    } -ArgumentList `
        $BaseUrl,
    $ShowId,
    $RequestFile,
    $ResponseFile,
    $StatusFile,
    $UserId
}

# ------------------------------------------------------------
# Wait for all requests
# ------------------------------------------------------------

Write-Host "Waiting for all requests..."

$Jobs |
        Wait-Job |
        Out-Null

$Jobs |
        Remove-Job `
        -Force

Write-Host "All requests completed."
Write-Host ""

# ------------------------------------------------------------
# Collect results
# ------------------------------------------------------------

$Results = @()

for ($i = 1; $i -le $RequestCount; $i++) {

    $ResponseFile =
    Join-Path $TempDirectory "response-$i.json"

    $StatusFile =
    Join-Path $TempDirectory "status-$i.txt"

    $Status = "000"
    $Body = ""

    if (Test-Path $StatusFile) {
        $Status =
        (Get-Content $StatusFile -Raw).Trim()
    }

    if (Test-Path $ResponseFile) {
        $Body =
        Get-Content $ResponseFile -Raw
    }

    $Results += [PSCustomObject]@{
        Request = $i
        Seat    = "A$i"
        Status  = $Status
        Body    = $Body
    }
}

# ------------------------------------------------------------
# Count results
# ------------------------------------------------------------

$Count201 = @(
$Results |
        Where-Object { $_.Status -eq "201" }
).Count

$Count409 = @(
$Results |
        Where-Object { $_.Status -eq "409" }
).Count

$Count401 = @(
$Results |
        Where-Object { $_.Status -eq "401" }
).Count

$Count403 = @(
$Results |
        Where-Object { $_.Status -eq "403" }
).Count

$Count5xx = @(
$Results |
        Where-Object {
            $_.Status -match "^5\d\d$"
        }
).Count

$CountOther = @(
$Results |
        Where-Object {
            $_.Status -notmatch "^(201|409|401|403)$"
        }
).Count

Write-Host "========================================"
Write-Host " Results"
Write-Host "========================================"
Write-Host "HTTP 201: $Count201"
Write-Host "HTTP 409: $Count409"
Write-Host "HTTP 401: $Count401"
Write-Host "HTTP 403: $Count403"
Write-Host "5xx Errors: $Count5xx"
Write-Host "Other: $CountOther"
Write-Host ""

# ------------------------------------------------------------
# Print unexpected responses
# ------------------------------------------------------------

$Unexpected = @(
$Results |
        Where-Object {
            $_.Status -notmatch "^(201|409)$"
        }
)

if ($Unexpected.Count -gt 0) {

    Write-Host "Unexpected responses:"
    Write-Host ""

    foreach ($Result in $Unexpected) {

        Write-Host "Request: $($Result.Request)"
        Write-Host "Seat   : $($Result.Seat)"
        Write-Host "Status : $($Result.Status)"
        Write-Host "Body   :"
        Write-Host $Result.Body
        Write-Host ""
    }
}

# ------------------------------------------------------------
# Fetch final show state
# ------------------------------------------------------------

Write-Host "Final show state:"

$FinalShowResponseFile =
Join-Path $env:TEMP "per-user-limit-final-show.json"

& curl.exe `
    -s `
    -o $FinalShowResponseFile `
    "$BaseUrl/shows/$ShowId"

$FinalShowBody =
Get-Content $FinalShowResponseFile -Raw

Write-Host $FinalShowBody
Write-Host ""

$FinalShow =
$FinalShowBody | ConvertFrom-Json

# ------------------------------------------------------------
# Assertions
# ------------------------------------------------------------

Write-Host "========================================"
Write-Host " Assertions"
Write-Host "========================================"

$Passed = $true

# ------------------------------------------------------------
# Exactly four successful reservations
# ------------------------------------------------------------

if ($Count201 -eq $PerUserLimit) {

    Write-Host "PASS: Exactly $PerUserLimit reservations succeeded."

}
else {

    Write-Host "FAIL: Expected exactly $PerUserLimit successful reservations. Got $Count201."

    $Passed = $false
}

# ------------------------------------------------------------
# Remaining requests must be conflicts
# ------------------------------------------------------------

$Expected409 = $RequestCount - $PerUserLimit

if ($Count409 -eq $Expected409) {

    Write-Host "PASS: Expected conflict count: $Expected409."

}
else {

    Write-Host "FAIL: Expected $Expected409 conflicts. Got $Count409."

    $Passed = $false
}

# ------------------------------------------------------------
# No authentication failures
# ------------------------------------------------------------

if ($Count401 -eq 0 -and $Count403 -eq 0) {

    Write-Host "PASS: All requests were authenticated."

}
else {

    Write-Host "FAIL: Authentication failures detected."

    $Passed = $false
}

# ------------------------------------------------------------
# No 5xx
# ------------------------------------------------------------

if ($Count5xx -eq 0) {

    Write-Host "PASS: Zero 5xx responses."

}
else {

    Write-Host "FAIL: Found $Count5xx 5xx responses."

    $Passed = $false
}

# ------------------------------------------------------------
# Final seat counts
# ------------------------------------------------------------

if ($FinalShow.confirmed_seats -eq $PerUserLimit) {

    Write-Host "PASS: Confirmed seat count is $PerUserLimit."

}
else {

    Write-Host "FAIL: Expected $PerUserLimit confirmed seats. Got $($FinalShow.confirmed_seats)."

    $Passed = $false
}

if ($FinalShow.held_seats -eq 0) {

    Write-Host "PASS: Held seat count is 0."

}
else {

    Write-Host "FAIL: Expected held seat count 0. Got $($FinalShow.held_seats)."

    $Passed = $false
}

# ------------------------------------------------------------
# Verify invariant
# ------------------------------------------------------------

$Total =
[int]$FinalShow.total_seats

$Available =
[int]$FinalShow.available_seats

$Held =
[int]$FinalShow.held_seats

$Confirmed =
[int]$FinalShow.confirmed_seats

if (($Available + $Held + $Confirmed) -eq $Total) {

    Write-Host "PASS: Seat invariant holds: $Available + $Held + $Confirmed = $Total"

}
else {

    Write-Host "FAIL: Seat invariant violated:"
    Write-Host "      $Available + $Held + $Confirmed != $Total"

    $Passed = $false
}

# ------------------------------------------------------------
# Verify exactly four seats are confirmed
# ------------------------------------------------------------

$ConfirmedSeats = @(
$FinalShow.seats |
        Where-Object {
            $_.status -eq "CONFIRMED"
        }
)

if ($ConfirmedSeats.Count -eq $PerUserLimit) {

    Write-Host "PASS: Exactly $PerUserLimit seats are CONFIRMED."

}
else {

    Write-Host "FAIL: Expected $PerUserLimit confirmed seats. Got $($ConfirmedSeats.Count)."

    $Passed = $false
}

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

if (Test-Path $TempDirectory) {

    Remove-Item `
        $TempDirectory `
        -Recurse `
        -Force
}

if (Test-Path $ShowRequestFile) {

    Remove-Item `
        $ShowRequestFile `
        -Force
}

if (Test-Path $ShowResponseFile) {

    Remove-Item `
        $ShowResponseFile `
        -Force
}

if (Test-Path $FinalShowResponseFile) {

    Remove-Item `
        $FinalShowResponseFile `
        -Force
}

# ------------------------------------------------------------
# Final result
# ------------------------------------------------------------

Write-Host ""
Write-Host "========================================"

if ($Passed) {

    Write-Host " PER-USER LIMIT TEST PASSED"

}
else {

    Write-Host " PER-USER LIMIT TEST FAILED"

}

Write-Host "========================================"
Write-Host ""

Write-Host "Verified:"
Write-Host "  - Same authenticated user across all concurrent requests"
Write-Host "  - Per-user limit of $PerUserLimit enforced"
Write-Host "  - No concurrent overbooking"
Write-Host "  - Zero 5xx responses"
Write-Host "  - Seat reconciliation invariant holds"
Write-Host ""
Write-Host "Show ID: $ShowId"

if (-not $Passed) {
    exit 1
}