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
link root, configure its physical target folder. Robocopy excludes junctions
within copied trees. Backup source and session paths must not overlap.

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
