RideClimb 3D / Climb3D - corrected package
Bundle ID: com.alessiosargentini.climb3d
Scheme: Climb3D
App Store Connect app name: RideClimb 3D

This package deliberately reuses the signing pattern that worked for RideClimb:
- Codemagic Developer Portal integration key name: CodeMagic
- ios_signing distribution_type: app_store
- no manual fetch-signing-files script and no appstore_credentials group
- xcode-project use-profiles
- AppIcon asset catalog included and referenced by the Xcode target

Replace the repository contents with the contents of this folder, commit, then let Codemagic re-read codemagic.yaml.
