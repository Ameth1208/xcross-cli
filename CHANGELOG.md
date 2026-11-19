# Changelog

## 1.5.0 — Project detection and maintenance on Windows

- Detect Flutter, SwiftPM and Xcode roots while preserving saved project settings.
- Route `run` and `build` to SwiftPM for Windows packages; support product selection,
  debug/release configuration and executable arguments with `--args`.
- Explicitly reject native Xcode app builds on the Windows backend, including iKoda.
- Diagnose projects by type; add host-only `doctor --environment` and `verify` alias.
- Add guided `download all` and stable GitHub release IPA downloads with size,
  available SHA256 and main executable checks, without overwriting or installing.
- Pass validated engine update options (`--check`, `--force`, `--ref`), stop on failed
  checks and report the installed version after updating.
- Pin remote CLI downloads to one commit, validate all downloaded PowerShell scripts
  and restore prior files after copy failures. Validate local packages before copying.

## 1.4.0 — Check, sign only if unsigned, install

- Inspect the IPA's main Mach-O executable before transferring it to an iPhone; distinguish missing, ad-hoc and present signatures.
- Automatically sign unsigned IPA copies with the saved XCross identity and native provisioning engine. Preserve existing signatures, and never overwrite the original IPA.
- Cache the XCross 2.0.5 signing sources at a fixed commit and use Flutter's Dart when available; no manual P12 is needed for this flow.
- Add `xcm ipa inspect` and `xcm ipa logs`, actionable error summaries, and local diagnostic logs instead of raw tracebacks.
- Replace overflowing menu borders with paginated options and width-aware labels.
- Verified a real unsigned IPA was provisioned, signed and installed on an attached iPhone. Then verified direct installation of the signed output without re-signing. App launch/functionality was not tested.
- Add host-side parser and safe-extraction regression tests.

## 1.3.0 — Windows CLI

- Install an existing signed IPA over USB using `xcm install "app.ipa"`, `xcm install-ipa`, or menu option 7. Installation does not request a P12, provisioning profile or Apple ID. iOS still validates the package's existing signature.
- Build Flutter IPA files using `xcm ipa build`, with release, profile and debug modes.
- Optionally re-sign IPA files through zsign using a P12 and provisioning profile; protect existing output files and hide password arguments from CLI logging.
- Select a connected iPhone by UDID when multiple USB devices are present.
- Update the current Git project with `xcm project update` using `git pull --ff-only`, rejecting dirty working trees.
- Install local CLI changes with `xcm update-cli --local`.
- Preserve paths with spaces and handle native stderr correctly in Windows PowerShell 5.1.
- Update GitHub Pages, its interactive demo, English and Spanish documentation, and publicity templates.

The Linux helper retains its existing 1.2.0 command set. Real device signing and installation require validation with the user's IPA and credentials where applicable.
