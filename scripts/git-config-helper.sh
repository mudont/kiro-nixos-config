#!/bin/bash
# Git Configuration Management Helper Script
# This script helps manage Git-based configuration backup and rollback

set -euo pipefail

CONFIG_DIR="/etc/nixos"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
Git Configuration Management Helper

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    init                Initialize Git repository in /etc/nixos
    setup-remote <url>  Add remote repository for backup
    backup              Manually backup configuration to Git
    status              Show Git status and recent commits
    log                 Show configuration change history
    rollback <commit>   Rollback to specific commit
    list-commits        List recent commits with details
    diff [commit]       Show differences from current or specific commit
    push                Push local commits to remote repository
    pull                Pull latest changes from remote repository

Examples:
    $0 init
    $0 setup-remote git@github.com:username/nixos-config.git
    $0 backup
    $0 rollback HEAD~1
    $0 diff HEAD~2
EOF
}

init_git_repo() {
    log_info "Initializing Git repository in $CONFIG_DIR..."
    
    cd "$CONFIG_DIR"
    
    if [ -d ".git" ]; then
        log_warning "Git repository already exists"
        return 0
    fi
    
    git init
    git config user.name "NixOS System"
    git config user.email "system@nixos.local"
    
    # Create comprehensive .gitignore
    cat > .gitignore << 'EOF'
# Hardware-specific files
hardware-configuration.nix

# Temporary files
*.tmp
*.bak
*~
.#*
\#*#

# Secrets and sensitive data
secrets/
*.key
*.pem
*.crt
*.p12
*.pfx
password*
*secret*

# Build artifacts
result
result-*

# Editor files
.vscode/
.idea/
*.swp
*.swo

# OS files
.DS_Store
Thumbs.db

# Logs
*.log
EOF
    
    # Add initial files
    git add .
    git commit -m "Initial NixOS configuration commit"
    
    log_success "Git repository initialized successfully"
}

setup_remote() {
    local remote_url="$1"
    
    cd "$CONFIG_DIR"
    
    if [ ! -d ".git" ]; then
        log_error "No Git repository found. Run '$0 init' first."
        exit 1
    fi
    
    log_info "Setting up remote repository: $remote_url"
    
    # Remove existing origin if it exists
    git remote remove origin 2>/dev/null || true
    
    # Add new remote
    git remote add origin "$remote_url"
    
    # Set up branch tracking
    git branch -M main
    
    log_success "Remote repository configured"
    log_info "You can now push with: $0 push"
}

backup_config() {
    log_info "Backing up configuration to Git..."
    
    cd "$CONFIG_DIR"
    
    if [ ! -d ".git" ]; then
        log_error "No Git repository found. Run '$0 init' first."
        exit 1
    fi
    
    # Add all changes
    git add .
    
    # Check if there are changes
    if git diff --staged --quiet; then
        log_info "No changes to commit"
        return 0
    fi
    
    # Show what will be committed
    echo "Changes to be committed:"
    git diff --staged --name-status
    echo
    
    # Commit with timestamp
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    git commit -m "Configuration backup: $TIMESTAMP"
    
    log_success "Configuration backed up to Git"
    
    # Offer to push if remote is configured
    if git remote get-url origin >/dev/null 2>&1; then
        read -p "Push to remote repository? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            push_to_remote
        fi
    fi
}

show_status() {
    cd "$CONFIG_DIR"
    
    if [ ! -d ".git" ]; then
        log_error "No Git repository found"
        exit 1
    fi
    
    log_info "Git Repository Status"
    echo "====================="
    
    # Show current branch and status
    echo "Branch: $(git branch --show-current)"
    echo "Remote: $(git remote get-url origin 2>/dev/null || echo 'Not configured')"
    echo
    
    # Show working directory status
    echo "Working Directory Status:"
    git status --porcelain || echo "Clean working directory"
    echo
    
    # Show recent commits
    echo "Recent Commits:"
    git log --oneline -5
}

show_log() {
    cd "$CONFIG_DIR"
    
    if [ ! -d ".git" ]; then
        log_error "No Git repository found"
        exit 1
    fi
    
    log_info "Configuration Change History"
    git log --oneline --graph --decorate -10
}

rollback_config() {
    local commit_hash="$1"
    
    cd "$CONFIG_DIR"
    
    if [ ! -d ".git" ]; then
        log_error "No Git repository found"
        exit 1
    fi
    
    log_warning "This will rollback configuration to commit: $commit_hash"
    log_warning "Current changes will be lost!"
    
    # Show what commit we're rolling back to
    echo "Target commit:"
    git show --oneline -s "$commit_hash"
    echo
    
    read -p "Are you sure you want to rollback? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Rollback cancelled"
        return 0
    fi
    
    # Create backup of current state
    BACKUP_BRANCH="backup-$(date +%Y%m%d_%H%M%S)"
    git branch "$BACKUP_BRANCH"
    log_info "Created backup branch: $BACKUP_BRANCH"
    
    # Rollback to specified commit
    git reset --hard "$commit_hash"
    
    log_success "Configuration rolled back to $commit_hash"
    log_warning "Run 'nixos-rebuild switch' to apply the changes"
    log_info "If you need to undo this rollback, use: git reset --hard $BACKUP_BRANCH"
}

list_commits() {
    cd "$CONFIG_DIR"
    
    if [ ! -d ".git" ]; then
        log_error "No Git repository found"
        exit 1
    fi
    
    log_info "Recent Configuration Commits"
    echo "============================"
    git log --pretty=format:"%h - %an, %ar : %s" -10
}

show_diff() {
    local commit="${1:-HEAD}"
    
    cd "$CONFIG_DIR"
    
    if [ ! -d ".git" ]; then
        log_error "No Git repository found"
        exit 1
    fi
    
    log_info "Configuration differences from $commit"
    git diff "$commit"
}

push_to_remote() {
    cd "$CONFIG_DIR"
    
    if [ ! -d ".git" ]; then
        log_error "No Git repository found"
        exit 1
    fi
    
    if ! git remote get-url origin >/dev/null 2>&1; then
        log_error "No remote repository configured"
        exit 1
    fi
    
    log_info "Pushing to remote repository..."
    
    # Try to push to main, then master as fallback
    if git push origin main 2>/dev/null; then
        log_success "Pushed to remote repository (main branch)"
    elif git push origin master 2>/dev/null; then
        log_success "Pushed to remote repository (master branch)"
    else
        log_error "Failed to push to remote repository"
        exit 1
    fi
}

pull_from_remote() {
    cd "$CONFIG_DIR"
    
    if [ ! -d ".git" ]; then
        log_error "No Git repository found"
        exit 1
    fi
    
    if ! git remote get-url origin >/dev/null 2>&1; then
        log_error "No remote repository configured"
        exit 1
    fi
    
    log_info "Pulling from remote repository..."
    
    # Stash local changes if any
    if ! git diff --quiet || ! git diff --staged --quiet; then
        log_warning "Stashing local changes..."
        git stash push -m "Auto-stash before pull $(date)"
    fi
    
    # Pull from remote
    git pull origin main || git pull origin master
    
    log_success "Pulled latest changes from remote repository"
    log_warning "Run 'nixos-rebuild switch' to apply any configuration changes"
}

# Main script logic
case "${1:-}" in
    init)
        init_git_repo
        ;;
    setup-remote)
        if [ $# -lt 2 ]; then
            log_error "Please specify remote repository URL"
            exit 1
        fi
        setup_remote "$2"
        ;;
    backup)
        backup_config
        ;;
    status)
        show_status
        ;;
    log)
        show_log
        ;;
    rollback)
        if [ $# -lt 2 ]; then
            log_error "Please specify commit hash"
            list_commits
            exit 1
        fi
        rollback_config "$2"
        ;;
    list-commits)
        list_commits
        ;;
    diff)
        show_diff "${2:-HEAD}"
        ;;
    push)
        push_to_remote
        ;;
    pull)
        pull_from_remote
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown command: ${1:-}"
        echo
        show_help
        exit 1
        ;;
esac