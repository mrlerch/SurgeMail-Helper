# SurgeMail Helper — v1.14.12

## Install (symlink)
```bash
# from inside SurgeMail-Helper/
sudo ln -sf scripts/surgemail-helper.sh /usr/local/bin/surgemail
```
Ensure `/usr/local/bin` is in your `$PATH`.

## Short flags added
`-s` status, `-r` reload, `-u` update, `-d` diagnostics, `-v` version, `-w` where, `-h` help

Usage: surgemail <command> [options]

Commands:
  -u | update       Download and install a specified SurgeMail version
                    Options:
                      --version <ver>   e.g. 80e (NOT the full artifact name)
                      --os <target>     windows64 | windows | linux64 | linux |
                                        solaris_i64 | freebsd64 |
                                        macosx_arm64 | macosx_intel64
                      --api             requires --version, no prompts, auto-answers, --force
                      --yes             Auto-answer installer prompts with y
                      --force           Kill ANY processes blocking required ports at start
                      --dry-run         Simulate actions without changes
                      --verbose         Show detailed debug output
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
  self_update       Update the ServerMail Helper script folder (git clone or ZIP).
                    Options:
                      --auto            Eliminates prompts in self_check_update. 
                                        Use this in your cron job.
                      --channel         Options are:
                                        reelase
                                        prerelease
                                        dev
                                        If not set it defaults to release.
  stop              Stop SurgeMail AND free required ports (kills blockers)
  start             Start the SurgeMail server (use --force to kill blockers)
  restart           Stop then start the SurgeMail server (use --force to kill blockers)
  -r | reload       Reload SurgeMail configuration via 'tellmail reload'
  -s | status       Show current SurgeMail status via 'tellmail status'
  -v | version      Show installed SurgeMail version via 'tellmail version'
  -w | where        Show helper dir, surgemail server dir, tellmail path.
  -d | diagnostics  Print environment/report.
  -h | --help       Show this help
  man               Show man page (if installed), else help.
