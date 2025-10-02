# FAQ

## What is this project?

Declarative Windows configuration management - like NixOS, but for Windows. The goal is to reinstall Windows every 2 months without manual reconfiguration.

## What's the current status?

Planning phase. No scripts exist yet. See [TODO.md](TODO.md) for implementation tasks.

## What will this do when it's finished?

One command generates a custom Windows ISO. Boot from it, and everything installs automatically:
- Apps installed via WinGet
- OS tweaks applied via Sophia Script
- Automated Windows setup via autounattend.xml

## What Windows versions are supported?

Windows 11 only (22H2 or later). Windows 10 is not supported.

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

## Is it safe to commit my config to Git?

Only if you follow [SECURITY.md](SECURITY.md) guidelines:
- Never commit passwords or product keys in autounattend.xml
- Keep personal apps.json out of version control (it's in .gitignore)

## More Questions?

- [README.md](README.md) - Getting started
- [CLAUDE.md](CLAUDE.md) - Architecture details
- [SECURITY.md](SECURITY.md) - Security guidelines
