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
