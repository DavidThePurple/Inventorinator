# v0.1.1 release checklist

Build / commit: __________ · Tested by / date: __________

Import review and undo are implemented and covered by automated tests.

Check off against the build being released. Existing results count when they apply to that build.

## Ready to use

- [ ] Import review lets users inspect, correct, and accept or reject incoming items before saving.
- [ ] Undo import reverses the selected batch safely, including after restart and sync; later edits and unrelated records are protected.
- [ ] Linux, Windows, and Android packages install, launch, and keep existing data after upgrade.
- [ ] Add/edit an item, change quantity/location, search, and restart: changes remain correct.
- [ ] Drying timers, countdowns, and alerts still work.
- [ ] Kit/build stock, shopping lists, and kit-deletion reservation release behave correctly.
- [ ] CSV/XLSX/JSON item import/export and PDF reports work; unsupported kit/shopping-list JSON imports are clearly noted.
- [ ] Scratch Pad notes save and share correctly; only the Owner can manage every backed-up note. Verify Owner edits/deletes survive stale backups and reach the author.
- [ ] Two devices sync edits and offline changes without losing data; conflicts are reviewable and roles prevent unauthorized changes.
- [ ] Backup restores successfully into a separate test inventory.

## Ready to publish

- [ ] Automated checks pass for this commit; no unresolved release-blocking bugs.
- [ ] App version, release tag, filenames, and release notes agree.
- [ ] Downloaded packages install and launch; checksums, signing status, and contents are correct, with no credentials or personal data included.
- [ ] If this build adds migrations: test a fresh setup and an upgrade, include the complete matching server bundle, and publish linked, version-specific Wiki instructions. Keep older instructions available.
- [ ] Release notes list changes, known limitations, and the correct downloads.

**Decision:** Ready / Hold · Blockers: __________

DigiKey import and camera switching are already confirmed working. Remaining supplier checks and other planned features belong to [v0.1.2](roadmap.md).

[Detailed test reference](release-test-runbook.md)
