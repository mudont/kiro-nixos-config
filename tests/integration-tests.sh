#!/usr/bin/env bash

# NixOS Integration Testing
# This script tests end-to-end functionality from macOS to NixOS server

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NIXOS_HOST="${NIXOS_HOST:-nixos}"
NIXOS_USER="${NIXOS_USER:-murali}"
TEST_TIMEOUT=30

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Test result functions
test_pass() {
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
    log_info "✓ $1"
}

test_fail() {
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
    log_error "✗ $1"
}

test_skip() {
    ((TESTS_TOTAL++))
    log_warn "⚠ $1 (SKIPPED)"
}

# Function to check if we're on macOS
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "Integration tests are designed to run from macOS"
        exit 1
    fi
}

# Function to test SSH connectivity
test_ssh_connection() {
    log_header "Testing SSH connection to NixOS server"
    
    # Test basic SSH connectivity
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "echo 'SSH connection successful'" 2>/dev/null; then
        test_pass "SSH connection to $NIXOS_HOST successful"
    else
        test_fail "SSH connection to $NIXOS_HOST failed"
        log_error "Make sure SSH keys are set up and the server is accessible"
        return 1
    fi
    
    # Test SSH key authentication (no password prompt)
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no "$NIXOS_USER@$NIXOS_HOST" "whoami" 2>/dev/null | grep -q "$NIXOS_USER"; then
        test_pass "SSH key-based authentication working"
    else
        test_fail "SSH key-based authentication failed"
    fi
    
    # Test sudo access (if configured)
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "sudo -n whoami" 2>/dev/null | grep -q "root"; then
        test_pass "Passwordless sudo access working"
    else
        test_warn "Passwordless sudo access not configured (may be intentional)"
    fi
}

# Function to test remote desktop connectivity
test_remote_desktop() {
    log_header "Testing remote desktop connectivity"
    
    # Test RDP port accessibility
    if nc -z -w5 "$NIXOS_HOST" 3389 2>/dev/null; then
        test_pass "RDP port (3389) is accessible"
    else
        test_fail "RDP port (3389) is not accessible"
        return 1
    fi
    
    # Test XRDP service status via SSH
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "systemctl is-active xrdp" 2>/dev/null | grep -q "active"; then
        test_pass "XRDP service is running on remote server"
    else
        test_fail "XRDP service is not running on remote server"
    fi
    
    # Test desktop environment availability
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "which startxfce4" 2>/dev/null | grep -q "startxfce4"; then
        test_pass "XFCE desktop environment is available"
    else
        test_warn "XFCE desktop environment may not be properly installed"
    fi
    
    # Provide manual test instructions
    log_info "Manual RDP test: Open 'Microsoft Remote Desktop' and connect to $NIXOS_HOST"
    log_info "Expected: Should connect successfully and show XFCE desktop"
}

# Function to test file sharing (Samba)
test_file_sharing() {
    log_header "Testing file sharing (Samba) connectivity"
    
    # Test SMB ports accessibility
    local smb_ports=(139 445)
    for port in "${smb_ports[@]}"; do
        if nc -z -w5 "$NIXOS_HOST" "$port" 2>/dev/null; then
            test_pass "SMB port ($port) is accessible"
        else
            test_fail "SMB port ($port) is not accessible"
        fi
    done
    
    # Test Samba service status via SSH
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "systemctl is-active smbd" 2>/dev/null | grep -q "active"; then
        test_pass "Samba SMB daemon is running"
    else
        test_fail "Samba SMB daemon is not running"
    fi
    
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "systemctl is-active nmbd" 2>/dev/null | grep -q "active"; then
        test_pass "Samba NetBIOS daemon is running"
    else
        test_fail "Samba NetBIOS daemon is not running"
    fi
    
    # Test SMB share accessibility using smbclient (if available)
    if command -v smbclient >/dev/null 2>&1; then
        if timeout $TEST_TIMEOUT smbclient -L "//$NIXOS_HOST" -N 2>/dev/null | grep -q "Sharename"; then
            test_pass "SMB shares are accessible via smbclient"
        else
            test_warn "SMB shares may not be accessible (authentication may be required)"
        fi
    else
        test_skip "smbclient not available for testing"
    fi
    
    # Test macOS SMB connectivity
    log_info "Manual SMB test: In Finder, press Cmd+K and connect to smb://$NIXOS_HOST"
    log_info "Expected: Should show available shares and allow file access"
    
    # Test iOS connectivity instructions
    log_info "iOS file sharing test:"
    log_info "1. Open Files app on iPhone"
    log_info "2. Tap '...' -> 'Connect to Server'"
    log_info "3. Enter: smb://$NIXOS_HOST"
    log_info "4. Enter credentials when prompted"
    log_info "Expected: Should connect and show shared folders"
}

# Function to test web services
test_web_services() {
    log_header "Testing web services"
    
    # Test HTTP port accessibility
    if nc -z -w5 "$NIXOS_HOST" 80 2>/dev/null; then
        test_pass "HTTP port (80) is accessible"
    else
        test_fail "HTTP port (80) is not accessible"
    fi
    
    # Test HTTPS port accessibility
    if nc -z -w5 "$NIXOS_HOST" 443 2>/dev/null; then
        test_pass "HTTPS port (443) is accessible"
    else
        test_fail "HTTPS port (443) is not accessible"
    fi
    
    # Test Nginx service status via SSH
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "systemctl is-active nginx" 2>/dev/null | grep -q "active"; then
        test_pass "Nginx web server is running"
    else
        test_fail "Nginx web server is not running"
    fi
    
    # Test HTTP response
    if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://$NIXOS_HOST" | grep -q "200\|301\|302"; then
        test_pass "HTTP service responds correctly"
    else
        test_warn "HTTP service may not be responding (check server configuration)"
    fi
    
    # Test HTTPS response (if SSL is configured)
    if curl -s -k -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://$NIXOS_HOST" | grep -q "200\|301\|302"; then
        test_pass "HTTPS service responds correctly"
    else
        test_warn "HTTPS service may not be configured or responding"
    fi
    
    # Test specific web applications (if configured)
    local web_apps=("grafana:3000" "prometheus:9090")
    for app in "${web_apps[@]}"; do
        local app_name="${app%:*}"
        local app_port="${app#*:}"
        
        if nc -z -w5 "$NIXOS_HOST" "$app_port" 2>/dev/null; then
            test_pass "$app_name web interface is accessible on port $app_port"
        else
            test_warn "$app_name web interface may not be running on port $app_port"
        fi
    done
}

# Function to test database connectivity
test_database_services() {
    log_header "Testing database services"
    
    # Test PostgreSQL service via SSH
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "systemctl is-active postgresql" 2>/dev/null | grep -q "active"; then
        test_pass "PostgreSQL service is running"
    else
        test_fail "PostgreSQL service is not running"
    fi
    
    # Test PostgreSQL connectivity (should be localhost only)
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "sudo -u postgres psql -c 'SELECT version();'" 2>/dev/null | grep -q "PostgreSQL"; then
        test_pass "PostgreSQL accepts local connections"
    else
        test_fail "PostgreSQL local connection failed"
    fi
    
    # Verify PostgreSQL is NOT accessible externally (security test)
    if ! nc -z -w5 "$NIXOS_HOST" 5432 2>/dev/null; then
        test_pass "PostgreSQL is properly secured (not accessible externally)"
    else
        test_fail "PostgreSQL is accessible externally (security risk)"
    fi
}

# Function to test development environment
test_development_environment() {
    log_header "Testing development environment"
    
    # Test development tools availability
    local dev_tools=("node" "npm" "java" "python3" "git" "docker" "rustc" "cargo")
    for tool in "${dev_tools[@]}"; do
        if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "which $tool" 2>/dev/null | grep -q "$tool"; then
            test_pass "Development tool '$tool' is available"
        else
            test_warn "Development tool '$tool' may not be installed"
        fi
    done
    
    # Test container functionality
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "docker info" 2>/dev/null | grep -q "Server Version"; then
        test_pass "Docker is functional"
    else
        test_warn "Docker may not be properly configured"
    fi
    
    # Test shell environment
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "echo \$SHELL" 2>/dev/null | grep -q "zsh"; then
        test_pass "Zsh shell is configured"
    else
        test_warn "Zsh shell may not be the default"
    fi
}

# Function to test backup functionality
test_backup_functionality() {
    log_header "Testing backup functionality"
    
    # Test backup script existence
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "test -x /home/$NIXOS_USER/scripts/backup-helper.sh" 2>/dev/null; then
        test_pass "Backup script is available and executable"
    else
        test_warn "Backup script may not be properly installed"
    fi
    
    # Test backup directories
    local backup_dirs=("/srv/backup" "/var/backup")
    for backup_dir in "${backup_dirs[@]}"; do
        if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "test -d $backup_dir" 2>/dev/null; then
            test_pass "Backup directory $backup_dir exists"
        else
            test_warn "Backup directory $backup_dir may not exist"
        fi
    done
    
    # Test rsync availability for Mac backup
    if timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "which rsync" 2>/dev/null | grep -q "rsync"; then
        test_pass "Rsync is available for backup operations"
    else
        test_fail "Rsync is not available for backup operations"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Environment Variables:"
    echo "  NIXOS_HOST    NixOS server hostname or IP (default: nixos)"
    echo "  NIXOS_USER    Username for SSH connection (default: murali)"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  --ssh-only              Test only SSH connectivity"
    echo "  --rdp-only              Test only remote desktop"
    echo "  --smb-only              Test only file sharing"
    echo "  --web-only              Test only web services"
    echo "  --quick                 Run quick tests only (skip manual test instructions)"
    echo
    echo "Examples:"
    echo "  $0                      Run all integration tests"
    echo "  NIXOS_HOST=192.168.1.100 $0  Test specific IP address"
    echo "  $0 --ssh-only           Test only SSH connectivity"
}

# Main execution
main() {
    local ssh_only=false
    local rdp_only=false
    local smb_only=false
    local web_only=false
    local quick=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --ssh-only)
                ssh_only=true
                shift
                ;;
            --rdp-only)
                rdp_only=true
                shift
                ;;
            --smb-only)
                smb_only=true
                shift
                ;;
            --web-only)
                web_only=true
                shift
                ;;
            --quick)
                quick=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    check_macos
    
    log_info "NixOS Integration Testing from macOS"
    log_info "===================================="
    log_info "Target server: $NIXOS_HOST"
    log_info "Target user: $NIXOS_USER"
    echo
    
    # Run selected tests
    if $ssh_only; then
        test_ssh_connection
    elif $rdp_only; then
        test_ssh_connection && test_remote_desktop
    elif $smb_only; then
        test_ssh_connection && test_file_sharing
    elif $web_only; then
        test_ssh_connection && test_web_services
    else
        # Run all tests
        test_ssh_connection
        test_remote_desktop
        test_file_sharing
        test_web_services
        test_database_services
        test_development_environment
        test_backup_functionality
    fi
    
    # Print summary
    echo
    log_info "Integration Test Summary"
    log_info "======================="
    log_info "Total tests: $TESTS_TOTAL"
    log_info "Passed: $TESTS_PASSED"
    log_info "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "All integration tests passed! ✓"
        echo
        if ! $quick; then
            log_info "Manual testing recommendations:"
            log_info "1. Test RDP connection using Microsoft Remote Desktop"
            log_info "2. Test file sharing from macOS Finder (Cmd+K -> smb://$NIXOS_HOST)"
            log_info "3. Test file sharing from iPhone Files app"
            log_info "4. Test web interfaces in browser (http://$NIXOS_HOST)"
        fi
        exit 0
    else
        log_error "Some integration tests failed! ✗"
        echo
        log_error "Please fix the failed tests before considering the system ready for use."
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi