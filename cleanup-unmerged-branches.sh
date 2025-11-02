#!/bin/bash

# Cleanup unmerged branches with remote tracking
# Navigate with arrow keys, press Enter to select, Y to confirm deletion

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Get current user
CURRENT_USER="$(git config user.name)"
if [ -z "$CURRENT_USER" ]; then
  echo -e "${RED}Error: Could not determine git user name${NC}"
  exit 1
fi

# Get all branches with remote tracking that have NOT been merged to master, authored by current user
echo -e "${BLUE}Fetching unmerged branches with remote tracking authored by ${YELLOW}${CURRENT_USER}${BLUE}...${NC}"
BRANCHES=()
while IFS= read -r branch; do
  if [ -n "$branch" ]; then
    BRANCHES+=("$branch")
  fi
done < <(git for-each-ref --format='%(committerdate:iso8601) %(refname:short)' refs/heads | \
  while read date time tz branch; do
    # Skip if empty
    if [ -z "$branch" ]; then
      continue
    fi

    # Skip hotfix and release branches
    if [[ "$branch" == hotfix/* ]] || [[ "$branch" == release/* ]] || [[ "$branch" =~ ^(hotfix|release)- ]]; then
      continue
    fi

    # Check if this branch has a remote tracking branch
    if ! git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
      continue
    fi

    # Check if this branch IS merged to master
    if git merge-base --is-ancestor "$branch" master 2>/dev/null; then
      continue
    fi

    # Check if authored by current user
    author=$(git log -1 --format='%an' "$branch")
    if [ "$author" = "$CURRENT_USER" ]; then
      echo "$date $time $tz $branch"
    fi
  done | sort | cut -d' ' -f4-)

if [ ${#BRANCHES[@]} -eq 0 ]; then
  echo -e "${GREEN}No unmerged branches with remote tracking found that were authored by you.${NC}"
  exit 0
fi

echo -e "${GREEN}Found ${#BRANCHES[@]} branch(es)${NC}\n"

# Menu navigation
SELECTED=0
DELETED_COUNT=0
BRANCHES_DATES=()

# Populate branch dates for display
populate_branch_dates() {
  BRANCHES_DATES=()
  for branch in "${BRANCHES[@]}"; do
    date=$(git log -1 --format='%ai' "$branch" | cut -d' ' -f1)
    BRANCHES_DATES+=("$date")
  done
}

populate_branch_dates

# Function to show menu
show_menu() {
  clear
  echo -e "${BLUE}═══════════════════════════════════════${NC}"
  echo -e "${BLUE}Unmerged Branches Cleanup${NC}"
  echo -e "${BLUE}═══════════════════════════════════════${NC}"
  echo -e "${GRAY}User: ${CURRENT_USER}${NC}"
  echo -e "${GRAY}Deleted so far: ${DELETED_COUNT}${NC}\n"

  for i in "${!BRANCHES[@]}"; do
    branch="${BRANCHES[$i]}"
    date="${BRANCHES_DATES[$i]}"
    if [ $i -eq $SELECTED ]; then
      echo -e "${GREEN}▶ $branch${NC} ${GRAY}(${date})${NC}"
    else
      echo -e "  $branch ${GRAY}(${date})${NC}"
    fi
  done

  echo -e "\n${YELLOW}Navigation: ↑/↓ arrows, Enter to select, Q to quit${NC}"
}

# Function to get last commit message
get_commit_message() {
  local branch="$1"
  git log -1 --format='%B' "$branch"
}

# Function to get commit hash
get_commit_hash() {
  local branch="$1"
  git log -1 --format='%h' "$branch"
}

# Function to get commit author
get_commit_author() {
  local branch="$1"
  git log -1 --format='%an' "$branch"
}

# Function to get commit timestamp
get_commit_timestamp() {
  local branch="$1"
  git log -1 --format='%ai' "$branch"
}

# Function to confirm deletion
confirm_delete() {
  local branch="$1"

  local commit_hash=$(get_commit_hash "$branch")
  local commit_author=$(get_commit_author "$branch")
  local commit_timestamp=$(get_commit_timestamp "$branch")
  local commit_message=$(get_commit_message "$branch")

  clear
  echo -e "${BLUE}═══════════════════════════════════════${NC}"
  echo -e "${YELLOW}Delete Unmerged Branch: ${branch}${NC}"
  echo -e "${BLUE}═══════════════════════════════════════${NC}\n"

  echo -e "${GRAY}Branch Tip Commit:${NC}"
  echo -e "  ${commit_hash} - ${commit_author}"
  echo -e "  ${commit_timestamp}"
  echo -e "  Message: ${commit_message}\n"

  echo -e "${RED}⚠ WARNING: This branch has NOT been merged to master.${NC}"
  echo -e "${RED}This will delete the branch from both local and remote (origin).${NC}"
  echo -e "${YELLOW}Are you sure? (Y/n): ${NC}"

  # Read single character without requiring Enter
  read -r -s -n 1 response
  echo ""

  if [[ "$response" == "Y" || "$response" == "y" ]]; then
    return 0
  else
    return 1
  fi
}

# Function to delete branch
delete_branch() {
  local branch="$1"

  echo -e "\n${BLUE}Deleting ${branch}...${NC}"

  # Delete locally
  if git branch -D "$branch" 2>/dev/null; then
    echo -e "${GREEN}✓ Deleted locally${NC}"
  else
    echo -e "${RED}✗ Failed to delete locally${NC}"
    return 1
  fi

  # Delete remotely
  if git push origin --delete "$branch" 2>/dev/null; then
    echo -e "${GREEN}✓ Deleted from origin${NC}"
  else
    echo -e "${YELLOW}⚠ Could not delete from origin (may already be deleted)${NC}"
  fi

  ((DELETED_COUNT++))
  echo -e "${GREEN}Branch deleted successfully${NC}"
  sleep 1
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
          if [ $SELECTED -lt $((${#BRANCHES[@]} - 1)) ]; then
            ((SELECTED++))
          fi
          show_menu
          ;;
      esac
      ;;
    '')  # Enter key
      branch="${BRANCHES[$SELECTED]}"
      if confirm_delete "$branch"; then
        if delete_branch "$branch"; then
          # Remove from arrays
          BRANCHES=("${BRANCHES[@]:0:$SELECTED}" "${BRANCHES[@]:$((SELECTED + 1))}")
          BRANCHES_DATES=("${BRANCHES_DATES[@]:0:$SELECTED}" "${BRANCHES_DATES[@]:$((SELECTED + 1))}")
          if [ $SELECTED -ge ${#BRANCHES[@]} ] && [ $SELECTED -gt 0 ]; then
            ((SELECTED--))
          fi
        fi
      fi
      show_menu
      ;;
    'q'|'Q')
      clear
      echo -e "${GREEN}Cleanup complete!${NC}"
      echo -e "${GREEN}Deleted ${DELETED_COUNT} branch(es)${NC}"
      exit 0
      ;;
    *)
      # Ignore other keys
      ;;
  esac
done
