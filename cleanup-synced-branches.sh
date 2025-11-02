#!/bin/bash

# Cleanup local branches that are in sync with their remote tracking branch
# Navigate with arrow keys, press Enter to select, Y to confirm deletion
# NOTE: Only deletes the local branch, remote branch is preserved

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

# Get all local branches that are in sync with their remote, excluding hotfix and release
echo -e "${BLUE}Fetching local branches in sync with remote...${NC}"
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

    # Skip protected main branches
    if [[ "$branch" == "master" ]] || [[ "$branch" == "staging" ]] || [[ "$branch" == "test" ]] || [[ "$branch" == "develop" ]]; then
      continue
    fi

    # Check if this branch has a remote tracking branch
    if ! git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
      continue
    fi

    # Check if local and remote are in sync (same commit hash)
    local_hash=$(git rev-parse "$branch" 2>/dev/null)
    remote_hash=$(git rev-parse "origin/$branch" 2>/dev/null)

    if [ "$local_hash" != "$remote_hash" ]; then
      continue
    fi

    echo "$date $time $tz $branch"
  done | sort | cut -d' ' -f4-)

if [ ${#BRANCHES[@]} -eq 0 ]; then
  echo -e "${GREEN}No synced branches found.${NC}"
  exit 0
fi

echo -e "${GREEN}Found ${#BRANCHES[@]} branch(es)${NC}\n"

# Menu navigation
SELECTED=0
DELETED_COUNT=0
BRANCHES_DATES=()
BRANCHES_AUTHORS=()
FILTER_NOT_AUTHOR=0

# Function to filter branches where current user is not an author
apply_filter() {
  local filtered_branches=()
  local filtered_dates=()
  local filtered_authors=()

  for i in "${!BRANCHES[@]}"; do
    local branch="${BRANCHES[$i]}"
    local authors="${BRANCHES_AUTHORS[$i]}"

    # Check if current user is in the authors list
    if [[ ! "$authors" =~ $CURRENT_USER ]]; then
      filtered_branches+=("$branch")
      filtered_dates+=("${BRANCHES_DATES[$i]}")
      filtered_authors+=("$authors")
    fi
  done

  BRANCHES=("${filtered_branches[@]}")
  BRANCHES_DATES=("${filtered_dates[@]}")
  BRANCHES_AUTHORS=("${filtered_authors[@]}")
  SELECTED=0
}

# Populate branch dates and authors for display
populate_branch_dates() {
  BRANCHES_DATES=()
  BRANCHES_AUTHORS=()
  for branch in "${BRANCHES[@]}"; do
    date=$(git log -1 --format='%ai' "$branch" | cut -d' ' -f1)
    BRANCHES_DATES+=("$date")

    # Get unique authors from the last 3 commits on this branch
    authors=$(git log -3 "$branch" --format='%an' 2>/dev/null | sort -u | paste -sd ',' -)
    BRANCHES_AUTHORS+=("$authors")
  done
}

populate_branch_dates

# Ask if user wants to filter branches
echo -e "${YELLOW}Show only branches where you are NOT an author? (y/N): ${NC}"
read -r -s -n 1 filter_response
echo ""

if [[ "$filter_response" == "Y" || "$filter_response" == "y" ]]; then
  FILTER_NOT_AUTHOR=1
  apply_filter

  if [ ${#BRANCHES[@]} -eq 0 ]; then
    echo -e "${GREEN}No branches found where you are not an author.${NC}"
    exit 0
  fi

  echo -e "${GREEN}Filtered to ${#BRANCHES[@]} branch(es) where you are not an author${NC}\n"
fi

# Function to show menu
show_menu() {
  clear
  echo -e "${BLUE}═══════════════════════════════════════${NC}"
  echo -e "${BLUE}Synced Branches Cleanup${NC}"
  echo -e "${BLUE}═══════════════════════════════════════${NC}"
  echo -e "${GRAY}Deleted so far: ${DELETED_COUNT}${NC}\n"

  for i in "${!BRANCHES[@]}"; do
    branch="${BRANCHES[$i]}"
    date="${BRANCHES_DATES[$i]}"
    authors="${BRANCHES_AUTHORS[$i]}"
    if [ $i -eq $SELECTED ]; then
      echo -e "${GREEN}▶ $branch${NC} ${GRAY}(${date}) [${authors}]${NC}"
    else
      echo -e "  $branch ${GRAY}(${date}) [${authors}]${NC}"
    fi
  done

  echo -e "\n${YELLOW}Navigation: ↑/↓ arrows, Enter to select"
  echo -e "A - Delete all, Q - quit${NC}"
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

  # Verify branch is still synced with remote
  local_hash=$(git rev-parse "$branch" 2>/dev/null)
  remote_hash=$(git rev-parse "origin/$branch" 2>/dev/null)

  if [ "$local_hash" != "$remote_hash" ]; then
    clear
    echo -e "${RED}═══════════════════════════════════════${NC}"
    echo -e "${RED}ERROR: Branch is no longer in sync${NC}"
    echo -e "${RED}═══════════════════════════════════════${NC}\n"
    echo -e "${YELLOW}The branch ${branch} is no longer in sync with origin/${branch}.${NC}"
    echo -e "${YELLOW}It may have been modified locally or remotely.${NC}\n"
    echo -e "${GRAY}Press any key to continue...${NC}"
    read -r -s -n 1
    return 1
  fi

  local commit_hash=$(get_commit_hash "$branch")
  local commit_author=$(get_commit_author "$branch")
  local commit_timestamp=$(get_commit_timestamp "$branch")
  local commit_message=$(get_commit_message "$branch")

  clear
  echo -e "${BLUE}═══════════════════════════════════════${NC}"
  echo -e "${YELLOW}Delete Local Branch: ${branch}${NC}"
  echo -e "${BLUE}═══════════════════════════════════════${NC}\n"

  echo -e "${GRAY}Branch Tip Commit:${NC}"
  echo -e "  ${commit_hash} - ${commit_author}"
  echo -e "  ${commit_timestamp}"
  echo -e "  Message: ${commit_message}\n"

  echo -e "${GREEN}✓ Remote branch (origin/${branch}) is synced and will be preserved.${NC}"
  echo -e "${YELLOW}This will DELETE ONLY the local branch.${NC}"
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

  echo -e "\n${BLUE}Deleting local branch: ${branch}...${NC}"

  # Delete locally only
  if git branch -d "$branch" 2>/dev/null; then
    echo -e "${GREEN}✓ Deleted local branch${NC}"
  elif git branch -D "$branch" 2>/dev/null; then
    echo -e "${GREEN}✓ Deleted local branch (forced)${NC}"
  else
    echo -e "${RED}✗ Failed to delete local branch${NC}"
    return 1
  fi

  echo -e "${GREEN}✓ Remote branch (origin/${branch}) left untouched${NC}"
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
          BRANCHES_AUTHORS=("${BRANCHES_AUTHORS[@]:0:$SELECTED}" "${BRANCHES_AUTHORS[@]:$((SELECTED + 1))}")
          if [ $SELECTED -ge ${#BRANCHES[@]} ] && [ $SELECTED -gt 0 ]; then
            ((SELECTED--))
          fi
        fi
      fi
      show_menu
      ;;
    'a'|'A')
      # Delete all branches
      if [ ${#BRANCHES[@]} -eq 0 ]; then
        show_menu
        continue
      fi

      clear
      echo -e "${BLUE}═══════════════════════════════════════${NC}"
      echo -e "${RED}Delete ALL Branches?${NC}"
      echo -e "${BLUE}═══════════════════════════════════════${NC}\n"
      echo -e "${YELLOW}This will delete ${#BRANCHES[@]} local branch(es):${NC}\n"

      for branch in "${BRANCHES[@]}"; do
        echo -e "  ${GRAY}• $branch${NC}"
      done

      echo -e "\n${YELLOW}Remote branches will be preserved.${NC}"
      echo -e "${RED}Are you absolutely sure? (Y/n): ${NC}"

      read -r -s -n 1 response
      echo ""

      if [[ "$response" == "Y" || "$response" == "y" ]]; then
        for branch in "${BRANCHES[@]}"; do
          if delete_branch "$branch"; then
            :
          fi
        done

        # Clear all arrays after deleting all
        BRANCHES=()
        BRANCHES_DATES=()
        BRANCHES_AUTHORS=()
        SELECTED=0

        clear
        echo -e "${GREEN}All branches deleted!${NC}"
        echo -e "${GREEN}Deleted ${DELETED_COUNT} local branch(es) total${NC}"
        echo -e "${GREEN}Remote branches were preserved.${NC}"
        exit 0
      fi
      show_menu
      ;;
    'q'|'Q')
      clear
      echo -e "${GREEN}Cleanup complete!${NC}"
      echo -e "${GREEN}Deleted ${DELETED_COUNT} local branch(es)${NC}"
      echo -e "${GREEN}Remote branches were preserved.${NC}"
      exit 0
      ;;
    *)
      # Ignore other keys
      ;;
  esac
done
