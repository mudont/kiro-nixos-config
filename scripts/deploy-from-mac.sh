#!/bin/bash
# Mac Deployment Script for NixOS Home Server
# This script deploys configuration from Mac to NixOS server with validation and error handling

set -euo pipefail

# Configuration
NIXOS_HOST="${NIXOS_HOST:-nixos}"
NIXOS_USER="${NIXOS_USER:-murali}"
NIXOS_CONFIG_DIR="/etc/nixos"
LOCAL_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
Mac Deployment Script for NixOS Home Server

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    setup-ssh           Set up SSH keys and passwordless authentication
    sync-git            Synchronize Git credentials and SSH keys
    validate            Validate local configuration before deployment
    deploy              Deploy configuration to NixOS server
    deploy-and-rebuild  Deploy configuration and rebuild NixOS system
    full-deploy         Complete deployment with Git sync and rebuild
    status              Check deployment status and connectivity
    rollback            Rollback to previous configuration on server
    test-connection     Test SSH connection to NixOS server

Options:
    --host <hostname>   Override NixOS hostname (default: nixos)
    --user <username>   Override NixOS username (default: murali)
    --dry-run          Show what would be deployed without making changes
    --force            Skip confirmation prompts
    --verbose          Enable verbose output

Examples:
    $0 setup-ssh
    $0 validate
    $0 deploy --dry-run
    $0 deploy-and-rebuild
    $0 status
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
        setup-ssh|sync-git|validate|deploy|deploy-and-rebuild|full-deploy|status|rollback|test-connection|help|--help|-h)
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
    local required_commands=("ssh" "ssh-keygen" "rsync" "git")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    # Check if we're in the correct directory
    if [ ! -f "$LOCAL_CONFIG_DIR/flake.nix" ]; then
        log_error "Not in NixOS configuration directory (flake.nix not found)"
        log_error "Current directory: $LOCAL_CONFIG_DIR"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

test_ssh_connection() {
    log_info "Testing SSH connection to $NIXOS_USER@$NIXOS_HOST..."
    
    if ssh -o ConnectTimeout=10 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" exit 2>/dev/null; then
        log_success "SSH connection successful"
        return 0
    else
        log_error "SSH connection failed"
        return 1
    fi
}

setup_ssh_keys() {
    log_info "Setting up SSH keys for passwordless authentication..."
    
    local ssh_key_path="$HOME/.ssh/id_rsa"
    local ssh_pub_key_path="$HOME/.ssh/id_rsa.pub"
    
    # Generate SSH key if it doesn't exist
    if [ ! -f "$ssh_key_path" ]; then
        log_info "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f "$ssh_key_path" -N "" -C "$(whoami)@$(hostname)"
        log_success "SSH key pair generated"
    else
        log_info "SSH key already exists"
    fi
    
    # Test if passwordless SSH already works
    if test_ssh_connection; then
        log_success "Passwordless SSH already configured"
        return 0
    fi
    
    log_info "Setting up passwordless SSH access..."
    log_warning "You may be prompted for the NixOS server password"
    
    # Copy SSH key to server
    if ssh-copy-id -i "$ssh_pub_key_path" "$NIXOS_USER@$NIXOS_HOST"; then
        log_success "SSH key copied to server"
    else
        log_error "Failed to copy SSH key to server"
        exit 1
    fi
    
    # Test passwordless connection
    if test_ssh_connection; then
        log_success "Passwordless SSH authentication configured successfully"
    else
        log_error "Passwordless SSH setup failed"
        exit 1
    fi
}

validate_configuration() {
    log_info "Validating local NixOS configuration..."
    
    cd "$LOCAL_CONFIG_DIR"
    
    # Check if flake.nix exists and is valid
    if [ ! -f "flake.nix" ]; then
        log_error "flake.nix not found"
        exit 1
    fi
    
    # Validate flake syntax
    log_info "Checking flake syntax..."
    if command -v nix >/dev/null 2>&1; then
        if nix flake check --no-build 2>/dev/null; then
            log_success "Flake syntax is valid"
        else
            log_error "Flake syntax validation failed"
            log_info "Run 'nix flake check' for detailed error information"
            exit 1
        fi
    else
        log_warning "Nix not installed on Mac - skipping flake syntax validation"
        log_info "Flake will be validated on the NixOS server during rebuild"
    fi
    
    # Check for required files
    local required_files=(
        "configuration.nix"
        "networking.nix"
        "users.nix"
        "home-manager/home.nix"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Required file not found: $file"
            exit 1
        fi
    done
    
    # Check Git status
    if [ -d ".git" ]; then
        if [ -n "$(git status --porcelain)" ]; then
            log_warning "There are uncommitted changes in the repository"
            if [ "$FORCE" != true ]; then
                read -p "Continue with uncommitted changes? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Deployment cancelled"
                    exit 0
                fi
            fi
        fi
    fi
    
    log_success "Configuration validation passed"
}

deploy_configuration() {
    log_info "Deploying configuration to $NIXOS_HOST..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would deploy the following files:"
        rsync -avz --dry-run --delete \
            --exclude='.git' \
            --exclude='result*' \
            --exclude='*.tmp' \
            --exclude='.DS_Store' \
            --rsync-path="sudo rsync" \
            "$LOCAL_CONFIG_DIR/" "$NIXOS_USER@$NIXOS_HOST:$NIXOS_CONFIG_DIR/"
        return 0
    fi
    
    # Ensure SSH connection works
    if ! test_ssh_connection; then
        log_error "Cannot connect to NixOS server"
        exit 1
    fi
    
    # Create backup of current configuration on server
    log_info "Creating backup of current configuration on server..."
    ssh "$NIXOS_USER@$NIXOS_HOST" "sudo cp -r $NIXOS_CONFIG_DIR $NIXOS_CONFIG_DIR.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Deploy configuration files
    log_info "Syncing configuration files..."
    
    # Deploy entire project structure to preserve flake directory layout
    if ! rsync -avz --delete \
        --exclude='.git' \
        --exclude='.kiro' \
        --exclude='result*' \
        --exclude='*.tmp' \
        --exclude='.DS_Store' \
        --exclude='scripts/' \
        --exclude='tests/' \
        --exclude='docs/' \
        --rsync-path="sudo rsync" \
        "$LOCAL_CONFIG_DIR/" "$NIXOS_USER@$NIXOS_HOST:$NIXOS_CONFIG_DIR/"; then
        log_error "Failed to deploy configuration files"
        exit 1
    fi
    
    # Deploy flake files
    if ! rsync -avz \
        --rsync-path="sudo rsync" \
        "$LOCAL_CONFIG_DIR/flake.nix" "$LOCAL_CONFIG_DIR/flake.lock" "$NIXOS_USER@$NIXOS_HOST:$NIXOS_CONFIG_DIR/"; then
        log_error "Failed to deploy flake files"
        exit 1
    fi
    
    log_success "Configuration files deployed successfully"
    
    # Set correct ownership
    ssh "$NIXOS_USER@$NIXOS_HOST" "sudo chown -R root:root $NIXOS_CONFIG_DIR"
    
    # Update Git repository on server if it exists
    ssh "$NIXOS_USER@$NIXOS_HOST" "cd $NIXOS_CONFIG_DIR && if [ -d .git ]; then sudo git add . && sudo git commit -m 'Deployed from Mac at $(date)' || true; fi"
    
    log_success "Configuration deployment completed"
}

rebuild_nixos() {
    log_info "Rebuilding NixOS system on $NIXOS_HOST..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would run 'nixos-rebuild switch' on server"
        return 0
    fi
    
    # Store current generation for potential rollback
    local current_generation
    current_generation=$(ssh "$NIXOS_USER@$NIXOS_HOST" "sudo nixos-rebuild list-generations | tail -1 | awk '{print \$1}'")
    log_info "Current generation: $current_generation"
    
    # Run nixos-rebuild switch on the server
    log_info "Running nixos-rebuild switch (this may take several minutes)..."
    if ssh "$NIXOS_USER@$NIXOS_HOST" "cd $NIXOS_CONFIG_DIR && timeout 1800 sudo nixos-rebuild switch --flake .#nixos"; then
        log_success "NixOS system rebuilt successfully"
        
        # Run health checks after successful rebuild
        if run_health_checks; then
            log_success "Health checks passed - deployment successful"
        else
            log_error "Health checks failed - initiating automatic rollback"
            automatic_rollback "$current_generation"
            exit 1
        fi
    else
        log_error "NixOS rebuild failed"
        log_warning "The system may be in an inconsistent state"
        
        # Attempt automatic rollback
        log_info "Attempting automatic rollback to generation $current_generation..."
        automatic_rollback "$current_generation"
        exit 1
    fi
}

automatic_rollback() {
    local target_generation="$1"
    
    log_warning "Initiating automatic rollback to generation $target_generation..."
    
    if ssh "$NIXOS_USER@$NIXOS_HOST" "sudo nixos-rebuild switch --rollback"; then
        log_success "Automatic rollback completed successfully"
        
        # Verify rollback with basic health checks
        if basic_health_check; then
            log_success "System restored to working state"
        else
            log_error "System still not responding properly after rollback"
            log_error "Manual intervention may be required"
        fi
    else
        log_error "Automatic rollback failed"
        log_error "Manual intervention required on the NixOS server"
    fi
}

basic_health_check() {
    log_info "Running basic health check..."
    
    # Check if system is responsive
    if ! ssh -o ConnectTimeout=30 "$NIXOS_USER@$NIXOS_HOST" "echo 'System responsive'" >/dev/null 2>&1; then
        log_error "System not responding to SSH"
        return 1
    fi
    
    # Check if systemd is running
    if ! ssh "$NIXOS_USER@$NIXOS_HOST" "systemctl is-system-running --wait" >/dev/null 2>&1; then
        log_warning "System not fully operational"
        return 1
    fi
    
    return 0
}

run_health_checks() {
    log_info "Running comprehensive health checks..."
    
    local health_check_failed=false
    
    # Basic system health
    if ! basic_health_check; then
        health_check_failed=true
    fi
    
    # Check critical services
    local critical_services=("sshd" "NetworkManager")
    for service in "${critical_services[@]}"; do
        if ! ssh "$NIXOS_USER@$NIXOS_HOST" "systemctl is-active --quiet $service"; then
            log_error "Critical service not running: $service"
            health_check_failed=true
        else
            log_info "✓ Service running: $service"
        fi
    done
    
    # Check optional services (don't fail deployment if these are down)
    local optional_services=("nginx" "postgresql" "samba" "xrdp")
    for service in "${optional_services[@]}"; do
        if ssh "$NIXOS_USER@$NIXOS_HOST" "systemctl is-enabled --quiet $service 2>/dev/null"; then
            if ssh "$NIXOS_USER@$NIXOS_HOST" "systemctl is-active --quiet $service"; then
                log_info "✓ Service running: $service"
            else
                log_warning "Optional service not running: $service"
            fi
        fi
    done
    
    # Check disk space
    local disk_usage
    disk_usage=$(ssh "$NIXOS_USER@$NIXOS_HOST" "df / | tail -1 | awk '{print \$5}' | sed 's/%//'")
    if [ "$disk_usage" -gt 90 ]; then
        log_error "Disk usage too high: ${disk_usage}%"
        health_check_failed=true
    else
        log_info "✓ Disk usage acceptable: ${disk_usage}%"
    fi
    
    # Check memory usage
    local memory_usage
    memory_usage=$(ssh "$NIXOS_USER@$NIXOS_HOST" "free | grep Mem | awk '{printf \"%.0f\", \$3/\$2 * 100.0}'")
    if [ "$memory_usage" -gt 95 ]; then
        log_warning "Memory usage high: ${memory_usage}%"
    else
        log_info "✓ Memory usage acceptable: ${memory_usage}%"
    fi
    
    # Check network connectivity
    if ssh "$NIXOS_USER@$NIXOS_HOST" "ping -c 1 8.8.8.8 >/dev/null 2>&1"; then
        log_info "✓ Network connectivity working"
    else
        log_error "Network connectivity failed"
        health_check_failed=true
    fi
    
    # Test web services if nginx is enabled
    if ssh "$NIXOS_USER@$NIXOS_HOST" "systemctl is-enabled --quiet nginx 2>/dev/null"; then
        if ssh "$NIXOS_USER@$NIXOS_HOST" "curl -s -o /dev/null -w '%{http_code}' http://localhost" | grep -q "200\|301\|302"; then
            log_info "✓ Web server responding"
        else
            log_warning "Web server not responding properly"
        fi
    fi
    
    if [ "$health_check_failed" = true ]; then
        log_error "Health checks failed"
        return 1
    else
        log_success "All health checks passed"
        return 0
    fi
}

verify_services() {
    log_info "Verifying service configuration and status..."
    
    # Get list of enabled services
    local enabled_services
    enabled_services=$(ssh "$NIXOS_USER@$NIXOS_HOST" "systemctl list-unit-files --state=enabled --type=service | grep -E '(nginx|postgresql|samba|xrdp|prometheus|grafana)' | awk '{print \$1}' | sed 's/.service$//'")
    
    if [ -n "$enabled_services" ]; then
        log_info "Checking enabled services:"
        while IFS= read -r service; do
            if ssh "$NIXOS_USER@$NIXOS_HOST" "systemctl is-active --quiet $service"; then
                log_info "  ✓ $service: active"
            else
                log_warning "  ✗ $service: inactive"
                # Try to get service status for debugging
                ssh "$NIXOS_USER@$NIXOS_HOST" "systemctl status $service --no-pager -l" || true
            fi
        done <<< "$enabled_services"
    else
        log_info "No additional services to verify"
    fi
    
    # Check firewall status
    if ssh "$NIXOS_USER@$NIXOS_HOST" "systemctl is-active --quiet firewall"; then
        log_info "✓ Firewall: active"
    else
        log_warning "✗ Firewall: inactive"
    fi
    
    # Check open ports
    log_info "Open ports:"
    ssh "$NIXOS_USER@$NIXOS_HOST" "ss -tlnp | grep LISTEN" | head -10 || true
}

check_deployment_status() {
    log_info "Checking deployment status..."
    
    if ! test_ssh_connection; then
        log_error "Cannot connect to NixOS server"
        exit 1
    fi
    
    # Check system status
    log_info "System Status:"
    ssh "$NIXOS_USER@$NIXOS_HOST" "uptime && df -h / && free -h"
    
    # Check service status
    log_info "Service Status:"
    ssh "$NIXOS_USER@$NIXOS_HOST" "systemctl status nginx postgresql samba xrdp --no-pager -l" || true
    
    # Check last deployment
    log_info "Last Configuration Change:"
    ssh "$NIXOS_USER@$NIXOS_HOST" "cd $NIXOS_CONFIG_DIR && if [ -d .git ]; then git log -1 --oneline; else echo 'No Git repository found'; fi"
    
    # Check NixOS generation
    log_info "Current NixOS Generation:"
    ssh "$NIXOS_USER@$NIXOS_HOST" "nixos-rebuild list-generations | tail -3"
    
    # Run service verification
    verify_services
}

rollback_configuration() {
    log_info "Rolling back to previous configuration on $NIXOS_HOST..."
    
    if [ "$FORCE" != true ]; then
        log_warning "This will rollback to the previous NixOS generation"
        read -p "Are you sure you want to rollback? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Rollback cancelled"
            exit 0
        fi
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would rollback to previous generation"
        return 0
    fi
    
    # Rollback to previous generation
    if ssh "$NIXOS_USER@$NIXOS_HOST" "sudo nixos-rebuild switch --rollback"; then
        log_success "System rolled back to previous generation"
    else
        log_error "Rollback failed"
        exit 1
    fi
}

sync_git_credentials() {
    log_info "Synchronizing Git credentials and SSH keys..."
    
    local git_sync_script="$LOCAL_CONFIG_DIR/scripts/sync-git-credentials.sh"
    
    if [ ! -f "$git_sync_script" ]; then
        log_error "Git sync script not found: $git_sync_script"
        exit 1
    fi
    
    # Run the Git credentials sync script
    local sync_args=""
    if [ "$DRY_RUN" = true ]; then
        sync_args="--dry-run"
    fi
    if [ "$FORCE" = true ]; then
        sync_args="$sync_args --force"
    fi
    if [ "$VERBOSE" = true ]; then
        sync_args="$sync_args --verbose"
    fi
    
    "$git_sync_script" sync-all --host "$NIXOS_HOST" --user "$NIXOS_USER" $sync_args
}

full_deployment() {
    log_info "Starting full deployment process..."
    
    # Step 1: Validate configuration
    validate_configuration
    
    # Step 2: Sync Git credentials
    sync_git_credentials
    
    # Step 3: Deploy configuration
    deploy_configuration
    
    # Step 4: Rebuild NixOS system
    rebuild_nixos
    
    log_success "Full deployment completed successfully"
}

# Main script logic
case "$COMMAND" in
    setup-ssh)
        check_prerequisites
        setup_ssh_keys
        ;;
    sync-git)
        check_prerequisites
        sync_git_credentials
        ;;
    validate)
        check_prerequisites
        validate_configuration
        ;;
    deploy)
        check_prerequisites
        validate_configuration
        deploy_configuration
        ;;
    deploy-and-rebuild)
        check_prerequisites
        validate_configuration
        deploy_configuration
        rebuild_nixos
        ;;
    full-deploy)
        check_prerequisites
        full_deployment
        ;;
    status)
        check_prerequisites
        check_deployment_status
        ;;
    rollback)
        check_prerequisites
        rollback_configuration
        ;;
    test-connection)
        check_prerequisites
        test_ssh_connection
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