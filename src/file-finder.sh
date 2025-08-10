#!/usr/bin/env bash
# File Operations Toolkit v0.1
# Scans a target directory for common ops signals:
# - Largest files
# - Recent changes
# - World-writable files
# - SUID/SGID files
# - Duplicate basenames
# - Stale files
# - Top directories by size
# - Safe cleanup suggestions (dry-run)
set -euo pipefail

TARGET_DIR="${1:-/var/log}"   # default scan path

echo "=== File Ops Report ==="
echo "Scanning: $TARGET_DIR"

echo -e "\nLargest files (>50M):"
{ find "$TARGET_DIR" -type f -size +50M -printf "%p %k KB\n" 2>/dev/null || true; } \
  | sort -nr -k2,2 | head -10

echo -e "\nModified in last 24h:"
{ find "$TARGET_DIR" -type f -mtime -1 -printf "%TY-%Tm-%Td %TH:%TM %p\n" 2>/dev/null || true; } \
  | head -20

echo -e "\nWorld-writable files (potential risk):"
{ find "$TARGET_DIR" -type f -perm -o+w -printf "%p\n" 2>/dev/null || true; } \
  | head -20

echo -e "\nSUID/SGID files (security review):"
{ find "$TARGET_DIR" -type f \( -perm -4000 -o -perm -2000 \) -printf "%p\n" 2>/dev/null || true; } \
  | head -20

echo -e "\nDuplicate names (not content):"
{ find "$TARGET_DIR" -type f -printf "%f\n" 2>/dev/null || true; } \
  | sort | uniq -d | head -20

echo -e "\nStale files (>30 days not modified):"
{ find "$TARGET_DIR" -type f -mtime +30 -printf "%TY-%Tm-%Td %p\n" 2>/dev/null || true; } \
  | head -50

echo -e "\nTop directories by size (depth 1):"
{ du -x -h --max-depth=1 "$TARGET_DIR" 2>/dev/null || true; } \
  | sort -hr | head -10

echo -e "\nCleanup suggestions (dry-run):"
# Prints gzip commands for big, older logs; review before running.
{ find "$TARGET_DIR" -type f -name "*.log" -size +100M -mtime +7 -printf "gzip -9 \"%p\"\n" 2>/dev/null || true; } \
  | head -20

echo -e "\nTip: pass a path, e.g.  ./src/file-finder.sh /etc"
echo "=== End ==="

