# Frequently Asked Questions (FAQ)

## General Questions

### Q: What Windows versions are supported?

**A:** Windows 11 only (22H2 or later). Windows 10 is not supported.

### Q: Is this an open source project?

**A:** No, this is a personal project for managing Windows installations. It's designed for personal use and sharing with friends.

### Q: Can I run the setup multiple times safely?

**A:** Yes! The `bootstrap.ps1` script is designed to be **idempotent**, meaning you can run it multiple times without breaking anything. It checks if apps are already installed and skips them.

### Q: Do I need to be a programmer to use this?

**A:** No, but basic familiarity with PowerShell and JSON editing is helpful. The documentation provides step-by-step instructions.

---

## Setup & Installation

### Q: What if I don't have all the config files yet?

**A:** Start simple! You only need `apps.json` to begin. Other configs (Sophia Script, autounattend.xml, custom registry tweaks) are optional.

### Q: Can I use this without creating a custom ISO?

**A:** Yes! You can:

1. Install Windows normally
2. Clone this repo
3. Run `bootstrap.ps1` manually

The custom ISO is just for full automation.

### Q: How do I update my apps.json after initial setup?

**A:**

1. Export current apps: `winget export -o apps-new.json`
2. Manually compare with your existing `apps.json`
3. Add/remove packages as needed
4. Test with `winget import apps.json` (dry run)

---

## WinGet Questions

### Q: What if WinGet fails during installation?

**A:** Common solutions:

1. **Check network connection** - WinGet needs internet
2. **Update WinGet:** `winget upgrade --id Microsoft.AppInstaller`
3. **Re-run the script** - It's idempotent and will pick up where it left off
4. **Check the log:** Look at `C:\Setup\install.log` for errors

### Q: WinGet says "No package found matching input criteria"

**A:** The package ID might be wrong or the app might not be in WinGet:

- Search for it: `winget search <app-name>`
- Verify the ID: `winget show <package-id>`
- Check if it's in the winget repository: https://winget.run/

### Q: Can I install apps that aren't in WinGet?

**A:** Not with this project's current design. Alternatives:

- Add the app to WinGet community repository
- Install manually after automation completes
- Consider Chocolatey for missing apps (Phase 2 enhancement)

### Q: Some apps installed but others failed. What now?

**A:** Just re-run `bootstrap.ps1`:

- It will skip already-installed apps
- Retry failed installations
- Check the desktop summary log for status

---

## Sophia Script Questions

### Q: What if Sophia Script breaks something?

**A:**

1. **Create a system restore point** before running (recommended)
2. **Review Sophia.ps1** before customizing - understand what each tweak does
3. **Test in a VM first** before running on your main machine
4. **Rollback:** Use System Restore if something breaks

### Q: How do I know which Sophia Script options to enable?

**A:**

1. Download Sophia Script from GitHub
2. Open `Sophia.ps1` in a text editor
3. Read the comments - each option is documented
4. Start conservative - enable only tweaks you understand
5. Test in a VM before applying to your main machine

### Q: Can I skip Sophia Script and just use WinGet?

**A:** Yes! Sophia Script is optional. Comment it out in `bootstrap.ps1`:

```powershell
# .\Sophia.ps1  # Commented out - skip Sophia tweaks
```

---

## AutoUnattend.xml Questions

### Q: Where do I get an autounattend.xml file?

**A:** It's already in the repo! The project includes `autounattend.xml` that's ready to use. It has:
- Passwords LEFT BLANK (Windows prompts during install)
- Product key set to skip
- FirstLogonCommands configured to run bootstrap.ps1

Just review and customize if needed (username, timezone, etc.).

### Q: Can I use my own autounattend.xml?

**A:** Yes! You can:
1. Replace the included `autounattend.xml` with your own
2. Generate a new one at [Schneegans Unattend Generator](https://schneegans.de/windows/unattend-generator/)
3. Make sure to add `FirstLogonCommands` to run `C:\Setup\bootstrap.ps1` (see CLAUDE.md for template)

### Q: Why don't I need to add passwords to autounattend.xml?

**A:** The password fields are left blank, so Windows will prompt you to create a password during installation. This is safer than hardcoding passwords in the file.

### Q: The setup didn't run automatically after Windows install

**A:** Check:

1. Is `autounattend.xml` in the ISO/USB root?
2. Are files in the `$OEM$\$$\Setup\` folder structure?
3. Does `autounattend.xml` have `FirstLogonCommands` configured correctly?
4. Check `C:\Windows\Panther\setupact.log` for errors

---

## ISO Generation Questions

### Q: Do I need to create a custom ISO?

**A:** No, it's optional but convenient. You can:

- **With ISO:** Fully automated - boot and everything installs
- **Without ISO:** Manual - install Windows, then run bootstrap.ps1

### Q: How big will the custom ISO be?

**A:** Same size as the source Windows ISO (typically 4-6 GB). Your config files add negligible size.

### Q: Can I burn the ISO to a USB drive?

**A:** Yes! Use Rufus or Ventoy to create a bootable USB from the ISO.

---

## Idempotency & Re-running

### Q: What does "idempotent" mean?

**A:** It means you can run the script multiple times safely. It checks what's already done and skips it, instead of duplicating or breaking things.

### Q: When should I re-run bootstrap.ps1?

**A:**

- After a failed run (to retry failed steps)
- After updating your `apps.json` (to install new apps)
- After Windows updates (to reapply tweaks that might have been reset)
- Anytime you want to ensure your system matches your config

### Q: Will re-running install duplicate apps?

**A:** No! The script checks if each app is already installed before installing it.

---

## Troubleshooting

### Q: The desktop shortcut wasn't created

**A:** Manually create one:

1. Right-click desktop → New → Shortcut
2. Location: `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File C:\Setup\bootstrap.ps1`
3. Name it "Run Windows Setup"

### Q: Where are the log files?

**A:**

- **Detailed log:** `C:\Setup\install.log`
- **Desktop summary:** `C:\Users\[YourName]\Desktop\Setup Summary.txt`
- **Windows setup logs:** `C:\Windows\Panther\setupact.log`

### Q: Something broke - how do I rollback?

**A:**

1. **System Restore:** Use a restore point (if created before running)
2. **Manual rollback:** Check `install.log` to see what changed, reverse manually
3. **Fresh install:** Reinstall Windows (that's why we automate, right?)

### Q: Can I run this in Safe Mode?

**A:** Not recommended. WinGet and many tweaks require normal Windows operation.

---

## Customization

### Q: How do I customize this for my friend's setup?

**A:**

1. Fork/copy the repo
2. Update `apps.json` with their preferred apps
3. Customize `Sophia.ps1` preset
4. Share the repository with them
5. They run the same workflow

### Q: Can I have multiple app lists (work vs. personal)?

**A:** Yes! Create multiple JSON files:

- `apps-work.json`
- `apps-personal.json`
- `apps-gaming.json`

Then specify which one to import in `bootstrap.ps1`.

### Q: How do I add custom registry tweaks?

**A:** Create `config/registry.json` with your tweaks, then add a script to apply them in `bootstrap.ps1`. See TODO.md for planned schema.

---

## Network & Connectivity

### Q: Does this work without internet?

**A:** Partially:

- **WinGet:** Requires internet to download apps
- **Sophia Script:** Works offline (it's just registry/OS tweaks)
- **AutoUnattend.xml:** Works offline for Windows setup

**Recommendation:** Ensure network connection before running.

### Q: Can I pre-download WinGet packages?

**A:** Not directly supported yet. Planned for Phase 2 (caching).

---

## Security & Privacy

### Q: Is it safe to store my config in Git?

**A:** Yes, IF you follow security guidelines:

- Never commit `autounattend.xml` with passwords
- Never commit personal `apps.json` with sensitive apps
- Use `.gitignore` (provided)
- See SECURITY.md for detailed guidance

### Q: Can friends see my passwords if I share the repo?

**A:** Not if you follow SECURITY.md guidelines. Sanitize all files before sharing.

---

## Performance

### Q: How long does the full setup take?

**A:** Depends on:

- Number of apps in apps.json: ~2-5 minutes per app
- Network speed: Faster internet = faster downloads
- Sophia Script: ~2-5 minutes
- Total: Typically 30-60 minutes for full setup

### Q: Can I make it faster?

**A:** Planned for Phase 3:

- Parallel app installations
- Package caching
- Optimized Sophia Script execution

---

## Still Have Questions?

Check:

- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues
- [SECURITY.md](SECURITY.md) for security concerns
- [README.md](README.md) for getting started guide
- [CLAUDE.md](CLAUDE.md) for architectural details
