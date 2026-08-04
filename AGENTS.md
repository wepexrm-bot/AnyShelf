# Project Conventions

## Mobile versioning

Every time the mobile app code (`mobile/`) changes, increment both:
- the version number in `mobile/pubspec.yaml` (e.g. `4.0.1`, then `4.1.0` for features)
- the build number after `+` (versionCode) — always bump it, e.g. `4.0.1+2`

This keeps the published APK in sync with the installed build for forced-update checks.
