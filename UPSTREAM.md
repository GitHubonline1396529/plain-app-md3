# Upstream Maintenance Runbook

Operational notes for keeping this fork in sync with [`plainhub/plain-app`][upstream]
and cutting releases. Not user documentation — for what this fork *is*, see
[README.md](README.md).

[upstream]: https://github.com/plainhub/plain-app

## Remotes

| Remote | URL | Push? |
|---|---|---|
| `origin` | `git@github.com:GitHubonline1396529:plain-app-md3.git` | yes — this fork |
| `upstream` | `git@github.com:plainhub/plain-app.git` | no — never push here |

Both are configured. `upstream` is read-only by convention.

## Base policy: newest upstream *tag*

**This fork is based on upstream's newest release tag, not on `upstream/main`.**

Current base: **`v3.3.25`** (`fb7a65044`), the last version upstream actually
shipped. See [Why the tag, not main](#why-the-tag-not-main) for the reasoning.

Everything that tracks the base follows from this:

- `upstream-drift.yml` compares `main` against the newest upstream tag, not `main`
- `scripts/sync-upstream.ps1` resolves the newest tag automatically
- The base only moves when upstream cuts a **new tag**. A busy upstream `main`
  is not a trigger.

## Why the tag, not main

Upstream's `main` carries work that has never been in any release, and that work
is not reliably shippable. Concrete evidence: a build of upstream `main` at
`4.0.0` **crashes on launch for every user** — see
[Known upstream blocker](#known-upstream-blocker-launch-crash). Upstream has not
tagged a release since `v3.3.25` (2026-09-11).

Riding on unreleased `main` would mean shipping other people's unreleased work —
including a Rust HTTP core migration and a preferences migration — as this fork's
first public release, with no way to know what else is broken there.

So the rule is objective and cheap to check:

```bash
git tag --list | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
```

When that output changes to a newer tag, move the base forward.

## Moving the base forward

The fork's own delta is ~20 files, so moving the base is cheap: only the fork's
own commits are replayed, never upstream's.

```powershell
./scripts/sync-upstream.ps1 -Base v4.0.0        # report only
./scripts/sync-upstream.ps1 -Base v4.0.0 -Merge # do it
git push --force-with-lease origin main
```

Rebase, do not merge. Fork commits are pushed; merging would accumulate
increasingly stale merge commits for no benefit.

After the push, watch `Build Check` and `CodeQL` — they are the only automated
gates, and see [What CI does not cover](#what-ci-does-not-cover) before trusting
them.

## Scope of this fork

One feature: **Material You dynamic color** on Android 12+, toggleable in
*Settings → Dark theme*, falling back to the original palette when off.

Everything else is inherited from `v3.3.25`. The iOS target is left intact in
the build (deliberately — see [Why iOS stays](#why-ios-stays)) but is neither
built nor shipped; the fork publishes Android builds only.

## Known upstream blocker: launch crash

**Do not move the base past `v3.3.25` until this is fixed.** It affects every
`release` build of upstream `main`, not just this fork.

- **Symptom**: launch crash, 100% of installs, no config needed. Fully
  deterministic — repeated crashes differ only by PID.
- **Exception**: `java.lang.IllegalArgumentException: Drawable resource ID must
  not be 0`, on a `Dispatchers.Default` worker.
- **Path**: `MainActivity` → `lifecycleScope.launch(Dispatchers.Default)` →
  `publishLauncherShortcuts` → `LauncherShortcuts.android.kt:31` →
  `IconCompat.createWithResource(context, appResourceDrawable(resName))` →
  `Resources.getIdentifier` returns `0`.
- **Why 0**: the `shortcut_*` drawables are referenced only through a
  runtime-built string (`"shortcut_${type.name.lowercase()}"`). The release
  resource shrinker cannot see that and strips all 16 files. `keep.xml` — which
  exists precisely for this bug class, added in `v3.3.9` — does not list them.
  Debug builds set `isShrinkResources = false`, which is why they do not crash.
- **Fix**: add the 8 `shortcut_*` drawables to `app/src/main/res/raw/keep.xml`,
  and guard the icon lookup with a non-zero check the way the label lookup
  already is.

Status: **not patched in this fork, by design** — the bug does not exist at
`v3.3.25`, so there is nothing to patch here. It becomes a prerequisite the
moment the base moves forward. If upstream has not fixed it by then, either fix
it locally or stay on `v3.3.25`.

It was reported upstream. This is a regression of a bug they fixed in `v3.3.9`:
the launcher-shortcuts feature was added afterwards (`ae5bb92b2`,
2026-09-27) with the same unguarded pattern.

## What CI does not cover

Worth knowing before trusting a green build:

- `build-check.yml` runs `:app:compileGithubDebugKotlin` and
  `:app:assembleFdroidDebug`. Both are **debug** variants, so
  `isShrinkResources` and `isMinifyEnabled` are both `false`.
- `fdroid` flavour also swaps MediaPipe and LiteRT for `project(":litert-stubs")`,
  so the `github` flavour's real native libraries are never exercised.
- Consequence: `assembleGithubRelease` is built **only during an actual
  release**, and a green CI run says nothing about whether the release variant
  works at runtime. The launch crash above passed CI cleanly.

Adding `:app:assembleGithubRelease` to CI (with a throwaway keystore, the way
`build-check.yml` already generates a throwaway debug key) would catch R8
*build* failures. It would **not** have caught the launch crash, which builds
fine. Only installing the release APK reveals that class of bug.

## The README merge driver

`.gitattributes` declares `README.md merge=ours` so that upstream's constant
README rewriting never produces a conflict. **`ours` is not a built-in git
driver**, so that declaration does nothing until the driver is declared, and the
declaration lives in `.git/config` where it cannot be committed:

```bash
git config merge.ours.driver true
```

`./scripts/sync-upstream.ps1` sets this for you on every run and tells you when
it does. If you ever merge by hand without having run the script, README.md will
conflict like any other file.

## Fork-only files

The complete delta against upstream. Anything not on this list should come from
upstream verbatim. Keep it that way — every extra file is a future conflict.

| File | What the fork changes here |
|---|---|
| `.github/workflows/build-check.yml` | fork-only CI gate (upstream has none) |
| `.gitattributes` | forces `merge=ours` on `README.md` |
| `.github/workflows/upstream-drift.yml` | drift check against the newest upstream tag |
| `.github/workflows/release.yml` | concurrency lock, Play job gated, auto-changelog |
| `UPSTREAM.md` | this file |
| `scripts/sync-upstream.ps1` | base-move helper; resolves the newest upstream tag |
| `scripts/pre-release-check.ps1` | dry-run check of the signing path before a release |
| `README.md` | fork description; upstream's README is the source of truth |
| `.github/workflows/releases-to-discord.yml` | **deleted** — pointed at upstream's Discord |
| `.github/workflows/ios-testflight.yml` | **deleted** — needs an Apple Developer account |
| `scripts/build-ios-release.sh` | **deleted** — same |
| `shared/src/commonMain/.../platform/DynamicColor.kt` | `expect` bridge |
| `shared/src/androidMain/.../platform/DynamicColor.android.kt` | Android `actual` |
| `shared/src/iosMain/.../platform/DynamicColor.ios.kt` | iOS `actual` stub |
| `shared/src/commonMain/.../ui/theme/Theme.kt` | applies the dynamic scheme |
| `shared/src/androidMain/.../MainActivity.kt` | splash/first-frame colour |
| `shared/src/commonMain/.../ui/page/settings/DarkThemePage.kt` | the toggle |
| `shared/src/commonMain/.../preferences/Preferences.kt` | new pref |
| `shared/src/commonMain/.../preferences/LocalPreferences.kt` | new pref storage |
| `shared/src/commonMain/.../preferences/Settings.kt` | pref plumbing |
| `shared/src/commonMain/composeResources/values/strings_settings.xml` | toggle label |
| `app/src/main/res/values-v31/colors.xml` | dynamic colour resource overlay |
| `app/src/main/res/values-v31/themes.xml` | dynamic theme overlay |
| `app/src/main/res/values-night-v31/colors.xml` | dynamic colour resource overlay |
| `app/src/main/res/values-night-v31/themes.xml` | dynamic theme overlay |

`app/build.gradle.kts` is **byte-identical to upstream**. Version, signing and
flavours are all inherited — do not fork them without a reason.

### Conflict hotspots

Ranked by how often upstream touches each file (out of its last 400 commits),
cross-referenced with whether the fork edits it. This is the list to check first
when a rebase is messy.

The churn column was measured against **upstream `main`**, which is ahead of our
`v3.3.25` base — so treat it as an upper bound on the conflicts to expect.

The `v3.3.25 → 4.0.0` move was pre-verified: of the 11 existing files the MD3
patch modifies, 4 are new and 7 are byte-identical between the two revisions.
Expect **zero** conflicts. Re-verify with `sync-upstream.ps1 -Base <tag>` before
assuming that still holds.

| File | Upstream churn | Risk |
|---|---|---|
| `README.md` | 68 | neutralised by the merge driver (see above) |
| `preferences/Preferences.kt` | 27 | **high** — small diff, hot file |
| `composeResources/values/strings_settings.xml` | 17 | **high** — every string addition collides |
| `MainActivity.kt` | 16 | **high** |
| `ui/theme/Theme.kt` | 14 | **high** — largest fork diff in a hot file |
| `preferences/Settings.kt` | 4 | low |
| `values-v31*/colors.xml`, `values-v31*/themes.xml` | 0 | low |
| `platform/DynamicColor.ios.kt` | 0 | none — new file, only the fork has it |

## Syncing from upstream

`upstream-drift.yml` opens a rolling issue every Monday when a newer upstream
tag appears, so a missed base move gets noticed without anyone having to
remember to check.

```powershell
./scripts/sync-upstream.ps1                    # report: drift vs newest tag, predicted conflicts
./scripts/sync-upstream.ps1 -Base v4.0.0       # report against a specific tag
./scripts/sync-upstream.ps1 -Base v4.0.0 -Merge
```

The script never commits and never pushes. By hand the sequence is:

```bash
git fetch upstream --prune --tags
UP=$(git tag --list | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
git log --oneline "$UP"..main    # fork-only commits
git log --oneline main.."$UP"    # what we are missing; expect empty if current
git diff --stat "$UP"...main     # our divergence surface
git rebase "$UP"                 # replays only our commits
git push --force-with-lease origin main
```

**Rebase, do not merge** — see [Moving the base forward](#moving-the-base-forward).

### After every base move

CI runs on the push, so `Build Check` and `CodeQL` are the real gate. Watch
them before assuming the move is good.

Then **install the release APK**. That is the only step CI cannot do for you —
see [What CI does not cover](#what-ci-does-not-cover). Confirm the fork feature
by eye: the toggle in *Settings → Dark theme*, and the splash colour on
Android 12+.

When a conflict does land, these are the things that break silently:

- `Theme.kt` — dropping the dynamic scheme call compiles fine but the feature dies
- `DynamicColor.android.kt` / `.ios.kt` — `expect`/`actual` mismatch is a compile error, so this one is loud
- `strings_settings.xml` — a dropped string resource shows up as a raw key at runtime
- `Preferences.kt` — a dropped pref resets the user's toggle to default

### `maven/` needs care

Upstream publishes the `plain-common` Maven artifacts into `maven/` and pushes
them straight to `main` (see `.github/workflows/publish-plain-common.yml`).
This fork inherited that tree, so a release on both sides will collide on
`maven-metadata.xml`.

When it conflicts: take both sides, then re-run `publish-plain-common.yml` to
regenerate the metadata and checksums. Do not hand-edit files under `maven/`.

## Releasing

Version and signing live in `app/build.gradle.kts`, inherited from upstream and
hand-edited:

```kotlin
val vCode = 706          // 36
versionName = "4.0.0"    // 38
```

`versionCode` is derived: `vCode - singleAbiNum`. At the `v3.3.25` base
(`vCode = 700`) that is **699 for arm64-v8a** and **698 for armeabi-v7a**. Bump
`vCode` and `versionName` together, and always bump `vCode` — without it users
cannot upgrade in place.

> Do not add a comment containing the word `versionName` above line 38.
> `release.yml` greps the first match of `versionName` in that file to name the
> release, and a stray earlier match will silently mislabel the release.

### Version scheme

`<upstream-tag>-md3.<n>`, for example `3.3.25-md3.1`. It is valid semver, it
records which upstream release the build is based on, and it matches the
[base policy](#base-policy-newest-upstream-tag). The resulting tag is
`v3.3.25-md3.1`.

The workflow finds the previous fork release by looking for tags matching
`v*-md3.*`, so this scheme is what makes the auto-changelog work. Note the drift
detector's tag filter (`^v[0-9]+\.[0-9]+\.[0-9]+$`) deliberately excludes
`-md3.N` tags so fork releases never look like upstream ones.

### Procedure

0. **Do this first, every time:**
   ```powershell
   ./scripts/pre-release-check.ps1
   ```
   Verifies the keystore, the three secrets, the `keystore.properties` wiring and
   the Play gate — without building. Exits non-zero if anything is wrong, so a
   release run should never fail on setup.

1. Make sure the base is current (above). Never release on a stale base.
2. Set `versionName = <upstream-tag>-md3.<n>` and bump `vCode`.
3. Commit and push. `build-check.yml` and CodeQL run automatically.
4. Actions → **Release** → *Run workflow*.
   - `changelog_base` — leave empty to diff from the previous fork release.
     Set it to sync upstream's changelog attribution explicitly.
   - `skip_play` — only needed if `ENABLE_PLAY_PUBLISH` is on.
5. Wait for the draft. The changelog, SLSA section and VirusTotal placeholder
   are generated for you. Verify `body` is non-empty — a silent empty body was
   caused by a misspelled action input once already.
6. **Install the APK and confirm it launches** before publishing. See
   [What CI does not cover](#what-ci-does-not-cover); this step is not optional
   and not automatable.
7. Publish the draft. The VirusTotal job appends its table either before or
   shortly after; refresh the page.

### Building locally is not an option

`./gradlew` cannot run on this machine — the wrapper cannot download
`gradle-9.7.1-bin.zip` (network). **CI is the only build gate.** Do not plan a
workflow around a local compile; use a branch and let `Build Check` report.

### Repository configuration

Secrets — required:

| Secret | Notes |
|---|---|
| `ANDROID_STORE_PASSWORD` | goes into `keystore.properties` via `build-apk.sh` |
| `ANDROID_KEY_PASSWORD` | same value — the keystore is PKCS12, one password for both |
| `KEYSTORE_B64` | base64 of `app/release.jks`; expect 5776 characters |
| `VIRUSTOTAL_API_KEY` | optional; scan rows render as `⬜ N/A` without it |

First-time setup, and the traps in it:

```powershell
# 1. One-time. -alias release is mandatory: build-apk.sh hardcodes it.
keytool -genkeypair -v -keystore app/release.jks -alias release `
        -keyalg RSA -keysize 4096 -validity 36500 `
        -dname "CN=PlainApp MD3, O=GitHubonline1396529, C=CN"
```

- `-dname` skips the interactive DN prompts. Without it the final prompt shows
  `[否 ]` as the default, and answering 是 does nothing — a localisation bug in
  the JDK. If you get that prompt, press Ctrl+C and rerun with `-dname`.
- Modern JDKs default to PKCS12, where keytool asks for **one** password that
  serves as both store and key password. Hence two secrets, one value.
- **Back up `app/release.jks` outside the repo.** It is gitignored, and the
  GitHub copy is write-only. Lose it and no future build can ever update an
  already-installed app again.
- The certificate's DN is public — it ships inside every APK and any installed
  app can read it. Keep it free of private details.
- Encode for the secret:
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("app/release.jks")) | Set-Clipboard
  ```

Variables — all optional:

| Variable | Notes |
|---|---|
| `ENABLE_PLAY_PUBLISH` | must be `true` for the Play job to run at all. Left unset here: this fork ships via GitHub Releases only, and the job needs a Play service account. |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | Cloudflare R2 mirror; `continue-on-error` |
| `R2_ENDPOINT_URL`, `R2_BUCKET` | validated when present; `continue-on-error` |
| `R2_PREFIX` | **not validated.** If unset the APK lands at the bucket root. Set it. |

GitHub Actions permissions must allow `contents: write` (release creation, the
VirusTotal body edit) and `id-token: write` (SLSA provenance OIDC).

### Known fork caveats

- **`applicationId` is `com.ismartcoding.plain`, same as upstream, but signed
  with a different key.** Anyone who already has the upstream app installed must
  uninstall it first; an in-place upgrade fails with
  `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. This is intentional — keeping the id
  identical means zero build-script divergence from upstream.
- **APK filenames are not renamed.** `release.yml` hardcodes
  `PlainApp-<version>-64bit-Recommended.apk` in six places and `build-apk.sh` in
  two. Fork identity is carried by `versionName`, not the filename.
- **`releases-to-discord.yml` was removed.** It pointed at upstream's Discord
  server and upstream's icon. Recreate it against your own webhook if wanted.
- **Release is `workflow_dispatch` only, and creates a *draft*.** Nothing is
  public until a human publishes it.

## Why iOS stays

iOS is roughly 11k lines across `iosApp/` and the `iosMain` source sets — about
5% of the Kotlin and Swift. It is kept, not cut, because deleting it makes this
fork *harder* to maintain:

- The fork currently touches **none** of the four Gradle files that declare iOS
  targets (`shared`, `shared-lib`, `plain-common`, `room-db`). Upstream edits
  `shared/build.gradle.kts` about 43 times per 400 commits. Removing iOS means
  permanently diverging in exactly those files, and re-applying the deletion
  after every upstream KMP change. That is a permanent tax, not a one-off cost.
- Upstream keeps iOS alive — 109 of its last 400 commits touch
  `shared/src/iosMain` — so keeping it means those fixes arrive for free and
  `DynamicColor.ios.kt` stays aligned with the Android side.
- `plain-common` publishes iOS klibs and declares them in its Gradle module
  metadata. Dropping the targets breaks resolution for anyone consuming the
  artifact and leaves ~3 MB of permanently stale binaries under `maven/`.

iOS costs a few seconds of Gradle configuration and nothing else. The Android
build has no compile-time or dependency coupling to any of it.

What is disabled is only the iOS *release* path, since it can never run without
an Apple Developer account:

- `.github/workflows/ios-testflight.yml` — deleted
- `scripts/build-ios-release.sh` — deleted

The iOS source is intact, so the target can be re-enabled by restoring those two
paths from git history.

**Do not** convert the four KMP modules to plain `com.android.library`. That
would mean removing 389 `expect` and 386 `actual` declarations and relocating
~1,500 `commonMain` files, producing a fork that can never merge cleanly again.

## Adding a fork change

1. Keep it inside the delta table above. A new file outside it is a new
   permanent conflict.
2. If it touches `expect`/`actual`, add the iOS `actual` too — it costs nine
   lines and keeps the KMP build valid.
3. Bump `vCode` if it affects the shipped APK.
4. `./gradlew :app:compileGithubDebugKotlin :shared:compileAndroidMain` before pushing.