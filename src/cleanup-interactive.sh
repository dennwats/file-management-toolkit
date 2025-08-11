#!/usr/bin/env bash
set -euo pipefail

# Require bash 4+ for 'mapfile -d'
if (( BASH_VERSINFO[0] < 4 )); then
  echo "This script requires Bash 4+." >&2
  exit 1
fi

TARGET_DIR="${1:-/var/log}"
DRY_RUN=1     # default: preview only
BATCH=""      # non-interactive mode: compress-big|truncate-huge|trash-stale|undo
PICKS=""      # numbers like "1 3" or "1,3" or "a" for all

# -------- arg parsing (after TARGET_DIR) --------
args=("${@:2}")
i=0
while (( i < ${#args[@]} )); do
  key="${args[$i]}"
  case "$key" in
    --apply) DRY_RUN=0; ((i++)) ;;
    --batch) BATCH="${args[$((i+1))]:-}"; ((i+=2)) ;;
    --batch=*) BATCH="${key#*=}"; ((i++)) ;;
    --pick) PICKS="${args[$((i+1))]:-}"; ((i+=2)) ;;
    --pick=*) PICKS="${key#*=}"; ((i++)) ;;
    *) echo "Unknown arg: $key" >&2; exit 2 ;;
  esac
done

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/filetool"
mkdir -p "$STATE_DIR"
UNDO_FILE="$STATE_DIR/last_trash_dir"

say() { printf '%s\n' "$*"; }

# Execute commands safely without eval; print exact command in DRY mode
doit() {
  if (( DRY_RUN )); then
    printf '[DRY]'
    for arg in "$@"; do printf ' %q' "$arg"; done
    printf '\n'
  else
    "$@"
  fi
}

list_big_files() {
  mapfile -d '' -t C < <(find "$TARGET_DIR" -type f -size +50M -print0 2>/dev/null)
}

list_huge_files() {
  mapfile -d '' -t C < <(find "$TARGET_DIR" -type f -size +200M -print0 2>/dev/null)
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

apply_picks() {
  SEL=()
  local picks="${1:-}"
  [[ -z "$picks" ]] && return 1
  # normalize commas -> spaces
  picks="${picks//,/ }"
  if [[ "$picks" == "a" ]]; then
    for i in "${!C[@]}"; do SEL+=("$i"); done
  else
    for n in $picks; do
      [[ "$n" =~ ^[0-9]+$ ]] || continue
      (( n>=1 && n<=${#C[@]} )) && SEL+=("$((n-1))")
    done
  fi
  ((${#SEL[@]})) || return 1
}

pick_indices() {
  read -rp "Pick numbers (e.g., 1 3 5), 'a' for all, or ENTER to cancel: " picks
  apply_picks "$picks"
}

compress_files() {
  for idx in "${SEL[@]}"; do
    f="${C[$idx]}"
    doit gzip -n --keep --force "$f"
  done
}

truncate_files() {
  for idx in "${SEL[@]}"; do
    f="${C[$idx]}"
    doit truncate -s 0 "$f"
  done
}

trash_files() {
  stamp="$(date +%Y%m%d_%H%M%S)"
  TRASH_DIR="$TARGET_DIR/.trash_$stamp"
  doit mkdir -p "$TRASH_DIR"
  for idx in "${SEL[@]}"; do
    f="${C[$idx]}"
    doit mv -v "$f" "$TRASH_DIR/"
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
  doit mkdir -p "$restore"
  # ignore error if empty
  doit bash -lc "shopt -s dotglob nullglob; mv -v \"$last\"/* \"$restore\"/ || true"
  if (( ! DRY_RUN )); then
    rm -f "$UNDO_FILE"
    say "Restored into: $restore"
  else
    say "[DRY] Would restore from $last -> $restore"
  fi
}

batch_run() {
  case "$BATCH" in
    compress-big)
      list_big_files || { say "No big files."; return 0; }
      [[ -n "$PICKS" ]] || PICKS="a"
      apply_picks "$PICKS" || { say "No picks."; return 0; }
      compress_files
      ;;
    truncate-huge)
      list_huge_files || { say "No huge files."; return 0; }
      [[ -n "$PICKS" ]] || PICKS="a"
      apply_picks "$PICKS" || { say "No picks."; return 0; }
      truncate_files
      ;;
    trash-stale)
      list_stale_files || { say "No stale files."; return 0; }
      [[ -n "$PICKS" ]] || PICKS="a"
      apply_picks "$PICKS" || { say "No picks."; return 0; }
      trash_files
      ;;
    undo)
      undo_trash
      ;;
    *) echo "Unknown batch action: $BATCH" >&2; return 2 ;;
  esac
  return 0
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
    # Use $ans so ShellCheck doesn't flag it as unused and to validate input
    if [[ -z "${ans:-}" ]]; then
      say "Invalid selection: $REPLY"
      continue
    else
      say "Selected: $ans"
    fi
    case "$REPLY" in
      1)
        list_big_files || continue
        show_candidates || continue
        pick_indices || { say "Canceled."; continue; }
        compress_files
        ;;
      2)
        list_huge_files || continue
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

if [[ -n "$BATCH" ]]; then
  batch_run
else
  main_menu
fi

