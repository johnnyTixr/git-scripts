# git-scripts

A collection of interactive Bash scripts for Git branch cleanup and worktree management. All scripts feature arrow-key navigation, colorized output, and safety confirmations.

## Scripts Overview

### 🎯 git-cleanup.sh
**Main menu interface for branch cleanup operations**

An interactive menu that provides access to all branch cleanup scripts. Use arrow keys to navigate between different cleanup options and see detailed descriptions of what each operation does.

- Unified interface for all cleanup operations
- Shows descriptions for each cleanup type
- Arrow key navigation (↑/↓ to navigate, Enter to select, Q to quit)

**Usage:**
```bash
./git-cleanup.sh
```

---

### 🔥 cleanup-branches.sh
**Delete merged branches (local AND remote)**

Cleans up branches that have been merged to master and were authored by you. This script:
- Finds branches merged to master created by the current git user
- Excludes hotfix and release branches
- Shows branch commit details and merge commit information
- Deletes from **both local and remote (origin)**
- Interactive confirmation before deletion

**Features:**
- Shows commit hash, author, timestamp, and message
- Attempts to locate the merge commit in master
- Double confirmation required (shows merge status)
- Arrow key navigation

**Usage:**
```bash
./cleanup-branches.sh
```

---

### 📤 cleanup-local-branches.sh
**Delete local unpushed branches**

Removes local branches that haven't been pushed to remote. **Use with caution** - these could be useful branches!

- Finds branches that exist locally but not on remote
- Only shows branches authored by current user
- Excludes hotfix and release branches
- Deletes only from local (no remote impact)

**Features:**
- Shows commit information for each branch
- Warning about permanent deletion of unpushed work
- Arrow key navigation (↑/↓ to navigate, Enter to select, Q to quit)

**Usage:**
```bash
./cleanup-local-branches.sh
```

---

### ✅ cleanup-synced-branches.sh
**Delete local branches that are in sync with remote (preserves remote)**

Removes local branches that are perfectly synchronized with their remote tracking branch. The **remote branch is preserved** - only the local copy is deleted.

- Finds branches where local and remote have identical commits
- Excludes protected branches (master, staging, test, develop)
- Optional filter to show only branches where you're NOT an author
- Shows last 3 unique commit authors per branch
- Bulk delete option (press 'A' to delete all)

**Features:**
- Verifies sync status before deletion
- Shows branch date and author information
- "Delete all" functionality for batch cleanup
- Remote branches remain untouched

**Usage:**
```bash
./cleanup-synced-branches.sh
```

---

### ⚠️ cleanup-unmerged-branches.sh
**Delete unmerged branches (local AND remote)**

Removes branches with remote tracking that have **NOT** been merged to master. These are usually stale branches but **be cautious** - unmerged work will be lost!

- Finds branches with remote tracking not merged to master
- Only shows branches authored by current user
- Excludes hotfix and release branches
- Deletes from **both local and remote (origin)**
- Extra warnings since branches are unmerged

**Features:**
- Shows commit details and unmerged status
- Multiple confirmation steps
- Force delete (git branch -D) used locally
- Arrow key navigation

**Usage:**
```bash
./cleanup-unmerged-branches.sh
```

---

### 🌳 git-worktree.sh
**Comprehensive Git worktree management**

A full-featured worktree management tool with unified keyboard navigation. Worktrees allow you to work on multiple branches simultaneously in different directories.

**Available Operations:**

1. **Add New Worktree** (hotkey: `a`)
   - Create a new branch and worktree from base branch
   - Automatically creates worktree directory structure
   - Auto-normalizes branch names (lowercase, hyphens, etc.)
   - Optional VS Code launch in new worktree
   - Mirrors current subdirectory in new worktree

2. **List Worktrees** (hotkey: `l`)
   - Shows all existing worktrees with paths, branches, and commits
   - Select and open in VS Code
   - Displays commit hashes for each worktree

3. **Remove Worktree** (hotkey: `r`)
   - Safety checks for uncommitted changes
   - Verifies push status before deletion
   - Multiple confirmation levels based on safety
   - Clear warnings for unpushed or dirty worktrees

4. **Prune Worktrees** (hotkey: `p`)
   - Cleans up administrative files for removed worktrees
   - Verbose output showing what's being cleaned

5. **Lock Worktree** (hotkey: `k`)
   - Prevents worktree from being pruned
   - Optional reason/message for lock

6. **Unlock Worktree** (hotkey: `u`)
   - Shows currently locked worktrees
   - Displays lock reasons
   - Confirmation before unlocking

7. **Move Worktree** (hotkey: `m`)
   - Relocates worktree to new path
   - Updates git administrative files

8. **Repair Worktrees** (hotkey: `e`)
   - Fixes worktree administrative files
   - Can repair individual or all worktrees

**Features:**
- Unified keyboard input handling
- ESC key support throughout
- Intelligent VS Code launching (detects `code` CLI or macOS app)
- Branch name normalization
- Safety checks for uncommitted/unpushed changes
- Keyboard shortcuts and arrow key navigation
- Color-coded output with detailed status information

**Usage:**
```bash
./git-worktree.sh
```

---

## Requirements

- Git
- Bash shell (macOS/Linux)
- Terminal with color support
- VS Code (optional, for worktree script's launch feature)

## Installation

1. Clone this repository
2. Make scripts executable:
   ```bash
   chmod +x *.sh
   ```
3. Optionally, add to your PATH for global access

## Safety Features

All scripts include:
- ✅ Interactive confirmations before destructive operations
- ✅ Color-coded warnings (red for dangerous operations)
- ✅ Commit information display before deletion
- ✅ User-based filtering (only shows your branches)
- ✅ Protected branch exclusions
- ✅ Multiple confirmation steps for risky operations
- ✅ ESC key support to cancel operations

## Tips

- Start with `git-cleanup.sh` to access all cleanup options
- Use `cleanup-synced-branches.sh` for safe cleanup (preserves remotes)
- Be cautious with `cleanup-unmerged-branches.sh` - it deletes unmerged work
- `git-worktree.sh` is great for working on multiple features simultaneously
- All scripts filter by current git user to avoid touching others' branches
