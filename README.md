# PlainApp MD3

An unofficial fork of [PlainApp](https://github.com/plainhub/plain-app) that only adds
**Material Design 3 / Material You dynamic color**.

Everything else is identical to upstream **v3.3.25**; the
[upstream README](https://github.com/plainhub/plain-app#readme) is the reference for everything
this fork does not touch. All credit belongs to the original author.

- **Base version:** upstream **v3.3.25**, its newest tagged release. The fork moves to a newer base
  only when upstream cuts a new tag — not when `main` changes. Maintenance details in
  [UPSTREAM.md](UPSTREAM.md).
- **One change only:** adds Material You (wallpaper-based dynamic color) on Android 12+, toggleable in
  *Settings → Dark theme*, falling back to the original colors when off.
- **What dynamic color covers:** the Compose UI and the splash screen. It does **not** recolor the
  launcher icon — Android provides no API for that, so the icon keeps upstream's own colors. On
  Android 13+ launchers that offer themed icons, the icon's monochrome layer is tinted by the
  launcher instead.
- **Version naming:** `<upstream-tag>-md3.<n>`, for example `3.3.25-md3.2`.
- **Installing:** this build is signed with a different key than upstream's releases while using the
  same application id, so **uninstall the upstream app first**. Installing over it fails with
  `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. Once installed, later fork releases upgrade normally.
- **Updates:** the in-app update check reads this fork's own releases, so it will not offer you an
  upstream APK — those cannot install over this build. It also will not announce later `-md3.N`
  releases automatically; check [releases](https://github.com/GitHubonline1396529/plain-app-md3/releases) instead.
- **iOS:** not provided. Android only.
- **License:** AGPL-3.0, same as upstream.

Fork repository: [GitHubonline1396529](https://github.com/GitHubonline1396529)/[plain-app-md3](https://github.com/GitHubonline1396529/plain-app-md3).