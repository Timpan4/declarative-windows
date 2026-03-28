# FAQ

## What is this project?

Declarative Windows configuration management - like NixOS, but for Windows. The goal is to reinstall Windows every 2 months without manual reconfiguration.

## What's the current status?

Implementation phase. MVP scripts exist (`bootstrap.ps1`, `build-iso.ps1`). See [TODO.md](TODO.md) for remaining tasks.

## What will this do when it's finished?

One command generates a custom Windows ISO. Boot from it, choose the target disk yourself, and post-install setup continues automatically:
- Apps installed via WinGet
- OS tweaks applied via Sophia Script
- Automated Windows setup via autounattend.xml

Before reinstall, you can also run a declarative backup workflow that preserves common folders and extra configured paths.

## What Windows versions are supported?

Windows 11 only (24H2 or later). Windows 10 is not supported.

## Do I need to create a custom ISO?

No. You can also:
1. Install Windows normally
2. Run the bootstrap script manually

The custom ISO is just for full automation.

## How do I get my app list?

```powershell
winget export -o apps.json
```

Then edit the JSON to remove unwanted apps.

If you want some apps to stay optional after reinstall, create `optional-apps.json` with the same WinGet manifest format. Bootstrap prompts for it after first login and also creates `Install Optional Apps.lnk` for later use.

## Where does the repo live after reinstall?

The installer tries to clone the original repo remote into `%USERPROFILE%\Documents\declarative-windows`.

If cloning fails, setup continues from `C:\Setup` and you can retry later.

## What files should stay out of git?

Keep personal/system-specific files out of version control:

- `apps.json`
- `config\backup.json`
- backup manifests and reports
- machine-specific exports

Use the committed templates for shared defaults.

## Is it safe to commit my config to Git?

Only if you follow [SECURITY.md](SECURITY.md) guidelines:
- Never commit passwords or product keys in autounattend.xml
- Keep personal apps.json out of version control (it's in .gitignore)

## More Questions?

- [README.md](README.md) - Getting started
- [CLAUDE.md](CLAUDE.md) - Architecture details
- [SECURITY.md](SECURITY.md) - Security guidelines
