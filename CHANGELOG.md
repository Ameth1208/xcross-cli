# Changelog

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
