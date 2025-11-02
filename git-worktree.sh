#!/bin/bash

# Git worktree management menu - v3
# Complete rewrite with unified keyboard navigation and consolidated logic
# Fixes: Case statement syntax, ESC handling, duplicated code

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
UNDERLINE='\033[4m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"

# Define worktree operations with descriptions
OPERATIONS=(
	"add:Add New Worktree:Create a new worktree for a branch or commit:a"
	"list:List Worktrees:Show all existing worktrees and their branches:l"
	"remove:Remove Worktree:Delete an existing worktree:r"
	"prune:Prune Worktrees:Clean up worktree administrative files:p"
	"lock:Lock Worktree:Prevent a worktree from being pruned:k"
	"unlock:Unlock Worktree:Allow a locked worktree to be pruned:u"
	"move:Move Worktree:Move a worktree to a new location:m"
	"repair:Repair Worktrees:Fix worktree administrative files:e"
)

# Parse operation information
OPERATION_NAMES=()
OPERATION_TITLES=()
OPERATION_DESCRIPTIONS=()
OPERATION_SHORTCUTS=()

for operation_info in "${OPERATIONS[@]}"; do
	IFS=':' read -r name title desc shortcut <<< "$operation_info"
	OPERATION_NAMES+=("$name")
	OPERATION_TITLES+=("$title")
	OPERATION_DESCRIPTIONS+=("$desc")
	OPERATION_SHORTCUTS+=("$shortcut")
done

SELECTED=0

# ============================================================================
# CORE INPUT HANDLING - Single source of truth for keyboard input
# ============================================================================

# Read a single keypress and normalize to readable strings
# Returns: "UP", "DOWN", "RIGHT", "LEFT", "ESC", "ENTER", or the actual character
# This is the ONLY function that should use raw read commands
read_key() {
	local key escape_seq

	# Read one character
	IFS= read -r -s -n 1 key

	# Check if it's escape sequence
	if [[ "$key" == $'\x1b' ]]; then
		# Read the rest of the escape sequence
		# Arrow keys send ESC [ A/B/C/D
		IFS= read -r -s -n 1 -t 1 escape_seq 2>/dev/null
		if [[ "$escape_seq" == "[" ]]; then
			IFS= read -r -s -n 1 -t 1 escape_seq 2>/dev/null
			case "$escape_seq" in
				A) echo "UP" ;;
				B) echo "DOWN" ;;
				C) echo "RIGHT" ;;
				D) echo "LEFT" ;;
				*) echo "ESC" ;;
			esac
		else
			echo "ESC"
		fi
	elif [ -z "$key" ]; then
		echo "ENTER"
	else
		echo "$key"
	fi
}

# Prompt helper that detects ESC and can require non-empty input
# Usage: ask "Prompt: " varname [required]
# Returns: 0 on success, 1 if empty when required, 2 on ESC
ask() {
	local prompt="$1"
	local __var="$2"
	local required="$3"
	local ch rest answer

	# Print prompt without newline
	printf "%s" "$prompt"

	# Disable echo temporarily to read the very first character
	stty -echo 2>/dev/null || true
	IFS= read -r -n 1 ch || ch=""
	stty echo 2>/dev/null || true

	# If ESC, consume any trailing escape bytes and return 2
	if [[ "$ch" == $'\x1b' ]]; then
		# Consume quickly any remaining bytes in stdin that are part of escape
		while IFS= read -r -n 1 -t 0.01 rest 2>/dev/null; do
			:
		done
		printf "\n\n"
		return 2
	fi

	# If first char was newline (user pressed Enter immediately)
	if [ -z "$ch" ]; then
		answer=""
		printf "\n"
	else
		# Echo the first character (it was read with echo off)
		printf "%s" "$ch"
		# Read rest of the line until newline
		IFS= read -r rest || rest=""
		answer="$ch$rest"
		printf "\n"
	fi

	# If required and empty
	if [ "$required" = "true" ] && [ -z "$answer" ]; then
		printf "\n"
		return 1
	fi

	# Echo a newline for aesthetics
	printf "\n"

	# Assign to caller variable
	eval "$__var=\"\$answer\""
	return 0
}

# ============================================================================
# GENERIC MENU SYSTEM - Single implementation for all menus
# ============================================================================

# Generic interactive menu with unified keyboard handling
# Usage: generic_menu "Title" display_callback item_count [initial_selected]
# display_callback receives: index selected_index
# Returns: 0 on success with selection in MENU_RESULT, 1 on ESC/cancel
generic_menu() {
	local title="$1"
	local item_callback="$2"
	local max_items="$3"
	local initial_selected="${4:-0}"
	local selected=$initial_selected

	# Handle empty menu
	if [ "$max_items" -le 0 ]; then
		MENU_RESULT=-1
		return 1
	fi

	while true; do
		clear
		echo -e "${BLUE}${title}${NC}\n"

		# Call the display callback for each item
		for ((i = 0; i < max_items; i++)); do
			"$item_callback" "$i" "$selected"
		done

		echo
		echo -e "${YELLOW}Use ↑↓ to navigate, → or Enter to select, ← or Esc to cancel${NC}"

		key=$(read_key)
		case "$key" in
			UP)
				if [ $selected -gt 0 ]; then ((selected--)); fi
				;;
			DOWN)
				if [ $selected -lt $((max_items - 1)) ]; then ((selected++)); fi
				;;
			RIGHT|ENTER)
				MENU_RESULT=$selected
				return 0
				;;
			LEFT|ESC)
				MENU_RESULT=-1
				return 1
				;;
			*)
				# Check for numeric shortcut
				if [[ "$key" =~ ^[1-9]$ ]]; then
					local num=$((10#$key))
					if [ $num -le $max_items ]; then
						MENU_RESULT=$((num - 1))
						return 0
					fi
				fi
				# Check for letter shortcuts (handled by caller if needed)
				;;
		esac
	done
}

# ============================================================================
# DISPLAY HELPERS - Simple, reusable display functions
# ============================================================================

# Display a simple list item
# Args: index selected_index item_name [description]
display_simple_item() {
	local i="$1"
	local selected="$2"
	local name="$3"
	local desc="$4"

	if [ $i -eq $selected ]; then
		echo -e "${GREEN}► ${CYAN}${name}${NC}"
		if [ -n "$desc" ]; then
			echo -e "${GRAY}  ${desc}${NC}"
		fi
	else
		echo -e "  ${name}"
		if [ -n "$desc" ]; then
			echo -e "  ${GRAY}${desc}${NC}"
		fi
	fi
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Normalize branch name to be valid git branch name
normalize_branch_name() {
	local input="$1"

	# Convert to lowercase and replace spaces with hyphens
	local normalized=$(echo "$input" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

	# Remove leading/trailing hyphens
	normalized=$(echo "$normalized" | sed 's/^-*//g' | sed 's/-*$//g')

	# Replace multiple consecutive hyphens with single hyphen
	normalized=$(echo "$normalized" | sed 's/-\+/-/g')

	# Remove invalid characters (keep only alphanumeric, hyphens, underscores, dots, slashes)
	normalized=$(echo "$normalized" | sed 's/[^a-z0-9._/-]//g')

	# Ensure it doesn't end with .lock
	if [[ "$normalized" == *.lock ]]; then
		normalized="${normalized%.lock}"
	fi

	echo "$normalized"
}

# Open a directory in VS Code
open_in_vscode() {
	local target_dir="$1"

	if command -v code >/dev/null 2>&1; then
		echo -e "${YELLOW}Launching VS Code...${NC}"
		(nohup code -n "$target_dir" >/dev/null 2>&1 &)
		echo -e "${GREEN}VS Code launched at: $target_dir${NC}"
	else
		if [ "$(uname -s)" = "Darwin" ]; then
			echo -e "${YELLOW}Opening Visual Studio Code (macOS)...${NC}"
			open -a "Visual Studio Code" "$target_dir"
			echo -e "${GREEN}VS Code opened at: $target_dir${NC}"
		else
			echo -e "${RED}Couldn't find 'code' CLI. Please open VS Code manually at: ${NC}$target_dir"
		fi
	fi
}

# Get the target directory mirroring current subdirectory in worktree
get_worktree_target_dir() {
	local worktree_path="$1"
	local repo_root cwd rel target_dir

	repo_root="$(git rev-parse --show-toplevel)"
	cwd="$(pwd)"
	rel=""

	if [[ "$cwd" == "$repo_root" ]]; then
		rel=""
	elif [[ "$cwd" == "$repo_root"/* ]]; then
		rel="${cwd#$repo_root/}"
	fi

	if [ -n "$rel" ]; then
		target_dir="$worktree_path/$rel"
	else
		target_dir="$worktree_path"
	fi

	if [ ! -d "$target_dir" ]; then
		target_dir="$worktree_path"
	fi

	echo "$target_dir"
}

# Parse worktree list into arrays
# Sets: WT_PATHS, WT_BRANCHES, WT_COMMITS (if available)
parse_worktrees() {
	local include_commits="${1:-false}"

	WT_PATHS=()
	WT_BRANCHES=()
	WT_COMMITS=()

	while IFS= read -r line; do
		if [[ "$line" =~ ^worktree ]]; then
			WT_PATHS+=("${line#worktree }")
			WT_BRANCHES+=("")
			if [ "$include_commits" = "true" ]; then
				WT_COMMITS+=("")
			fi
		elif [[ "$line" =~ ^branch ]]; then
			local branch="${line#branch refs/heads/}"
			WT_BRANCHES[$((${#WT_BRANCHES[@]}-1))]="$branch"
		elif [[ "$line" =~ ^HEAD ]] && [ "$include_commits" = "true" ]; then
			local commit="${line#HEAD }"
			WT_COMMITS[$((${#WT_COMMITS[@]}-1))]="$commit"
		fi
	done < <(git worktree list --porcelain 2>/dev/null || echo "")
}

# ============================================================================
# HANDLERS - Business logic for each operation
# ============================================================================

# Handle add worktree
handle_add() {
	local current_branch base_branch new_branch_name repo_root repo_name parent_dir worktree_base worktree_path launch_vscode target_dir

	echo -e "${BLUE}Add New Worktree${NC}\n"

	current_branch=$(git branch --show-current)

	# Show base branch options menu
	display_add_branch() {
		local i="$1"
		local selected="$2"
		case "$i" in
			0) display_simple_item "$i" "$selected" "Current Branch (${current_branch})" ;;
			1) display_simple_item "$i" "$selected" "master" ;;
			2) display_simple_item "$i" "$selected" "Enter branch name" ;;
		esac
	}

	generic_menu "Select base branch" display_add_branch 3 0
	if [ $? -ne 0 ]; then
		return 1
	fi

	case "$MENU_RESULT" in
		0) base_branch="$current_branch" ;;
		1) base_branch="master" ;;
		2)
			ask "Enter branch name: " base_branch true
			if [ $? -eq 2 ]; then
				return 1
			elif [ $? -ne 0 ]; then
				echo -e "${RED}Error: Branch name is required${NC}"
				return 1
			fi
			;;
	esac

	# Get new branch name for worktree
	ask "Enter new branch name for worktree: " new_branch_name true
	if [ $? -eq 2 ]; then
		return 1
	elif [ $? -ne 0 ]; then
		echo -e "${RED}Error: Branch name is required${NC}"
		return 1
	fi

	# Normalize the branch name
	new_branch_name=$(normalize_branch_name "$new_branch_name")

	if [ -z "$new_branch_name" ]; then
		echo -e "${RED}Error: Branch name resulted in empty string after normalization${NC}"
		return 1
	fi

	echo -e "${GRAY}Normalized branch name: ${NC}${GREEN}$new_branch_name${NC}"

	# Generate worktree path automatically
	repo_root="$(git rev-parse --show-toplevel)"
	repo_name="$(basename "$repo_root")"
	parent_dir="$(dirname "$repo_root")"
	worktree_base="${parent_dir}/${repo_name}.worktrees"
	worktree_path="${worktree_base}/${new_branch_name}"

	# Create the worktree directory if it doesn't exist
	mkdir -p "$worktree_base"

	# Create the worktree with new branch
	echo -e "${YELLOW}Creating worktree with new branch '$new_branch_name' based on '$base_branch'...${NC}"
	echo -e "${GRAY}Worktree path: $worktree_path${NC}"
	git worktree add -b "$new_branch_name" "$worktree_path" "$base_branch"

	echo -e "${GREEN}Worktree created successfully at: $worktree_path${NC}"

	# Offer to launch VS Code in the new worktree
	ask "Launch new VS Code window in the worktree (Y/n)? " launch_vscode false
	if [ $? -ne 2 ]; then
		launch_vscode="${launch_vscode:-y}"
		if [[ -z "$launch_vscode" || "$launch_vscode" =~ ^[Yy]$ ]]; then
			target_dir=$(get_worktree_target_dir "$worktree_path")
			open_in_vscode "$target_dir"
		fi
	fi

	return 0
}

# Handle list worktrees
handle_list() {
	local chosen_path launch_vscode target_dir
	local WT_PATHS WT_BRANCHES WT_COMMITS

	echo -e "${BLUE}Current Worktrees${NC}\n"

	if ! git worktree list --porcelain >/dev/null 2>&1; then
		echo -e "${RED}No worktrees found${NC}"
		return 0
	fi

	# Parse worktrees with commits
	parse_worktrees true

	if [ ${#WT_PATHS[@]} -eq 0 ]; then
		echo -e "${GREEN}No worktrees found${NC}"
		return 0
	fi

	# Display menu
	display_worktree() {
		local i="$1"
		local selected="$2"
		local p="${WT_PATHS[$i]}"
		local b="${WT_BRANCHES[$i]}"
		local c="${WT_COMMITS[$i]}"
		local display="${p} | ${c:0:8} | ${b}"

		if [ $i -eq $selected ]; then
			echo -e "${GREEN}► ${CYAN}${display}${NC}"
		else
			echo -e "  ${display}"
		fi
	}

	generic_menu "Current Worktrees" display_worktree ${#WT_PATHS[@]} 0
	if [ $? -ne 0 ]; then
		return 1
	fi

	chosen_path="${WT_PATHS[$MENU_RESULT]}"

	ask "Open selected worktree in a new VS Code window (Y/n)? " launch_vscode false
	if [ $? -eq 2 ]; then
		echo -e "${GRAY}Cancelled — returning to menu...${NC}"
		sleep 0.2
		return 0
	fi

	launch_vscode="${launch_vscode:-y}"
	if [[ -z "$launch_vscode" || "$launch_vscode" =~ ^[Yy]$ ]]; then
		target_dir=$(get_worktree_target_dir "$chosen_path")
		open_in_vscode "$target_dir"
	fi

	return 0
}

# Handle remove worktree
handle_remove() {
	local target_path target_branch dirty is_clean repo_root remote pushed remote_has remote_matches local_commit remote_commit confirm1 confirm2 confirm_safe
	local WT_PATHS WT_BRANCHES

	echo -e "${BLUE}Remove Worktree${NC}\n"

	# Parse worktrees
	parse_worktrees false

	if [ ${#WT_PATHS[@]} -eq 0 ]; then
		echo -e "${RED}No worktrees found${NC}"
		return 0
	fi

	# Display menu
	display_remove() {
		local i="$1"
		local selected="$2"
		local p="${WT_PATHS[$i]}"
		local b="${WT_BRANCHES[$i]}"
		local line="${p} | ${b}"

		if [ $i -eq $selected ]; then
			echo -e "${GREEN}► ${CYAN}${line}${NC}"
		else
			echo -e "  ${line}"
		fi
	}

	generic_menu "Remove Worktree" display_remove ${#WT_PATHS[@]} 0
	if [ $? -ne 0 ]; then
		return 1
	fi

	target_path="${WT_PATHS[$MENU_RESULT]}"
	target_branch="${WT_BRANCHES[$MENU_RESULT]}"

	echo -e "${YELLOW}Selected: ${target_path} (${target_branch})${NC}"

	# Check cleanliness
	dirty=$(git -C "$target_path" status --porcelain 2>/dev/null || true)
	is_clean=true
	if [ -n "$dirty" ]; then
		is_clean=false
	fi

	# Determine remote and pushed status
	repo_root="$(git rev-parse --show-toplevel)"
	remote="$(git -C "$repo_root" remote | head -n1)"
	pushed=false
	remote_has=false
	remote_matches=false
	local_commit=""
	remote_commit=""

	if [ -n "$target_branch" ]; then
		# Get local commit at HEAD for worktree
		local_commit=$(git -C "$target_path" rev-parse --verify HEAD 2>/dev/null || true)
		if [ -n "$local_commit" ] && [ -n "$remote" ]; then
			remote_commit=$(git -C "$repo_root" ls-remote "$remote" "refs/heads/$target_branch" 2>/dev/null | awk '{print $1}') || remote_commit=""
			if [ -n "$remote_commit" ]; then
				remote_has=true
			fi
			if [ "$remote_has" = true ] && [ "$remote_commit" = "$local_commit" ]; then
				remote_matches=true
			fi
			if [ "$remote_has" = true ] && [ "$remote_matches" = true ]; then
				pushed=true
			fi
		fi
	fi

	# Decide messages and confirmation flow
	if [ "$is_clean" = false ] || [ "$pushed" = false ]; then
		# Not safe
		echo -e "${RED}Warning:${NC} This worktree may not be fully committed and pushed."
		if [ "$is_clean" = false ]; then
			echo -e "${RED}- There are uncommitted changes in the worktree.${NC}"
		fi
		if [ "$pushed" = false ]; then
			if [ "$remote_has" = false ]; then
				echo -e "${RED}- The branch '$target_branch' does not exist on remote '$remote' (not pushed).${NC}"
			elif [ "$remote_matches" = false ]; then
				echo -e "${RED}- The branch '$target_branch' exists on remote '$remote' but differs from the worktree (local != remote).${NC}"
			else
				echo -e "${RED}- The branch '$target_branch' appears not pushed or in an unexpected state.${NC}"
			fi
		fi

		ask "Still delete this worktree? (y/N): " confirm1 false
		if [ $? -eq 2 ]; then
			echo -e "${GRAY}Cancelled — returning to menu...${NC}"
			sleep 0.2
			return 0
		fi
		if [[ ! "$confirm1" =~ ^[Yy]$ ]]; then
			echo -e "${GRAY}Operation cancelled${NC}"
			return 0
		fi

		# Final warning
		ask "Are you ABSOLUTELY sure you want to delete this worktree? This cannot be undone (y/N): " confirm2 false
		if [ $? -eq 2 ]; then
			echo -e "${GRAY}Cancelled — returning to menu...${NC}"
			sleep 0.2
			return 0
		fi
		if [[ ! "$confirm2" =~ ^[Yy]$ ]]; then
			echo -e "${GRAY}Operation cancelled${NC}"
			return 0
		fi

		echo -e "${YELLOW}Removing worktree...${NC}"
		git worktree remove "$target_path"
		echo -e "${GREEN}Worktree removed successfully${NC}"
		return 0
	else
		# Clean and pushed
		echo -e "${GREEN}This worktree appears committed and pushed. Safe to delete.${NC}"
		ask "Delete this worktree? (y/N): " confirm_safe false
		if [ $? -eq 2 ]; then
			echo -e "${GRAY}Cancelled — returning to menu...${NC}"
			sleep 0.2
			return 0
		fi
		if [[ "$confirm_safe" =~ ^[Yy]$ ]]; then
			echo -e "${YELLOW}Removing worktree...${NC}"
			git worktree remove "$target_path"
			echo -e "${GREEN}Worktree removed successfully${NC}"
		else
			echo -e "${GRAY}Operation cancelled${NC}"
		fi
	fi

	return 0
}

# Handle prune worktrees
handle_prune() {
	local confirm

	echo -e "${BLUE}Prune Worktrees${NC}\n"

	echo -e "${YELLOW}This will clean up worktree administrative files for removed worktrees.${NC}"
	ask "Continue? (y/N): " confirm true
	if [ $? -eq 2 ]; then
		return 1
	fi
	if [ $? -ne 0 ]; then
		confirm="n"
	fi

	if [[ "$confirm" =~ ^[Yy]$ ]]; then
		echo -e "${YELLOW}Pruning worktrees...${NC}"
		git worktree prune -v
		echo -e "${GREEN}Worktrees pruned successfully${NC}"
	else
		echo -e "${GRAY}Operation cancelled${NC}"
	fi

	return 0
}

# Handle lock worktree
handle_lock() {
	local target_path target_branch reason
	local WT_PATHS WT_BRANCHES

	echo -e "${BLUE}Lock Worktree${NC}\n"

	# Parse worktrees
	parse_worktrees false

	if [ ${#WT_PATHS[@]} -eq 0 ]; then
		echo -e "${RED}No worktrees found${NC}"
		return 0
	fi

	display_lock() {
		local i="$1"
		local selected="$2"
		local p="${WT_PATHS[$i]}"
		local b="${WT_BRANCHES[$i]}"
		local line="${p} | ${b}"

		if [ $i -eq $selected ]; then
			echo -e "${GREEN}► ${CYAN}${line}${NC}"
		else
			echo -e "  ${line}"
		fi
	}

	generic_menu "Lock Worktree" display_lock ${#WT_PATHS[@]} 0
	if [ $? -ne 0 ]; then
		return 1
	fi

	target_path="${WT_PATHS[$MENU_RESULT]}"
	target_branch="${WT_BRANCHES[$MENU_RESULT]}"

	ask "Enter lock reason (optional): " reason false
	if [ $? -eq 2 ]; then
		return 1
	fi
	if [ $? -ne 0 ]; then
		reason=""
	fi

	if [ -n "$reason" ]; then
		git worktree lock --reason "$reason" "$target_path"
	else
		git worktree lock "$target_path"
	fi

	echo -e "${GREEN}Worktree locked successfully${NC}"
	return 0
}

# Handle unlock worktree
handle_unlock() {
	local LOCKED_PATHS LOCKED_BRANCHES LOCK_REASONS target_path lock_reason confirm_unlock
	local ALL_PATHS ALL_BRANCHES p b wt_gitdir gd_path reason

	echo -e "${BLUE}Unlock Worktree${NC}\n"

	# Parse worktrees
	ALL_PATHS=()
	ALL_BRANCHES=()

	while IFS= read -r line; do
		if [[ "$line" =~ ^worktree ]]; then
			p="${line#worktree }"
			ALL_PATHS+=("$p")
			ALL_BRANCHES+=("")
		elif [[ "$line" =~ ^branch ]]; then
			b="${line#branch refs/heads/}"
			ALL_BRANCHES[$((${#ALL_BRANCHES[@]}-1))]="$b"
		fi
	done < <(git worktree list --porcelain 2>/dev/null || echo "")

	LOCKED_PATHS=()
	LOCKED_BRANCHES=()
	LOCK_REASONS=()

	for i in "${!ALL_PATHS[@]}"; do
		p="${ALL_PATHS[$i]}"
		b="${ALL_BRANCHES[$i]}"

		wt_gitdir="$(git -C "$p" rev-parse --git-dir 2>/dev/null || true)"
		if [ -z "$wt_gitdir" ]; then
			continue
		fi
		if [ -f "$wt_gitdir" ]; then
			gd_path="$(sed -n 's/^gitdir: //p' "$wt_gitdir" || true)"
			if [ -n "$gd_path" ]; then
				wt_gitdir="$gd_path"
			fi
		fi

		if [ -f "$wt_gitdir/locked" ]; then
			reason="$(cat "$wt_gitdir/locked" 2>/dev/null || true)"
			LOCKED_PATHS+=("$p")
			LOCKED_BRANCHES+=("$b")
			LOCK_REASONS+=("$reason")
		fi
	done

	if [ ${#LOCKED_PATHS[@]} -eq 0 ]; then
		echo -e "${GRAY}No locked worktrees found.${NC}"
		return 0
	fi

	display_unlock() {
		local i="$1"
		local selected="$2"
		local p="${LOCKED_PATHS[$i]}"
		local b="${LOCKED_BRANCHES[$i]}"
		local reason="${LOCK_REASONS[$i]}"
		local line="${p} | ${b}"

		if [ $i -eq $selected ]; then
			echo -e "${GREEN}► ${CYAN}${line}${NC}"
			if [ -n "$reason" ]; then
				echo -e "    ${GRAY}Lock: ${reason}${NC}"
			fi
		else
			echo -e "  ${line}"
		fi
	}

	generic_menu "Unlock Worktree" display_unlock ${#LOCKED_PATHS[@]} 0
	if [ $? -ne 0 ]; then
		return 1
	fi

	target_path="${LOCKED_PATHS[$MENU_RESULT]}"
	lock_reason="${LOCK_REASONS[$MENU_RESULT]}"

	echo -e "${YELLOW}Selected: ${target_path}${NC}"
	echo -e "${RED}This worktree is locked.${NC}"
	if [ -n "$lock_reason" ]; then
		echo -e "${GRAY}Lock message:${NC} ${lock_reason}"
	fi

	ask "Unlock this worktree? (y/N): " confirm_unlock false
	if [ $? -eq 2 ]; then
		echo -e "${GRAY}Cancelled — returning to menu...${NC}"
		sleep 0.2
		return 0
	fi
	if [[ "$confirm_unlock" =~ ^[Yy]$ ]]; then
		git worktree unlock "$target_path"
		echo -e "${GREEN}Worktree unlocked successfully${NC}"
	else
		echo -e "${GRAY}Operation cancelled${NC}"
	fi

	return 0
}

# Handle move worktree
handle_move() {
	local current_path new_path
	local WT_PATHS WT_BRANCHES

	echo -e "${BLUE}Move Worktree${NC}\n"

	# Parse worktrees
	parse_worktrees false

	if [ ${#WT_PATHS[@]} -eq 0 ]; then
		echo -e "${RED}No worktrees found${NC}"
		return 0
	fi

	display_move() {
		local i="$1"
		local selected="$2"
		local p="${WT_PATHS[$i]}"
		local b="${WT_BRANCHES[$i]}"
		local line="${p} | ${b}"

		if [ $i -eq $selected ]; then
			echo -e "${GREEN}► ${CYAN}${line}${NC}"
		else
			echo -e "  ${line}"
		fi
	}

	generic_menu "Move Worktree" display_move ${#WT_PATHS[@]} 0
	if [ $? -ne 0 ]; then
		return 1
	fi

	current_path="${WT_PATHS[$MENU_RESULT]}"

	ask "Enter new worktree path: " new_path true
	if [ $? -eq 2 ]; then
		return 1
	fi
	if [ $? -ne 0 ]; then
		echo -e "${RED}Error: New path is required${NC}"
		return 1
	fi

	echo -e "${YELLOW}Moving worktree from '$current_path' to '$new_path'...${NC}"
	git worktree move "$current_path" "$new_path"
	echo -e "${GREEN}Worktree moved successfully${NC}"

	return 0
}

# Handle repair worktrees
handle_repair() {
	local idx path_to_repair
	local WT_PATHS WT_BRANCHES

	echo -e "${BLUE}Repair Worktrees${NC}\n"

	# Parse worktrees and include an "All worktrees" option
	parse_worktrees false

	# Prepend "All worktrees" option
	WT_PATHS=("(All worktrees)" "${WT_PATHS[@]}")
	WT_BRANCHES=("" "${WT_BRANCHES[@]}")

	display_repair() {
		local i="$1"
		local selected="$2"
		local p="${WT_PATHS[$i]}"
		local b="${WT_BRANCHES[$i]}"
		local line

		if [ $i -eq 0 ]; then
			line="$p"
		else
			line="${p} | ${b}"
		fi

		if [ $i -eq $selected ]; then
			echo -e "${GREEN}► ${CYAN}${line}${NC}"
		else
			echo -e "  ${line}"
		fi
	}

	generic_menu "Repair Worktrees" display_repair ${#WT_PATHS[@]} 0
	if [ $? -ne 0 ]; then
		return 1
	fi

	idx=$MENU_RESULT
	if [ $idx -eq 0 ]; then
		echo -e "${YELLOW}Repairing all worktrees...${NC}"
		git worktree repair
	else
		path_to_repair="${WT_PATHS[$idx]}"
		echo -e "${YELLOW}Repairing worktree: ${path_to_repair}${NC}"
		git worktree repair "$path_to_repair"
	fi

	echo -e "${GREEN}Worktrees repaired successfully${NC}"
	return 0
}

# ============================================================================
# MAIN MENU
# ============================================================================

# Display callback for main menu
display_operation_item() {
	local i="$1"
	local selected="$2"

	local title="${OPERATION_TITLES[$i]}"
	local desc="${OPERATION_DESCRIPTIONS[$i]}"
	local shortcut="${OPERATION_SHORTCUTS[$i]}"

	# Find first occurrence of shortcut in title (case-insensitive)
	local lower_title="$(printf "%s" "$title" | tr '[:upper:]' '[:lower:]')"
	local lower_short="$(printf "%s" "$shortcut" | tr '[:upper:]' '[:lower:]')"
	local pos=0
	if [ -n "$lower_short" ]; then
		pos=$(awk -v a="$lower_title" -v b="$lower_short" 'BEGIN{print index(a,b)}')
	fi

	if [ "$pos" -gt 0 ]; then
		local idx=$((pos - 1))
		local prefix="${title:0:idx}"
		local ch="${title:$idx:1}"
		local suffix="${title:$((idx + 1))}"

		if [ $i -eq $selected ]; then
			echo -e "${GREEN}► ${prefix}${UNDERLINE}${ch}${NC}${GREEN}${suffix}${NC}"
			echo -e "${CYAN}  ${desc}${NC}"
		else
			echo -e "${GRAY}  ${prefix}${UNDERLINE}${ch}${NC}${GRAY}${suffix}${NC}"
			echo -e "${GRAY}  ${desc}${NC}"
		fi
	else
		if [ $i -eq $selected ]; then
			echo -e "${GREEN}► ${title}${NC} ${PURPLE}[${YELLOW}${shortcut}${PURPLE}]${NC}"
			echo -e "${CYAN}  ${desc}${NC}"
		else
			echo -e "${GRAY}  ${title}${NC} ${PURPLE}[${shortcut}]${NC}"
			echo -e "${GRAY}  ${desc}${NC}"
		fi
	fi

	echo
}

# Display main menu
show_menu() {
	clear
	echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
	echo -e "${BLUE}Git Worktree Management Menu${NC}"
	echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}\n"

	# Show current repository info
	echo -e "${GRAY}Repository: ${NC}$(basename "$REPO_ROOT")"
	echo -e "${GRAY}Current branch: ${NC}$(git branch --show-current)"
	echo -e "${GRAY}Working directory: ${NC}$(pwd)\n"

	for i in "${!OPERATION_NAMES[@]}"; do
		display_operation_item "$i" "$SELECTED"
	done

	echo -e "${YELLOW}Use arrow keys to navigate, hotkey letter to select, Enter to confirm, 'q' to quit${NC}"
}

# Execute selected operation
execute_operation() {
	local operation="${OPERATION_NAMES[$SELECTED]}"

	echo
	local rc=0
	case "$operation" in
		"add")
			handle_add || rc=$?
			;;
		"list")
			handle_list || rc=$?
			;;
		"remove")
			handle_remove || rc=$?
			;;
		"prune")
			handle_prune || rc=$?
			;;
		"lock")
			handle_lock || rc=$?
			;;
		"unlock")
			handle_unlock || rc=$?
			;;
		"move")
			handle_move || rc=$?
			;;
		"repair")
			handle_repair || rc=$?
			;;
		*)
			echo -e "${RED}Unknown operation: $operation${NC}"
			return 1
			;;
	esac

	# If handler returned non-zero (ESC/cancel), return to menu quietly
	if [ "$rc" -ne 0 ]; then
		echo -e "${GRAY}Returning to menu...${NC}"
		sleep 0.3
		return 0
	fi

	echo
	echo -e "${YELLOW}Press any key to return to menu...${NC}"
	read_key >/dev/null
}

# Main menu loop
main() {
	# Check if we're in a git repository
	if ! git rev-parse --git-dir >/dev/null 2>&1; then
		echo -e "${RED}Error: Not in a git repository${NC}"
		exit 1
	fi

	show_menu

	while true; do
		key=$(read_key)

		case "$key" in
			UP)
				if [ $SELECTED -gt 0 ]; then
					((SELECTED--))
				fi
				show_menu
				;;
			DOWN)
				if [ $SELECTED -lt $((${#OPERATION_NAMES[@]} - 1)) ]; then
					((SELECTED++))
				fi
				show_menu
				;;
			RIGHT|ENTER)
				execute_operation
				show_menu
				;;
			q|Q)
				clear
				echo -e "${GRAY}Goodbye!${NC}"
				exit 0
				;;
			*)
				# Check if key matches a shortcut
				lower_k="$(printf "%s" "$key" | tr '[:upper:]' '[:lower:]')"
				for i in "${!OPERATION_SHORTCUTS[@]}"; do
					if [[ "$lower_k" == "${OPERATION_SHORTCUTS[$i]}" ]]; then
						SELECTED=$i
						execute_operation
						show_menu
						break
					fi
				done
				;;
		esac
	done
}

# Run the main function
main
