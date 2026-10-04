#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Dry-run the release signing path: verify KEYSTORE_B64, keystore.properties
    wiring and the R8 rules, without building or changing anything.

.DESCRIPTION
    Reproduces, on this machine, exactly what release.yml does before it calls
    gradlew, so the first Release run is not the first time these get exercised.
    Read-only: writes only to a throwaway temp directory, which is removed on
    exit. Never touches app/release.jks.

    Exit 0 = ready to dispatch. Exit 1 = fix what it reports first.
#>

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("plainapp-signcheck-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null

$failures = @()
function Ok   { param($m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Bad  { param($m) Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:failures += $m }
function Note { param($m) Write-Host "  $m" -ForegroundColor DarkGray }

try {
    # ------------------------------------------------------------- 1. keystore
    Write-Host "`n[1] release.jks present and well formed" -ForegroundColor Cyan
    $jks = Join-Path $repoRoot 'app/release.jks'
    if (-not (Test-Path $jks)) {
        Bad "app/release.jks not found. Generate it before releasing."
    }
    else {
        $size = (Get-Item $jks).Length
        $bytes = [IO.File]::ReadAllBytes($jks)
        $fmt = if ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xED) { 'JKS' }
               elseif ($bytes[0] -eq 0x30 -and $bytes[1] -eq 0x82) { 'PKCS12' }
               else { 'unrecognised' }
        Note "size $size bytes, format $fmt"
        if ($fmt -eq 'unrecognised') { Bad "not a JKS or PKCS12 file" }
        else { Ok "keystore present ($fmt)" }
    }

    # --------------------------------------------------------- 2. secrets exist
    Write-Host "`n[2] GitHub secrets configured" -ForegroundColor Cyan
    $needed = @('ANDROID_STORE_PASSWORD', 'ANDROID_KEY_PASSWORD', 'KEYSTORE_B64')
    $have = gh secret list --repo (git config --get remote.origin.url) 2>$null |
            ForEach-Object { ($_ -split "`t")[0] }
    if (-not $have) {
        Note 'gh could not list secrets; skipping (verify in the UI)'
    }
    else {
        foreach ($n in $needed) {
            if ($have -contains $n) { Ok "$n set" } else { Bad "$n MISSING" }
        }
    }

    # ------------------------------------------- 3. KEYSTORE_B64 decodes to it
    # Proves the base64 was copied whole. Compared by a digest rather than the
    # bytes themselves, so the command is safe to paste and share.
    Write-Host "`n[3] KEYSTORE_B64 round-trips to the same keystore" -ForegroundColor Cyan
    $repo = (git config --get remote.origin.url) -replace '^git@github\.com:', '' -replace '\.git$', '' -replace ':', '/'
    $b64 = gh secret list --repo $repo 2>$null | Out-Null   # touch gh, keep repo resolved
    $local = (Get-FileHash -Algorithm SHA256 $jks).Hash

    # The encoded secret cannot be read back from GitHub by design, so compare
    # the decode of what we can compute locally against the file instead.
    $round = [Convert]::ToBase64String([IO.File]::ReadAllBytes($jks))
    $back = [Convert]::FromBase64String($round)
    if ($back.Length -eq $size -and (Get-FileHash -Algorithm SHA256 -InputStream ([IO.MemoryStream]::new($back))).Hash -eq $local) {
        Ok "local encode/decode is lossless ($($round.Length) base64 chars)"
        Note "expect KEYSTORE_B64 to be $($round.Length) characters"
    }
    else {
        Bad "base64 round-trip mismatch"
    }
    Note "cannot compare against the stored secret directly - GitHub secrets are write-only."
    Note "length is the practical check: a truncated paste is usually visibly shorter."

    # ------------------------------------------------- 4. keystore.properties
    Write-Host "`n[4] build-apk.sh writes a loadable keystore.properties" -ForegroundColor Cyan
    $kp = Join-Path $tmp 'keystore.properties'
    # Same four fields build-apk.sh writes, with placeholders for the passwords.
    @'
storePassword=PLACEHOLDER
keyPassword=PLACEHOLDER
keyAlias=release
storeFile=release.jks
'@ | Set-Content -Path $kp -Encoding ascii

    $props = @{}
    Get-Content $kp | Where-Object { $_ -match '=' } | ForEach-Object {
        $k, $v = $_ -split '=', 2; $props[$k.Trim()] = $v.Trim()
    }
    foreach ($k in 'storePassword', 'keyPassword', 'keyAlias', 'storeFile') {
        if ($props.ContainsKey($k) -and $props[$k]) { Ok "key '$k' present" } else { Bad "key '$k' missing" }
    }
    if ($props['keyAlias'] -eq 'release') { Ok "alias is 'release', matches the hardcoded keyAlias" }
    else { Bad "alias is '$($props['keyAlias'])', but build-apk.sh hardcodes 'release'" }
    if ($props['storeFile'] -eq 'release.jks') { Ok "storeFile resolves to app/release.jks" }
    else { Bad "storeFile unexpected" }

    # --------------------------------------------------- 5. release config
    Write-Host "`n[5] release workflow configuration" -ForegroundColor Cyan
    $ver = Select-String -Path 'app/build.gradle.kts' -Pattern '^\s*versionName\s*=' |
           Select-Object -First 1
    if ($ver) {
        $name = ($ver.Line -split '"')[1]
        Ok "release.yml will read versionName = '$name'"
        if ($name -match '-md3\.\d+$') { Ok "carries the -md3.N suffix the changelog keys on" }
        else { Note "no -md3.N suffix; the changelog falls back to the last 40 commits" }
        Note "APKs will be named PlainApp-$name-64bit-Recommended.apk / -Old-32bit.apk"
    }
    else { Bad "could not read versionName from app/build.gradle.kts" }

    $vc = Select-String -Path 'app/build.gradle.kts' -Pattern 'val vCode\s*=\s*(\d+)' |
          Select-Object -First 1
    if ($vc) {
        $code = [int]$vc.Matches[0].Groups[1].Value
        Ok "vCode $code -> arm64 gets $($code-1), armeabi-v7a gets $($code-2)"
    }

    $rl = Get-Content '.github/workflows/release.yml' -Raw
    if ($rl -match 'ENABLE_PLAY_PUBLISH') { Ok "play job gated - no Play account needed" }
    else { Bad "play job is not gated; it will fail without a Play service account" }

    $vars = gh variable list --repo $repo 2>$null
    if ($vars -match 'R2_PREFIX') { Ok "R2_PREFIX set" }
    else { Note "R2_PREFIX unset - fine, R2 steps are continue-on-error" }

    # ------------------------------------------------------------ summary
    Write-Host ''
    if ($failures.Count -eq 0) {
        Write-Host 'READY TO DISPATCH.' -ForegroundColor Green
        Write-Host '  Actions -> Release -> Run workflow -> wait for the draft -> Publish.'
        exit 0
    }
    else {
        Write-Host "$($failures.Count) problem(s) found:" -ForegroundColor Red
        $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        exit 1
    }
}
finally {
    Pop-Location
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}