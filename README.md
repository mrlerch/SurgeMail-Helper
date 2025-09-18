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
```

Commands:  

&ensp;update | -u &emsp;&ensp;&emsp;&emsp;&emsp;Download and install a specified SurgeMail version   
&ensp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&ensp;Options:  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&ensp;&emsp;&ensp;&ensp;--version \<ver>&emsp;e.g. 80e (NOT the full artifact name)  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&emsp;&ensp;&ensp;--os \<target>&emsp;&emsp;windows64 | windows | linux64 | linux | solaris_i64 | freebsd64 | macosx_arm64 | macosx_intel64  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&ensp;&emsp;&ensp;&ensp;--api&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;non-interactive mode (requires --version)  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&emsp;&ensp;&ensp;--yes&emsp;&emsp;&emsp;&emsp;&emsp;&ensp; auto-answer prompts  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&ensp;&ensp;&ensp;--force&emsp;&emsp;&emsp;&emsp;&ensp;&ensp;kill ANY processes blocking required ports  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&emsp;&ensp;&ensp;--dry-run&emsp;&emsp;&emsp;&ensp;&ensp;simulate without changes  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&ensp;&emsp;&ensp;--verbose&emsp;&emsp;&emsp;&ensp; detailed debug output  

&ensp;check-update&emsp;&ensp;&emsp;&emsp;Detect installed version and compare with latest online  
&ensp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&ensp;Options:  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&ensp;&emsp;&ensp;&ensp;--os \<target>&emsp;&emsp;windows64 | windows | linux64 | linux | solaris_i64 | freebsd64 | macosx_arm64 | macosx_intel64  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&ensp;&emsp;&emsp;&ensp;&ensp;--auto&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;If newer exists, run 'update --api' automatically.  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp; Triggers the update --api with latest version.  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp; Use this when setting up your scheduled run with cron  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp; crontab -e  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp; (* * * * * is place holder. user your own schedule)  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp; * * * * * /usr/local/bin/surgemail check-update --auto            
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&ensp;&ensp;--verbose&emsp;&emsp;&emsp;&ensp; Show details
                      
&ensp;self_check_update&emsp; Checks for newer ServerMail Helper script version and prompt to update.   
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&ensp;&emsp;&ensp;Options:  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&ensp;&emsp;&ensp;&ensp;&emsp;--auto&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;Eliminates prompts in self_check_update.   
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp; Use this in your cron job.  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&ensp;&ensp;&emsp;--channel \<...>&emsp;&ensp;Options are:  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&ensp;&emsp;&emsp;release (e.g. --channel release)  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&ensp;&emsp;&emsp;prerelease  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&ensp;&ensp;&emsp;&emsp;dev  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&ensp;&ensp;&emsp;If not set it defaults to release.    
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&ensp;&emsp;&ensp;--quiet&emsp;&emsp;&emsp;&emsp;&emsp; suppress messages  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&ensp;&emsp;&ensp;--token&emsp;&emsp;&emsp;&emsp;&emsp;GitHub token
                      
&ensp;self_update&emsp;&ensp;&emsp;&emsp;&emsp;Update the ServerMail Helper script folder (git clone or ZIP).  
&ensp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&ensp;&emsp;&ensp;&ensp;&emsp;Options:  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&emsp;&ensp;&ensp;&emsp;--auto&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;Eliminates prompts in self_check_update.   
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&ensp;Use this in your cron job.  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&ensp;&emsp;&ensp;&ensp;&emsp;--channel \<...>&emsp;&ensp;Options are:  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&ensp;&emsp;release (e.g. --channel release)  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&ensp;&emsp;prerelease  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&ensp;&emsp;dev  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&ensp;If not set it defaults to release.   
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&ensp;&emsp;&ensp;--quiet&emsp;&emsp;&emsp;&emsp;&emsp; suppress messages  
&ensp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;&emsp;&ensp;&ensp;&emsp;&ensp;--token&emsp;&emsp;&emsp;&emsp;&emsp;GitHub token
                      
&ensp;stop&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;Stop SurgeMail AND free required ports (kills blockers)  
&ensp;start&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;Start the SurgeMail server (use --force to kill blockers)  
&ensp;restart&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;Stop then start the SurgeMail server (use --force to kill blockers)  
&ensp;reload | -r&emsp;&emsp;&emsp;&emsp;&emsp;&ensp; Reload SurgeMail configuration via 'tellmail reload'  
&ensp;status | -s&emsp;&emsp;&emsp;&emsp;&emsp;&ensp; Show current SurgeMail status via 'tellmail status'  
&ensp;version | -v&emsp;&emsp;&emsp;&emsp;&emsp; Show installed SurgeMail version via 'tellmail version'  
&ensp;where | -w&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;Show helper dir, surgemail server dir, tellmail path.  
&ensp;diagnostics | -d&emsp;&emsp;&emsp; Print environment/report.  
&ensp;debug-gh&emsp;&emsp;&emsp;&emsp;&emsp;&ensp; Print GitHub troubleshooting info
&ensp;--help | -h       Show this help  
&ensp;man&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp; Show man page (if installed), else help.  


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
