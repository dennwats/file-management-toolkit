# File Management Toolkit
![CI](https://github.com/dennwats/file-management-toolkit/actions/workflows/ci.yml/badge.svg)

**TL;DR:** One-command disk-usage triage and **safe cleanup**. Report largest files and stale items, then interactively **compress / truncate / trash** with **dry-run by default** and **undo**.

## Quick start
```bash
git clone https://github.com/dennwats/file-management-toolkit
cd file-management-toolkit
chmod +x src/*.sh

# Report (read-only)
bash src/file-finder.sh /var/log

# Interactive cleanup (DRY-RUN)
bash src/cleanup-interactive.sh /var/log

# Batch (non-interactive, for CI) — DRY-RUN
bash src/cleanup-interactive.sh /var/log --batch trash-stale --pick a

# Apply for real (example)
bash src/cleanup-interactive.sh /var/log --apply --batch trash-stale --pick a
```

## Features
- **Report:** largest files, recently modified, stale (>30d)
- **Interactive cleanup:** compress big logs, truncate huge logs, trash stale files
- **Batch mode for CI:** `--batch <action> --pick <list>`
- **Safety:** DRY-RUN by default, “undo last trash”

## CI
ShellCheck + a tiny smoke test (batch dry-run) on every push/PR.

