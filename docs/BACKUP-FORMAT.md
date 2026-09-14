# Backup and restore format

Backup configuration and manifests support version 1. Unversioned legacy inputs
use the version 1 shape and receive the same validation. Unknown versions,
incorrect field types, and missing required fields are rejected before copying.
Configuration requires `knownFolders` and `extraPaths` arrays. Optional flags
must be JSON booleans. Manifests require `machine`, `backup`, `repo`, `repoFiles`,
and `rules`; unsuccessful rules do not require a restorable source.

Backup source paths are relative to the selected manifest's directory. Legacy
absolute sources beneath the recorded `backup.backupRoot` are converted to
relative paths and resolved beneath the selected directory, even if the original
copy still exists. Repository destinations must remain beneath `repo.restorePath`.
Content destinations may be explicit absolute paths, including redirected folders.

All selected restore paths and source existence checks run before the first
restore write. Traversal, rooted repository-relative paths, alternate streams,
and reparse points in path ancestors are rejected. For a junction or symbolic
link root, configure its physical target folder. Backup copying excludes junctions;
restore rejects reparse points inside selected trees. Backup sources, restore
destinations, and recovered-file locations must not overlap the selected backup.

## Restore mappings

In backup configuration, `restoreTargets.repoPath` selects the repository restore
root. Other `restoreTargets` entries map an absolute source folder to an absolute
destination folder. Environment variables expand when the backup is made; the
manifest persists the normalized mappings separately from `repo.restorePath`.

Restore applies the longest matching source prefix first, matching both the exact
root and descendants without case sensitivity. A similar folder name is not a
match. Explicit mappings take precedence over automatic profile and OS-drive
remapping. Manifests without `restoreTargets` retain those automatic fallbacks.

## File verification

`preflight-backup.ps1 -VerifyHashes` compares SHA256 hashes of every copied
repository and content file against its source. A mismatch stops backup with an
error. Excluded files are not part of the backup. Generated WinGet inventory files
also receive hashes. The manifest and text report are metadata and do not hash
themselves.

The optional `verification` object records `algorithm: SHA256`, `status`, and a
`files` array of session-relative `path` and `sha256` pairs. Only `status: verified`
is accepted for restore. Restore checks all recorded hashes before writing,
rejects missing or changed files, and refuses to copy files without a hash record.
The option adds reads of every copied file and its source; it does not provide a
snapshot of files that applications are still changing.

Legacy manifests without this object remain restorable with an explicit warning
that complete verification is unavailable. Any existing repository `sha256`
values are validated before restore. Hashes detect corruption; the manifest is
not signed and is not an authentication mechanism.

## Restore conflicts and selections

`restore-backup.ps1` resolves a file plan, displays it, and executes those same
decisions. `-Preview` and `-WhatIf` return the plan without creating directories,
copying files, prompting, writing a report, or opening Explorer. The shared
`New-RestorePlan` function is the restore-policy input for the broader console
preview tracked in #83; that issue's setup preview remains separate work.

| Selection | Personal files | Project settings | Application state |
| --- | --- | --- | --- |
| Default, or `-Mode Merge` | Restore missing files, keep identical files, save differing backups separately | Keep current configuration; retain differing or missing backup settings separately | Skip until the app is explicitly selected |
| `-Mode SkipExisting` | Leave every existing file untouched without making a conflict copy | Skip existing files; retain missing backup settings separately | Still requires a separate app selection |
| `-Mode Overwrite` | Preview every replacement and require `YES` before applying it | Still requires `-UseBackupSettings` | Still requires `-RestoreApp` |
| `-UseBackupSettings` | Uses the selected personal-file mode | Preview and confirm applying backup configuration, including `apps.json`, optional apps, and Windows preferences | Does not select app state |
| `-RestoreApp <id>` | Uses the selected personal-file mode | Does not select project settings | Preview and confirm restoring all complete roots for that app, with its processes closed |

`-Force` is retained for command compatibility and does not alter these rules or
bypass confirmation. `-Confirm:$false` also cannot bypass the explicit `YES`.
Declining confirmation cancels the entire run before writes. `SkipExisting`
continues to skip existing project files even with `-UseBackupSettings`.
`-IncludeTags` filters ordinary content rules; repository settings remain visible
and separately selected. Explicit app selections include every related app rule,
independently of tags, so a database cannot be partly restored by tag filtering.

Project files inside the canonical repository are protected even when they were
incidentally included in a content rule. Bootstrap may clone the repository but
never copies backup configuration into it automatically. Applying backup settings
can change what a later setup run installs or configures; review their contents
before selecting them. In particular, `config\backup.json` contains old-machine paths.

Recovered copies are stored beneath
`<destination profile>\Recovered from backup\<SHA256 of selected manifest>`, with
the original drive or UNC share and folder structure preserved underneath. Moving
an unchanged backup does not change its grouping. An identical recovered copy is
reused on a rerun. An edited recovered copy is kept; the backup is saved to a
stable `.backup-<content SHA256>` alternate. If that alternate was also edited,
restore stops during planning rather than replacing either copy.

Results distinguish `restored`, `already-present`, `conflicting-copy-saved`,
`skipped`, and `failed`. The JSON report is written inside that recovery grouping,
outside the original backup. Results print an **Open recovered files** command;
`-OpenRecoveredFiles` opens the same folder in Explorer after execution.

Each personal or project file is copied to a temporary sibling and hash checked
against the planned backup content before publication. Existing destinations are
checked again against the preview. Replacement uses the filesystem's file-replace
operation; copy or hash failures leave the current file intact. Legacy backups
still warn that original backup-time verification is unavailable, even though
the new copy is checked against the selected backup bytes.

## Application-state metadata

An application-state `knownFolders` or `extraPaths` entry can declare:

```json
"application": {
  "id": "example-app",
  "processNames": ["ExampleApp", "ExampleHelper"]
}
```

Use exact Windows process names without `.exe`, paths, or wildcards. Include all
processes that write the state. Backup persists this object on each corresponding
manifest rule. Give related settings, session, and database roots the same app ID.
Application backup consistency requires closing the application during backup too.

Restore stages and verifies all selected roots before replacing any of them. It
checks processes during planning and again before applying state, and refuses an
incomplete app backup or changed destination. A failed application of one root
rolls back the roots already applied. Previous state is retained in uniquely named
`.restore-<id>-previous` sibling directories, recorded in `previousPaths` in the
results. Keep the app closed until restoration finishes. This is a coordinated
restore with rollback, not a transaction across disks or protection from power loss.

Unclassified files beneath the recorded or destination profile's `AppData`, and
rules tagged `app-state` without application metadata, are skipped with an
explanation. State stored elsewhere must be declared with application metadata;
file extensions alone cannot reliably identify application databases. Legacy
app-state backups need this classification before an explicit app restore. App
installation and sign-in are separate from restoring files and saved state.

Examples, using the selected backup and destination profile:

```powershell
.\restore-backup.ps1 -ManifestPath E:\backup\backup-manifest.json -DestinationProfileRoot C:\Users\NewUser -Preview
.\restore-backup.ps1 -ManifestPath E:\backup\backup-manifest.json -DestinationProfileRoot C:\Users\NewUser -OpenRecoveredFiles
.\restore-backup.ps1 -ManifestPath E:\backup\backup-manifest.json -DestinationProfileRoot C:\Users\NewUser -Mode Overwrite
.\restore-backup.ps1 -ManifestPath E:\backup\backup-manifest.json -DestinationProfileRoot C:\Users\NewUser -UseBackupSettings
.\restore-backup.ps1 -ManifestPath E:\backup\backup-manifest.json -DestinationProfileRoot C:\Users\NewUser -RestoreApp example-app
```
