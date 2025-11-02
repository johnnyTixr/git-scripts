#!/bin/bash

# Git branch cleanup menu
# Presents options to run different branch cleanup scripts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define cleanup scripts with descriptions
SCRIPTS=(
  "cleanup-branches.sh:Delete Merged Branches:Removes branches that are merged to master (deletes from local AND remote)"
  "cleanup-synced-branches.sh:Delete Synced Branches:Removes local branches that are in sync with remote (preserves remote branch)"
  "cleanup-local-branches.sh:Delete Local Unpushed Branches:Removes local branches that haven't been pushed to remote. These could be useful branches so be careful!"
  "cleanup-unmerged-branches.sh:Delete Unmerged Branches:Removes branches that are NOT merged to master (deletes from local AND remote). These are usually stale branches but be cautious!"
)

# Parse script information
SCRIPT_NAMES=()
SCRIPT_TITLES=()
SCRIPT_DESCRIPTIONS=()

for script_info in "${SCRIPTS[@]}"; do
  IFS=':' read -r name title desc <<< "$script_info"
  SCRIPT_NAMES+=("$name")
  SCRIPT_TITLES+=("$title")
  SCRIPT_DESCRIPTIONS+=("$desc")
done

SELECTED=0

# Function to show menu
show_menu() {
  clear
  echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}Git Branch Cleanup Menu${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}\n"

  for i in "${!SCRIPT_NAMES[@]}"; do
    name="${SCRIPT_NAMES[$i]}"
    title="${SCRIPT_TITLES[$i]}"
    desc="${SCRIPT_DESCRIPTIONS[$i]}"

    if [ $i -eq $SELECTED ]; then
      echo -e "${GREEN}▶ ${title}${NC}"
      echo -e "${GRAY}  ${desc}${NC}\n"
    else
      echo -e "  ${title}"
      echo -e "${GRAY}  ${desc}${NC}\n"
    fi
  done

  echo -e "${YELLOW}Navigation: ↑/↓ arrows, Enter to select, Q to quit${NC}"
}

# Main loop
show_menu

while true; do
  # Read arrow keys and other input
  read -r -s -n 1 key

  case "$key" in
    $'\x1b')  # ESC sequence
      read -r -s -n 2 key  # Read [ and the arrow direction
      case "$key" in
        '[A')  # Up arrow
          if [ $SELECTED -gt 0 ]; then
            ((SELECTED--))
          fi
          show_menu
          ;;
        '[B')  # Down arrow
          if [ $SELECTED -lt $((${#SCRIPT_NAMES[@]} - 1)) ]; then
            ((SELECTED++))
          fi
          show_menu
          ;;
      esac
      ;;
    '')  # Enter key
      script="${SCRIPT_NAMES[$SELECTED]}"
      script_path="$SCRIPT_DIR/$script"

      if [ -f "$script_path" ] && [ -x "$script_path" ]; then
        clear
        "$script_path"
        show_menu
      else
        clear
        echo -e "${RED}Error: Could not find or execute script: $script_path${NC}"
        echo -e "${GRAY}Press any key to continue...${NC}"
        read -r -s -n 1
        show_menu
      fi
      ;;
    'q'|'Q')
      clear
      exit 0
      ;;
    *)
      # Ignore other keys
      ;;
  esac
done
