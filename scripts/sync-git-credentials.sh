#!/bin/bash
# Git Credentials Synchronization Script
# This script synchronizes Git configuration and SSH keys from Mac to NixOS server

set -euo pipefail

# Configuration
NIXOS_HOST="${NIXOS_HOST:-nixos}"
NIXOS_USER="${NIXOS_USER:-murali}"
MAC_USER="$(whoami)"

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
Git Credentials Synchronization Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    sync-config         Sync Git configuration from Mac to NixOS server
    sync-ssh-keys       Sync SSH keys for Git repository access
    sync-all            Sync both Git config and SSH keys
    status              Show Git configuration status on both systems
    test-git-access     Test Git repository access from NixOS server
    setup-github        Set up GitHub SSH access on NixOS server

Options:
    --host <hostname>   Override NixOS hostname (default: nixos)
    --user <username>   Override NixOS username (default: murali)
    --dry-run          Show what would be synced without making changes
    --force            Skip confirmation prompts
    --verbose          Enable verbose output

Examples:
    $0 sync-all
    $0 sync-config --dry-run
    $0 test-git-access
    $0 setup-github
EOF
}

# Parse command line arguments
COMMAND=""
DRY_RUN=false
FORCE=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            NIXOS_HOST="$2"
            shift 2
            ;;
        --user)
            NIXOS_USER="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        sync-config|sync-ssh-keys|sync-all|status|test-git-access|setup-github|help|--help|-h)
            COMMAND="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Enable verbose output if requested
if [ "$VERBOSE" = true ]; then
    set -x
fi

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if we're running on macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "This script is designed to run on macOS"
        exit 1
    fi
    
    # Check required commands
    local required_commands=("ssh" "git" "scp")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    # Check SSH connection
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" exit 2>/dev/null; then
        log_error "Cannot connect to NixOS server via SSH"
        log_info "Run the deployment script with 'setup-ssh' first"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

get_mac_git_config() {
    log_info "Reading Git configuration from Mac..."
    
    local git_config_items=(
        "user.name"
        "user.email"
        "user.signingkey"
        "commit.gpgsign"
        "core.editor"
        "core.autocrlf"
        "init.defaultBranch"
        "pull.rebase"
        "push.default"
        "credential.helper"
    )
    
    local config_commands=()
    
    for item in "${git_config_items[@]}"; do
        local value
        if value=$(git config --global "$item" 2>/dev/null); then
            config_commands+=("git config --global '$item' '$value'")
            if [ "$VERBOSE" = true ]; then
                log_info "Found: $item = $value"
            fi
        fi
    done
    
    printf '%s\n' "${config_commands[@]}"
}

sync_git_configuration() {
    log_info "Synchronizing Git configuration to NixOS server..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would sync the following Git configuration:"
        get_mac_git_config
        return 0
    fi
    
    # Get Git configuration from Mac
    local config_commands
    config_commands=$(get_mac_git_config)
    
    if [ -z "$config_commands" ]; then
        log_warning "No Git configuration found on Mac"
        return 0
    fi
    
    # Create temporary script with Git configuration commands
    local temp_script="/tmp/git-config-sync-$$.sh"
    cat > "$temp_script" << 'EOF'
#!/bin/bash
# Temporary Git configuration sync script
set -euo pipefail

echo "Setting up Git configuration..."
EOF
    
    echo "$config_commands" >> "$temp_script"
    echo 'echo "Git configuration updated successfully"' >> "$temp_script"
    
    # Copy and execute the script on NixOS server
    if scp "$temp_script" "$NIXOS_USER@$NIXOS_HOST:/tmp/git-config-sync.sh"; then
        ssh "$NIXOS_USER@$NIXOS_HOST" "chmod +x /tmp/git-config-sync.sh && /tmp/git-config-sync.sh && rm /tmp/git-config-sync.sh"
        log_success "Git configuration synchronized successfully"
    else
        log_error "Failed to sync Git configuration"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f "$temp_script"
}

sync_ssh_keys() {
    log_info "Synchronizing SSH keys for Git repository access..."
    
    local mac_ssh_dir="$HOME/.ssh"
    local key_files=("id_rsa" "id_ed25519" "id_ecdsa")
    local keys_found=false
    
    # Check for existing SSH keys on Mac
    for key in "${key_files[@]}"; do
        if [ -f "$mac_ssh_dir/$key" ] && [ -f "$mac_ssh_dir/$key.pub" ]; then
            keys_found=true
            
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN: Would sync SSH key: $key"
                continue
            fi
            
            log_info "Syncing SSH key: $key"
            
            # Copy private key
            if scp "$mac_ssh_dir/$key" "$NIXOS_USER@$NIXOS_HOST:.ssh/$key"; then
                ssh "$NIXOS_USER@$NIXOS_HOST" "chmod 600 ~/.ssh/$key"
            else
                log_error "Failed to copy private key: $key"
                continue
            fi
            
            # Copy public key
            if scp "$mac_ssh_dir/$key.pub" "$NIXOS_USER@$NIXOS_HOST:.ssh/$key.pub"; then
                ssh "$NIXOS_USER@$NIXOS_HOST" "chmod 644 ~/.ssh/$key.pub"
                log_success "SSH key synchronized: $key"
            else
                log_error "Failed to copy public key: $key.pub"
            fi
        fi
    done
    
    if [ "$keys_found" = false ]; then
        log_warning "No SSH keys found on Mac"
        log_info "Generate SSH keys with: ssh-keygen -t ed25519 -C 'your_email@example.com'"
        return 1
    fi
    
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    # Sync SSH config if it exists
    if [ -f "$mac_ssh_dir/config" ]; then
        log_info "Syncing SSH config file..."
        if scp "$mac_ssh_dir/config" "$NIXOS_USER@$NIXOS_HOST:.ssh/config"; then
            ssh "$NIXOS_USER@$NIXOS_HOST" "chmod 600 ~/.ssh/config"
            log_success "SSH config synchronized"
        else
            log_warning "Failed to sync SSH config"
        fi
    fi
    
    # Sync known_hosts if it exists
    if [ -f "$mac_ssh_dir/known_hosts" ]; then
        log_info "Syncing known_hosts file..."
        if scp "$mac_ssh_dir/known_hosts" "$NIXOS_USER@$NIXOS_HOST:.ssh/known_hosts"; then
            ssh "$NIXOS_USER@$NIXOS_HOST" "chmod 644 ~/.ssh/known_hosts"
            log_success "known_hosts synchronized"
        else
            log_warning "Failed to sync known_hosts"
        fi
    fi
    
    log_success "SSH keys synchronization completed"
}

setup_github_access() {
    log_info "Setting up GitHub SSH access on NixOS server..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would set up GitHub SSH access"
        return 0
    fi
    
    # Test if GitHub access already works
    if ssh "$NIXOS_USER@$NIXOS_HOST" "ssh -T git@github.com" 2>&1 | grep -q "successfully authenticated"; then
        log_success "GitHub SSH access already configured"
        return 0
    fi
    
    # Add GitHub to known_hosts
    log_info "Adding GitHub to known_hosts..."
    ssh "$NIXOS_USER@$NIXOS_HOST" "ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null"
    
    # Test GitHub connection
    log_info "Testing GitHub SSH connection..."
    if ssh "$NIXOS_USER@$NIXOS_HOST" "ssh -T git@github.com" 2>&1 | grep -q "successfully authenticated"; then
        log_success "GitHub SSH access configured successfully"
    else
        log_warning "GitHub SSH access test failed"
        log_info "You may need to add the SSH key to your GitHub account"
        log_info "Public key content:"
        ssh "$NIXOS_USER@$NIXOS_HOST" "cat ~/.ssh/id_*.pub 2>/dev/null | head -1" || true
    fi
}

show_git_status() {
    log_info "Git Configuration Status"
    echo "========================"
    
    # Mac Git configuration
    echo
    log_info "Mac Git Configuration:"
    git config --global --list | grep -E '^(user\.|core\.|init\.|pull\.|push\.)' || echo "  No relevant configuration found"
    
    # NixOS Git configuration
    echo
    log_info "NixOS Git Configuration:"
    ssh "$NIXOS_USER@$NIXOS_HOST" "git config --global --list | grep -E '^(user\.|core\.|init\.|pull\.|push\.)'" || echo "  No relevant configuration found"
    
    # SSH keys on Mac
    echo
    log_info "SSH Keys on Mac:"
    ls -la "$HOME/.ssh/id_*" 2>/dev/null | grep -v '.pub$' || echo "  No SSH keys found"
    
    # SSH keys on NixOS
    echo
    log_info "SSH Keys on NixOS:"
    ssh "$NIXOS_USER@$NIXOS_HOST" "ls -la ~/.ssh/id_* 2>/dev/null | grep -v '.pub$'" || echo "  No SSH keys found"
    
    # GitHub access test
    echo
    log_info "GitHub Access Test:"
    if ssh "$NIXOS_USER@$NIXOS_HOST" "ssh -T git@github.com" 2>&1 | grep -q "successfully authenticated"; then
        echo "  ✓ GitHub SSH access working"
    else
        echo "  ✗ GitHub SSH access not working"
    fi
}

test_git_repository_access() {
    log_info "Testing Git repository access from NixOS server..."
    
    # Test GitHub access
    log_info "Testing GitHub access..."
    if ssh "$NIXOS_USER@$NIXOS_HOST" "ssh -T git@github.com" 2>&1 | grep -q "successfully authenticated"; then
        log_success "GitHub SSH access working"
    else
        log_error "GitHub SSH access failed"
    fi
    
    # Test Git operations in a temporary directory
    log_info "Testing Git clone operation..."
    local test_repo="https://github.com/octocat/Hello-World.git"
    if ssh "$NIXOS_USER@$NIXOS_HOST" "cd /tmp && rm -rf Hello-World && git clone $test_repo && rm -rf Hello-World"; then
        log_success "Git clone operation successful"
    else
        log_error "Git clone operation failed"
    fi
    
    # Test if user can access their own repositories (if configured)
    local github_user
    if github_user=$(ssh "$NIXOS_USER@$NIXOS_HOST" "git config --global user.name" 2>/dev/null); then
        log_info "Git user configured as: $github_user"
    else
        log_warning "No Git user configured"
    fi
}

sync_all_credentials() {
    log_info "Synchronizing all Git credentials and SSH keys..."
    
    sync_git_configuration
    sync_ssh_keys
    setup_github_access
    
    log_success "All Git credentials synchronized successfully"
}

# Main script logic
case "$COMMAND" in
    sync-config)
        check_prerequisites
        sync_git_configuration
        ;;
    sync-ssh-keys)
        check_prerequisites
        sync_ssh_keys
        ;;
    sync-all)
        check_prerequisites
        sync_all_credentials
        ;;
    status)
        check_prerequisites
        show_git_status
        ;;
    test-git-access)
        check_prerequisites
        test_git_repository_access
        ;;
    setup-github)
        check_prerequisites
        setup_github_access
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        log_error "No command specified"
        echo
        show_help
        exit 1
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        echo
        show_help
        exit 1
        ;;
esac