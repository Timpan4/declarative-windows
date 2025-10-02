# Security Considerations

## ⚠️ Important: What NOT to Commit to Git

This project involves configuration files that can contain sensitive information. **Never commit these files with sensitive data:**

### Files That May Contain Secrets

#### 1. **autounattend.xml** ✅ Safe to Commit (if done correctly)

**The autounattend.xml in this repo is SAFE to commit** because:
- Password fields are LEFT BLANK - Windows prompts during installation
- Product key field is set to SKIP - Windows prompts if needed
- No Wi-Fi credentials stored
- No hardcoded secrets

**⚠️ WARNING:** Only commit autounattend.xml if you DON'T hardcode:
- Passwords
- Product keys
- Wi-Fi credentials

**How to use safely:**
- Leave `<Password>` fields empty or use `<PlainText>false</PlainText>` with no value
- Set product key to skip: `<SkipProductKey>true</SkipProductKey>`
- Windows will prompt for these during installation

#### 2. **apps.json** (Your Personal List)

May contain:

- Work-specific software
- Licensed applications with identifiable info
- Personal app preferences you don't want to share

**Solution:**

- Keep your personal `apps.json` local (it's in `.gitignore`)
- Create `apps-template.json` with generic apps for friends

#### 3. **Config Files**

Files in `config/` may contain:

- API keys in registry tweaks
- Personal paths or usernames
- Network configurations

**Solution:**

- Review all config files before sharing
- Use placeholders like `<YOUR_API_KEY>` for sensitive values

---

## Safe Practices

### ✅ Safe to Commit

- **`autounattend.xml`** (as long as passwords/keys are NOT hardcoded)
- Scripts (`bootstrap.ps1`, `build-iso.ps1`)
- Documentation files
- Config templates with placeholders

### ❌ Never Commit

- **`autounattend.xml` WITH real passwords/keys hardcoded** (if you add them)
- `apps.json` (your personal app list)
- Any file with `*-personal.*` in the name
- Generated ISOs (*.iso files)
- Log files (*.log files)

---

## Before Sharing with Friends

1. **Check for secrets:**

   ```powershell
   # Search for common secret patterns
   Select-String -Path *.xml,*.json -Pattern "password|key|secret" -CaseSensitive:$false
   ```

2. **Review autounattend.xml:**
   - Verify passwords are NOT hardcoded (should be blank)
   - Verify product keys are NOT hardcoded (should be set to skip)
   - Ensure no Wi-Fi credentials

3. **Review apps.json:**
   - Make sure it's not your personal apps.json
   - Should be a template or sanitized version

4. **Use .gitignore:**
   - The provided `.gitignore` protects personal files
   - Always double-check before `git push`

---

## Handling Passwords in autounattend.xml

### Recommended Approach: Leave Blank (Windows Prompts)

The autounattend.xml in this repo has passwords LEFT BLANK. Windows will prompt for:
- User account password during setup
- Product key (or skip activation)

**This is the safest approach** - no secrets in the file at all.

### Alternative: Hardcode Passwords (NOT RECOMMENDED)

If you need fully unattended install with no prompts:

1. **Add passwords to autounattend.xml** (local copy only)
2. **DO NOT commit this version to Git**
3. **Keep it in a secure location** (encrypted drive, password manager)

Example (DO NOT COMMIT):
```xml
<Password>
  <Value>YOUR_PASSWORD_HERE</Value>
  <PlainText>true</PlainText>
</Password>
```

**Remember:** If you add real passwords, you MUST NOT commit that file!

---

## Git Repository Recommendations

### For Personal Use

- Private Git repository (GitHub/GitLab private repo)
- Still use `.gitignore` as a safety net
- Never share repository publicly

### For Sharing with Friends

- Share sanitized templates only
- Provide setup instructions for adding their own secrets
- Consider using Git submodules for shared vs. personal configs

---

## Accidental Commit Recovery

If you accidentally committed sensitive data:

1. **Remove from Git history:**

   ```bash
   # Remove file from all commits
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch autounattend.xml" \
     --prune-empty --tag-name-filter cat -- --all
   ```

2. **Force push (if remote):**

   ```bash
   git push origin --force --all
   ```

3. **Rotate the exposed secrets:**
   - Change passwords
   - Invalidate product keys if needed
   - Revoke API tokens

---

## Summary

**Golden Rule:** If you wouldn't want it on a public billboard, don't commit it to Git.

Always review files before committing, use `.gitignore`, and keep sensitive data separate from shareable configuration.
