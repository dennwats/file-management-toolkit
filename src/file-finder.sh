#!/usr/bin/env bash
# File Operations Toolkit v0.1
set -euo pipefail

TARGET_DIR="${1:-/var/log}"     # default scan path
echo "=== File Ops Report ==="
echo "Scanning: $TARGET_DIR"

echo -e "\nLargest files (>50M):"
find "$TARGET_DIR" -type f -size +50M -printf "%p %k KB\n" 2>/dev/null | sort -nr -k2 | head -10

echo -e "\nModified in last 24h:"
find "$TARGET_DIR" -type f -mtime -1 -printf "%TY-%Tm-%Td %TH:%TM %p\n" 2>/dev/null | head -20

echo -e "\nWorld-writable files (potential risk):"
find "$TARGET_DIR" -type f -perm -o+w -printf "%p\n" 2>/dev/null | head -20

echo -e "\nSUID/SGID files (security review):"
find "$TARGET_DIR" -type f \( -perm -4000 -o -perm -2000 \) -printf "%p\n" 2>/dev/null | head -20

echo -e "\nDuplicate names (not content):"
find "$TARGET_DIR" -type f -printf "%f\n" 2>/dev/null | sort | uniq -d | head -20

echo -e "\nTip: pass a path, e.g.  ./src/file-finder.sh /etc"
echo "=== End ==="

