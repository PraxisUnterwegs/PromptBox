# Windows update verification

`packaging/updater/test_windows_native.ps1` runs in Windows PowerShell 5.1.
It compiles a real native EXE, starts the production Dart bootstrap, exits the
parent process, replaces the bundle and verifies that the new EXE actually ran.
It also checks SHA-256 rejection, cancellation, previous-bundle preservation,
Chinese characters, spaces, brackets, long asset paths and an invalid inherited
PowerShell module path. This test runs in Windows release CI.

The Flutter GUI fixture uses `windows_update_e2e_app.dart`, never `lib/main.dart`.
In a fresh test workspace:

1. Set an absolute `PROMPTBOX_DEMO_ROOT` pointing to
   `build/windows-update-e2e/profile` in that workspace.
2. Build Windows with `--target tool/windows_update_e2e_app.dart`, that
   `--dart-define`, `--build-name=0.1.0-preview.11 --build-number=11`.
   ZIP the entire release bundle as `profile/web/update.zip`.
3. Run `python tool/windows_update_e2e_fixture.py`. It seeds an isolated database,
   preferences and a text/image draft, then serves the local update feed.
   It refuses to overwrite an existing integration profile.
4. Build the same target/define with version `0.1.0-preview.10`, build number 10.
   Copy the entire bundle to `build/windows-update-e2e/PromptBox test [installed]`.
5. Launch that EXE on the interactive desktop. Open Settings, check updates,
   download and confirm, install and confirm. It should exit, replace the full
   bundle and reopen as preview.11 without further input.
6. Verify `launch-0.1.0-preview.11.json` has a different PID, the same database
   entries, theme and scales, and that the composer restored the text/image.
   Compare database SHA-256 hashes and preferences against `before.json`;
   compare `pending-update-draft.json.restored` with the seeded draft.

The HTTP fixture rewrites only release metadata and Windows ZIP requests to
loopback. It rejects other URLs and never modifies production preferences or
the production database. Fixture versions 10/11 do not refer to public releases.
