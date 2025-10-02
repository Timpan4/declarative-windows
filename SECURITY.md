# Security Guidelines

## What NOT to Commit to Git

Configuration files can contain sensitive information. Be careful what you commit.

---

## Files That May Contain Secrets

### autounattend.xml

**The autounattend.xml in this repo is safe to commit** because:
- Password fields are LEFT BLANK - Windows prompts during installation
- Product key is set to SKIP
- No Wi-Fi credentials

**⚠️ Only commit if you DON'T hardcode:**
- Passwords
- Product keys
- Wi-Fi credentials

**Safe usage:**
- Leave `<Password>` fields empty
- Set `<SkipProductKey>true</SkipProductKey>`
- Windows will prompt during installation

### apps.json

May reveal:
- Work-specific software
- Licensed applications
- Personal preferences

**Solution:** Keep personal `apps.json` local (it's in `.gitignore`)

### config/ Files

May contain:
- API keys
- Personal paths
- Network configurations

**Solution:** Use placeholders like `<YOUR_API_KEY>` in committed versions

---

## Quick Reference

### ✅ Safe to Commit

- autounattend.xml (without secrets)
- Scripts (*.ps1)
- Documentation (*.md)
- Config templates with placeholders

### ❌ Never Commit

- autounattend.xml WITH real passwords/keys
- apps.json (personal)
- Files with `*-personal.*` in name
- Generated ISOs (*.iso)
- Log files (*.log)

---

## Before Sharing

```powershell
# Search for potential secrets
Select-String -Path *.xml,*.json -Pattern "password|key|secret" -CaseSensitive:$false
```

**Checklist:**
- [ ] autounattend.xml has no hardcoded passwords
- [ ] autounattend.xml has no product keys
- [ ] Not sharing personal apps.json
- [ ] Config files use placeholders

---

## Accidental Commit?

If you committed secrets:

1. **Remove from Git history:**
   ```bash
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch FILENAME" \
     --prune-empty --tag-name-filter cat -- --all
   ```

2. **Force push (if remote):**
   ```bash
   git push origin --force --all
   ```

3. **Rotate the secrets:**
   - Change passwords
   - Invalidate keys
   - Revoke tokens

---

## Golden Rule

**If you wouldn't want it on a public billboard, don't commit it.**

The `.gitignore` file protects most sensitive files automatically, but always double-check.
