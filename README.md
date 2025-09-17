# SurgeMail Helper — v1.15.0

Cross-platform helper for managing and updating **SurgeMail** servers.  
Works on **Linux/Unix/macOS** (`surgemail-helper.sh`) and **Windows** (`surgemail-helper.ps1` + `.bat` wrappers).

---

## Installation

### Linux / Unix / macOS
1. **Clone from GitHub (preferred):**
```bash
sudo su
git clone https://github.com/mrlerch/SurgeMail-Helper.git
cd SurgeMail-Helper
chmod 775 scripts/surgemail-helper.sh
   ```

2. **Or download a .zip:**
```bash
sudo su
wget https://github.com/mrlerch/SurgeMail-Helper/archive/refs/heads/main.zip
unzip main.zip
mv SurgeMail-Helper-main SurgeMail-Helper
cd SurgeMail-Helper
chmod 775 scripts/surgemail-helper.sh
   ```

3. **Make global symlink (Linux / Unix / macOS):**
```bash
# to access the script globally create a sym link in /usr/local/bin
# from inside SurgeMail-Helper/
script="$PWD/scripts/surgemail-helper.sh"; sudo ln -sf "$script" /usr/local/bin/surgemail
```
Ensure `/usr/local/bin` is in your `$PATH`.

### Windows
1. Extract the release zip.
2. Run the installer:
   ```powershell
   .\installer\Install-WindowsHelper.ps1
   ```
   This places the helper script and wrappers in `C:\Surgemail\Helper\` (default) and registers the `surgemail` command.
3. Use either PowerShell (`surgemail-helper.ps1`) or CMD wrappers (`surgemail.bat`, `surgemail-helper.bat`).

---

## Usage

Short flags: `-s` status, `-r` reload, `-u` update, `-d` diagnostics, `-v` version, `-w` where, `-h` help

```
surgemail <command> [options]

Commands: 
```
  -u | update       Download and install a specified SurgeMail version  
                    Options:  
                      --version <ver>   e.g. 80e (NOT the full artifact name)  
                      --os <target>     windows64 | windows | linux64 | linux |  
                                        solaris_i64 | freebsd64 |  
                                        macosx_arm64 | macosx_intel64  
                  --api             non-interactive mode, requires --version
                  --yes             auto-answer prompts
                  --force           kill ANY processes blocking required ports
                  --dry-run         simulate without changes
                  --verbose         detailed debug output

  check-update      Detect installed version and compare with latest online  
                    Options:  
                      --os <target>     Artifact OS (auto-detected if omitted)  
                      --auto            If newer exists, run 'update --api' automatically.  
                                        Triggers the update --api with latest version.  
                                        Use this when setting up your scheduled run with cron  
                                        crontab -e  
                                        (* * * * * is place holder. user your own schedule)  
                                        * * * * * /usr/local/bin/surgemail check-update --auto            
                      --verbose         Show details
                      
  self_check_update Checks for newer ServerMail Helper script version and prompt to update.   
                    Options:  
                      --auto            Eliminates prompts in self_check_update.   
                                        Use this in your cron job.  
                      --channel         Options are:  
                                        reelase  
                                        prerelease  
                                        dev  
                                        If not set it defaults to release.    
                      --quiet   suppress messages
                      --token   GitHub token
                      
  self_update       Update the ServerMail Helper script folder (git clone or ZIP).  
                    Options:  
                      --auto            Eliminates prompts in self_check_update.   
                                        Use this in your cron job.  
                      --channel         Options are:  
                                        reelase  
                                        prerelease  
                                        dev  
                                        If not set it defaults to release.    
                      --quiet   suppress messages
                      --token   GitHub token
                      
  stop              Stop SurgeMail AND free required ports (kills blockers)  
  start             Start the SurgeMail server (use --force to kill blockers)  
  restart           Stop then start the SurgeMail server (use --force to kill blockers)  
  -r | reload       Reload SurgeMail configuration via 'tellmail reload'  
  -s | status       Show current SurgeMail status via 'tellmail status'  
  -v | version      Show installed SurgeMail version via 'tellmail version'  
  -w | where        Show helper dir, surgemail server dir, tellmail path.  
  -d | diagnostics  Print environment/report.  
  debug-gh          Print GitHub troubleshooting info
  -h | --help       Show this help  
  man               Show man page (if installed), else help.  

```


---

## Man Page (Linux/macOS)

The repository includes `docs/surgemail.1` (man page). To install:

**Linux (typical):**
```bash
sudo install -d /usr/local/share/man/man1
sudo gzip -c docs/surgemail.1 | sudo tee /usr/local/share/man/man1/surgemail.1.gz >/dev/null
sudo mandb || sudo /usr/sbin/makewhatis || true
```

**macOS (Intel):**
```bash
sudo install -d /usr/local/share/man/man1
sudo gzip -c docs/surgemail.1 | sudo tee /usr/local/share/man/man1/surgemail.1.gz >/dev/null
/usr/libexec/makewhatis /usr/local/share/man || true
```

**macOS (Apple Silicon / Homebrew):**
```bash
brew --prefix | xargs -I{} sh -c 'sudo install -d {}/share/man/man1; gzip -c docs/surgemail.1 | sudo tee {}/share/man/man1/surgemail.1.gz >/dev/null; /usr/libexec/makewhatis {}/share/man || true'
```

After installing, view with:
```bash
man surgemail
```

> **Windows:** man pages are not used natively. Use WSL or see README for commands.

---

## Notes
- **Windows `update`** downloads `.exe` artifacts and prints the path; silent install not attempted by default.
- For automated checks on Linux/macOS, use `cron` with `surgemail check-update --auto`.
- Both scripts target feature parity; some OS-specific behavior differs by design.

_Last updated: 2025-09-17_
