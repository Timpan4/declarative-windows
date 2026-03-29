# AutoUnattend.xml Explained

This file is now intentionally ultra-minimal. It avoids changing Windows Setup itself and only kicks off post-install automation after first login.

## How It Works

The file runs in three phases during Windows installation:

### 1. oobeSystem (First Boot)

Runs when Windows boots for the first time.

- Leaves the Windows installer completely manual until OOBE is finished
- Uses only a few standard OOBE settings (`ProtectYourPC`, `HideEULAPage`, wireless setup visibility)
- Waits for network connectivity
- Starts `bootstrap.ps1`

**You'll still see:**
- Region/language selection
- Keyboard layout
- User account creation (you choose username/password)
- Network setup

## What Happens on First Login

1. Complete the normal Windows setup flow yourself
2. Sign in for the first time
3. The system waits for network connectivity
4. **bootstrap.ps1 runs automatically** via FirstLogonCommands

Everything else now happens in `bootstrap.ps1`: app installs, debloat, Sophia, restore shortcuts, and post-install tweaks.

**If bootstrap fails or you want to re-run it:** Just run `C:\Setup\bootstrap.ps1` manually.

## Customization

This file should stay minimal. If Windows Setup errors return, prefer moving more logic into `bootstrap.ps1` rather than adding it back here.

## Logs

If something goes wrong, check these logs:

- `C:\Windows\Panther\setupact.log` - Windows setup log

## Security Note

Passwords and product keys are left blank. Windows will prompt you to set them during installation. Safe to commit to Git as-is.
