#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Reports how far this fork has drifted from plainhub/plain-app, then merges
    upstream/main and walks you through the conflicts it predicts.

.DESCRIPTION
    Runbook companion to UPSTREAM.md. Safe to run repeatedly: it never commits,
    never pushes, and leaves a conflicted merge in place for you to inspect.

.PARAMETER Merge
    Actually perform `git merge <target>`. Without it the script only
    reports, which is the default so you can look before you leap.

.PARAMETER Base
    Upstream ref to track, e.g. `v4.0.0`. This fork is based on upstream's
    newest release *tag*, not on `upstream/main`, so this is normally what
    you want. Omit it to fall back to `upstream/main`.

.PARAMETER NoFetch
    Skip `git fetch upstream` and use whatever refs are already local.

.EXAMPLE
    ./scripts/sync-upstream.ps1
    Look at the numbers, decide whether to merge.

.EXAMPLE
    ./scripts/sync-upstream.ps1 -Base v4.0.0 -Merge
    Move the base forward onto an upstream release tag.
#>

[CmdletBinding()]
param(
    [switch]$Merge,
    [switch]$NoFetch,
    [string]$Remote = 'upstream',
    [string]$Base,
    [string]$Branch = 'upstream/main'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

function Get-GitOutput {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $out = & git @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Args -join ' ') failed:`n$($out -join "`n")"
    }
    return ($out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
}

function Write-Head {
    param([string]$Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('-' * $Text.Length) -ForegroundColor Cyan
}

try {
    # ---------------------------------------------------------------- sanity
    if (-not (Get-GitOutput rev-parse --git-dir)) {
        throw "Not inside a git repository: $repoRoot"
    }

    # ------------------------------------------------- README merge driver
    # .gitattributes declares `README.md merge=ours`, but `ours` is not a
    # built-in git driver — the declaration is inert without this config line,
    # and every merge would conflict on README.md again. Lives in .git/config
    # so it cannot be committed; set it here, idempotently.
    $driver = (& git config --get merge.ours.driver 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($driver)) {
        Get-GitOutput config merge.ours.driver true | Out-Null
        Write-Host 'Configured merge.ours.driver=true (keeps the fork README on merge).' -ForegroundColor Green
    }
    else {
        Write-Host "merge.ours.driver = '$driver' (README kept on merge)"
    }

    $remotes = Get-GitOutput remote
    if ($remotes -notcontains $Remote) {
        throw "Remote '$Remote' not found. Add it with:`n  git remote add $Remote https://github.com/plainhub/plain-app.git"
    }

    $current = (Get-GitOutput rev-parse --abbrev-ref HEAD).Trim()
    if ($current -ne 'main') {
        Write-Warning "You are on '$current', not 'main'. The merge will land on this branch."
    }

    # ---------------------------------------------------------------- fetch
    if (-not $NoFetch) {
        Write-Head 'Fetching upstream'
        Get-GitOutput fetch $Remote --prune --tags | ForEach-Object { Write-Host "  $_" }
    }

    # ------------------------------------------------------------ resolve base
    # Default to upstream's newest release tag: this fork deliberately does not
    # track upstream/main, so comparing against main would report ~180 commits
    # of drift that are intentionally not taken.
    if ([string]::IsNullOrWhiteSpace($Base)) {
        $tags = Get-GitOutput tag --list |
        Where-Object { $_ -match '^v[0-9]+\.[0-9]+\.[0-9]+$' } |
        Sort-Object { [version]($_.TrimStart('v')) }
        if ($tags) {
            $Base = $tags[-1]
            Write-Host "Tracking newest upstream release tag: $Base" -ForegroundColor Green
        }
        else {
            Write-Warning "No upstream release tag found; falling back to '$Branch'."
            $Base = $Branch
        }
    }
    else {
        Get-GitOutput rev-parse --verify --quiet "$Base^{commit}" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Base ref '$Base' not found locally. Fetch tags first." }
    }

    $currentBranchRef = (Get-GitOutput rev-parse --abbrev-ref HEAD).Trim()
    # Commits upstream has that we lack, and the reverse. Easy to swap these,
    # so they are named rather than inlined.
    $missing = "$currentBranchRef..$Base"
    $ours = "$Base..$currentBranchRef"

    # ---------------------------------------------------------------- drift
    Write-Head 'Drift'
    $behind = [int](Get-GitOutput rev-list --count $missing)
    $ahead = [int](Get-GitOutput rev-list --count $ours)
    $mergeBase = (Get-GitOutput merge-base $currentBranchRef $Base).Trim()

    Write-Host "  Behind ${Base} : $behind commit(s)"
    Write-Host "  Ahead  of it    : $ahead commit(s)"
    Write-Host "  Merge base      : $($mergeBase.Substring(0, 9))"

    if ($behind -eq 0) {
        Write-Host ''
        Write-Host 'Already up to date with upstream.' -ForegroundColor Green
        return
    }

    # ------------------------------------------------- upstream commit preview
    Write-Head 'Newest upstream commits'
    Get-GitOutput log --no-merges --pretty=format:'  %h %s' -15 $missing |
        ForEach-Object { Write-Host $_ }

    # Upstream's own version bump matters: the fork derives its release version
    # from it.
    Write-Head "Upstream's current version"
    $ver = Get-GitOutput show "${Branch}:app/build.gradle.kts" |
        Select-String -Pattern '^\s*(val vCode\s*=|versionName\s*=)' |
        ForEach-Object { "  $($_.Line.Trim())" }
    if ($ver) { $ver | ForEach-Object { Write-Host $_ } }
    else { Write-Host '  (could not read app/build.gradle.kts)' -ForegroundColor Yellow }

    # ------------------------------------------------- fork divergence surface
    Write-Head 'Files this fork has changed'
    $changed = Get-GitOutput diff --name-only "$Base...$currentBranchRef"
    if ($changed) {
        $changed | ForEach-Object { Write-Host "  $_" }
        Write-Host ''
        Write-Host "  $($changed.Count) file(s)." -ForegroundColor Yellow
    }
    else {
        Write-Host '  (none)'
    }

    # ------------------------------------------------- predicted conflicts
    # A conflict is only likely where the fork's delta and upstream's incoming
    # changes overlap the same file.
    $incoming = Get-GitOutput diff --name-only "$mergeBase..$Base"
    $overlap = $changed | Where-Object { $incoming -contains $_ }

    Write-Head 'Predicted conflict hotspots'
    if ($overlap) {
        $overlap | ForEach-Object {
            $n = (Get-GitOutput log --oneline "$mergeBase..$Base" -- $_ | Measure-Object).Count
            Write-Host "  $_  ($n upstream commit(s) touch it)" -ForegroundColor Yellow
        }
        Write-Host ''
        Write-Host '  Files not listed here merge cleanly. README.md is excluded on'
        Write-Host '  purpose: the merge driver declared above keeps the fork copy.'
    }
    else {
        Write-Host '  None - the merge should be clean.'
    }

    if (-not $Merge) {
        Write-Head 'Re-run with -Merge to apply'
        Write-Host "  ./scripts/sync-upstream.ps1 -Merge`n"
        return
    }

    # ---------------------------------------------------------------- merge
    Write-Head 'Merging'
    & git merge --no-edit $Base
    $mergeExit = $LASTEXITCODE

    if ($mergeExit -ne 0) {
        Write-Host ''
        Write-Host 'Merge stopped with conflicts. Resolve them like this:' -ForegroundColor Yellow
        Get-GitOutput diff --name-only --diff-filter=U | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Yellow
        }
        Write-Host ''
        Write-Host 'Then verify the fork feature still builds, and finish the merge:'
        Write-Host '  ./gradlew :app:compileGithubDebugKotlin :shared:compileAndroidMain'
        Write-Host '  git add <resolved files>'
        Write-Host '  git commit'
        Write-Host '  git push origin main'
        Write-Host ''
        Write-Host 'The fork feature worth re-checking after every merge is the dynamic'
        Write-Host 'colour bridge: shared/src/**/platform/DynamicColor.* and ui/theme/Theme.kt.'
        return
    }

    if ($mergeExit -eq 0) {
        Write-Host ''
        Write-Host 'Merge was clean.' -ForegroundColor Green
        Write-Host 'Next: verify the build, then push.'
        Write-Host '  ./gradlew :app:compileGithubDebugKotlin :shared:compileAndroidMain'
        Write-Host '  git push origin main'
    }
}
finally {
    Pop-Location
}