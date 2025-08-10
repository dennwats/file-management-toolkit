#!/usr/bin/env bash
set -euo pipefail

# Require bash 4+ for 'mapfile -d'
if (( BASH_VERSINFO[0] < 4 )); then
  echo "This script requires Bash 4+." >&2
  exit 1
fi

TARGET_DIR="${1:-/var/log}"
DRY_RUN=1  # default: preview only

# Parse flags
for a in "${@:2}"; do
  case "$a" in
    --apply) DRY_RUN=0 ;;
    *) echo "Unknown arg: $a" >&2; exit 2 ;;
  esac
done

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/filetool"
mkdir -p "$STATE_DIR"
UNDO_FILE="$STATE_DIR/last_trash_dir"

say() { printf '%s\n' "$*"; }
doit() {
  if (( DRY_RUN )); then
    say "[DRY] $*"
  else
    eval "$@"
  fi
}

list_big_files() {
  mapfile -d '' -t C < <(find "$TARGET_DIR" -type f -size +50M -print0 2>/dev/null)
}

list_stale_files() {
  mapfile -d '' -t C < <(find "$TARGET_DIR" -type f -mtime +30 -print0 2>/dev/null)
}

show_candidates() {
  ((${#C[@]})) || { say "No candidates."; return 1; }
  say "Candidates:"
  for i in "${!C[@]}"; do
    printf "%3d) %s\n" "$((i+1))" "${C[$i]}"
  done
}

pick_indices() {
  read -rp "Pick numbers (e.g., 1 3 5), 'a' for all, or ENTER to cancel: " picks
  SEL=()
  [[ -z "${picks:-}" ]] && return 1
  if [[ "$picks" == "a" ]]; then
    for i in "${!C[@]}"; do SEL+=("$i"); done
  else
    for n in $picks; do
      (( n>=1 && n<=${#C[@]} )) && SEL+=("$((n-1))")
    done
  fi
  ((${#SEL[@]})) || return 1
}

compress_files() {
  for idx in "${SEL[@]}"; do
    f="${C[$idx]}"
    # --keep keeps the original; remove --keep if you want only .gz
    doit "gzip -n --keep --force \"\$f\""
  done
}

truncate_files() {
  for idx in "${SEL[@]}"; do
    f="${C[$idx]}"
    # Safer than rm: log rotation style zeroing
    doit "truncate -s 0 \"\$f\""
  done
}

trash_files() {
  stamp="$(date +%Y%m%d_%H%M%S)"
  TRASH_DIR="$TARGET_DIR/.trash_$stamp"
  doit "mkdir -p \"\$TRASH_DIR\""
  for idx in "${SEL[@]}"; do
    f="${C[$idx]}"
    doit "mv -v \"\$f\" \"\$TRASH_DIR\"/"
  done
  if (( ! DRY_RUN )); then
    echo "$TRASH_DIR" > "$UNDO_FILE"
    say "Moved to $(cat "$UNDO_FILE")"
  else
    say "[DRY] Would set UNDO to $TRASH_DIR"
  fi
}

undo_trash() {
  [[ -f "$UNDO_FILE" ]] || { say "Nothing to undo."; return; }
  last="$(cat "$UNDO_FILE")"
  [[ -d "$last" ]] || { say "Undo dir missing."; return; }
  restore="$TARGET_DIR/restored_$(date +%Y%m%d_%H%M%S)"
  doit "mkdir -p \"\$restore\""
  doit "mv -v \"\$last\"/* \"\$restore\"/ 2>/dev/null || true"
  if (( ! DRY_RUN )); then
    rm -f "$UNDO_FILE"
    say "Restored into: $restore"
  else
    say "[DRY] Would restore from $last -> $restore"
  fi
}

main_menu() {
  PS3="Choose an option: "
  select ans in \
    "Compress big logs (>50M)" \
    "Truncate huge logs (>200M)" \
    "Trash stale files (>30d)" \
    "Undo last trash move" \
    "Quit"
  do
    case "$REPLY" in
      1)
        list_big_files || continue
        show_candidates || continue
        pick_indices || { say "Canceled."; continue; }
        compress_files
        ;;
      2)
        mapfile -d '' -t C < <(find "$TARGET_DIR" -type f -size +200M -print0 2>/dev/null)
        show_candidates || continue
        pick_indices || { say "Canceled."; continue; }
        truncate_files
        ;;
      3)
        list_stale_files || continue
        show_candidates || continue
        pick_indices || { say "Canceled."; continue; }
        trash_files
        ;;
      4) undo_trash ;;
      5) break ;;
      *) say "Invalid."; ;;
    esac
  done
}

say "Interactive cleanup on: $TARGET_DIR"
say "Mode: $([[ $DRY_RUN -eq 1 ]] && echo DRY-RUN || echo APPLY)"
main_menu

