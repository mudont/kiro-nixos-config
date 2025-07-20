#!/usr/bin/env bash

# NixOS Network Connectivity and Security Testing
# This script tests network configuration and security settings

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Check if running on NixOS
check_nixos() {
    if [[ ! -f /etc/NIXOS ]]; then
        log_error "This script must be run on a NixOS system"
        exit 1
    fi
}

# Test network connectivity
test_network_connectivity() {
    log_info "Testing network connectivity..."
    
    # Test internet connectivity
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        test_pass "Internet connectivity (IPv4) is working"
    else
        test_fail "No internet connectivity (IPv4)"
    fi
    
    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        test_pass "DNS resolution is working"
    else
        test_fail "DNS resolution failed"
    fi
    
    # Test local network interface
    if ip addr show | grep -q "inet.*scope global"; then
        test_pass "Network interface has IP address"
    else
        test_fail "No network interface with IP address found"
    fi
}

# Test firewall configuration
test_firewall_config() {
    log_info "Testing firewall configuration..."
    
    # Check if firewall is enabled
    if systemctl is-active firewall >/dev/null 2>&1 || systemctl is-active iptables >/dev/null 2>&1; then
        test_pass "Firewall service is active"
    else
        test_fail "No firewall service is active"
    fi
    
    # Test specific port accessibility
    local expected_ports=(22 80 443 139 445 3389)
    local listening_ports
    listening_ports=$(ss -tuln | awk '{print $5}' | grep -o ':[0-9]*$' | cut -d: -f2 | sort -n | uniq)
    
    for port in "${expected_ports[@]}"; do
        if echo "$listening_ports" | grep -q "^$port$"; then
            test_pass "Port $port is listening as expected"
        else
            test_warn "Port $port is not listening (may be intentional)"
        fi
    done
    
    # Check for unexpected open ports
    local unexpected_ports=()
    while IFS= read -r port; do
        if [[ -n "$port" ]] && [[ ! " ${expected_ports[*]} " =~ " ${port} " ]]; then
            # Skip common system ports
            case "$port" in
                53|68|123|631|5353) ;; # DNS, DHCP, NTP, CUPS, mDNS
                *) unexpected_ports+=("$port") ;;
            esac
        fi
    done <<< "$listening_ports"
    
    if [[ ${#unexpected_ports[@]} -eq 0 ]]; then
        test_pass "No unexpected ports are listening"
    else
        test_warn "Unexpected ports listening: ${unexpected_ports[*]}"
    fi
}

# Test SSH security configuration
test_ssh_security() {
    log_info "Testing SSH security configuration..."
    
    local ssh_config="/etc/ssh/sshd_config"
    if [[ ! -f "$ssh_config" ]]; then
        test_fail "SSH configuration file not found"
        return
    fi
    
    # Test password authentication disabled
    if grep -q "^PasswordAuthentication no" "$ssh_config"; then
        test_pass "SSH password authentication is disabled"
    else
        test_fail "SSH password authentication should be disabled"
    fi
    
    # Test root login disabled
    if grep -q "^PermitRootLogin no" "$ssh_config"; then
        test_pass "SSH root login is disabled"
    else
        test_fail "SSH root login should be disabled"
    fi
    
    # Test key-based authentication enabled
    if grep -q "^PubkeyAuthentication yes" "$ssh_config" || ! grep -q "^PubkeyAuthentication no" "$ssh_config"; then
        test_pass "SSH public key authentication is enabled"
    else
        test_fail "SSH public key authentication should be enabled"
    fi
    
    # Test SSH protocol version
    if ! grep -q "^Protocol 1" "$ssh_config"; then
        test_pass "SSH is not using insecure Protocol 1"
    else
        test_fail "SSH should not use Protocol 1"
    fi
}

# Test SSL/TLS configuration
test_ssl_config() {
    log_info "Testing SSL/TLS configuration..."
    
    # Check if SSL certificates exist
    local cert_dirs=("/etc/ssl/certs" "/var/lib/acme" "/etc/letsencrypt")
    local cert_found=false
    
    for cert_dir in "${cert_dirs[@]}"; do
        if [[ -d "$cert_dir" ]] && find "$cert_dir" -name "*.crt" -o -name "*.pem" | grep -q .; then
            cert_found=true
            break
        fi
    done
    
    if $cert_found; then
        test_pass "SSL certificates found"
    else
        test_warn "No SSL certificates found (may be intentional for development)"
    fi
    
    # Test HTTPS redirect (if nginx is running)
    if systemctl is-active nginx >/dev/null 2>&1; then
        if curl -s -I http://localhost | grep -q "301\|302"; then
            test_pass "HTTP to HTTPS redirect is configured"
        else
            test_warn "HTTP to HTTPS redirect may not be configured"
        fi
    else
        test_skip "Nginx not running, skipping HTTPS redirect test"
    fi
}

# Test file sharing security
test_file_sharing_security() {
    log_info "Testing file sharing security..."
    
    # Test Samba configuration security
    if command -v testparm >/dev/null 2>&1; then
        local samba_config
        samba_config=$(testparm -s 2>/dev/null)
        
        if echo "$samba_config" | grep -q "security = user"; then
            test_pass "Samba is using user-level security"
        else
            test_warn "Samba security level should be reviewed"
        fi
        
        if echo "$samba_config" | grep -q "encrypt passwords = yes"; then
            test_pass "Samba password encryption is enabled"
        else
            test_warn "Samba password encryption should be enabled"
        fi
        
        # Check for guest access
        if echo "$samba_config" | grep -q "guest ok = no"; then
            test_pass "Samba guest access is properly restricted"
        else
            test_warn "Samba guest access configuration should be reviewed"
        fi
    else
        test_skip "Samba not available for security testing"
    fi
}

# Test system security settings
test_system_security() {
    log_info "Testing system security settings..."
    
    # Test if fail2ban is running
    if systemctl is-active fail2ban >/dev/null 2>&1; then
        test_pass "Fail2ban is active for intrusion prevention"
    else
        test_warn "Fail2ban is not active (consider enabling for production)"
    fi
    
    # Test kernel security features
    if grep -q "nx" /proc/cpuinfo && [[ -f /proc/sys/kernel/exec-shield ]] || grep -q "smep\|smap" /proc/cpuinfo; then
        test_pass "Hardware security features are available"
    else
        test_warn "Some hardware security features may not be available"
    fi
    
    # Test if core dumps are disabled
    if ulimit -c | grep -q "0"; then
        test_pass "Core dumps are disabled"
    else
        test_warn "Core dumps should be disabled for security"
    fi
    
    # Test file permissions on sensitive files
    local sensitive_files=("/etc/shadow" "/etc/ssh/ssh_host_*_key")
    for file_pattern in "${sensitive_files[@]}"; do
        for file in $file_pattern; do
            if [[ -f "$file" ]]; then
                local perms
                perms=$(stat -c "%a" "$file")
                if [[ "$perms" =~ ^[0-7]00$ ]]; then
                    test_pass "File $file has secure permissions ($perms)"
                else
                    test_fail "File $file has insecure permissions ($perms)"
                fi
            fi
        done
    done
}

# Test network service isolation
test_service_isolation() {
    log_info "Testing service isolation..."
    
    # Test PostgreSQL is only listening on localhost
    if ss -tuln | grep ":5432" | grep -q "127.0.0.1\|::1"; then
        test_pass "PostgreSQL is only listening on localhost"
    elif ss -tuln | grep -q ":5432"; then
        test_fail "PostgreSQL is listening on external interfaces"
    else
        test_skip "PostgreSQL is not running"
    fi
    
    # Test that services are running as non-root users
    local services=("nginx" "postgres" "smbd")
    for service in "${services[@]}"; do
        if pgrep "$service" >/dev/null 2>&1; then
            local service_user
            service_user=$(ps -o user= -p "$(pgrep "$service" | head -1)")
            if [[ "$service_user" != "root" ]]; then
                test_pass "Service $service is running as non-root user ($service_user)"
            else
                test_warn "Service $service is running as root (review if necessary)"
            fi
        else
            test_skip "Service $service is not running"
        fi
    done
}

# Test backup security
test_backup_security() {
    log_info "Testing backup security..."
    
    # Check if backup directories have proper permissions
    local backup_dirs=("/srv/backup" "/var/backup" "/home/*/backup")
    for backup_dir_pattern in "${backup_dirs[@]}"; do
        for backup_dir in $backup_dir_pattern; do
            if [[ -d "$backup_dir" ]]; then
                local perms
                perms=$(stat -c "%a" "$backup_dir")
                if [[ "$perms" =~ ^[0-7][0-7][0-5]$ ]]; then
                    test_pass "Backup directory $backup_dir has secure permissions ($perms)"
                else
                    test_warn "Backup directory $backup_dir permissions should be reviewed ($perms)"
                fi
            fi
        done
    done
    
    # Check if backup scripts exist and are executable
    if [[ -f "scripts/backup-helper.sh" ]]; then
        if [[ -x "scripts/backup-helper.sh" ]]; then
            test_pass "Backup script is executable"
        else
            test_fail "Backup script should be executable"
        fi
    else
        test_skip "Backup script not found"
    fi
}

# Main execution
main() {
    log_info "Starting Network Connectivity and Security Testing"
    log_info "================================================="
    
    check_nixos
    
    # Run all tests
    test_network_connectivity
    test_firewall_config
    test_ssh_security
    test_ssl_config
    test_file_sharing_security
    test_system_security
    test_service_isolation
    test_backup_security
    
    # Print summary
    echo
    log_info "Network and Security Test Summary"
    log_info "================================="
    log_info "Total tests: $TESTS_TOTAL"
    log_info "Passed: $TESTS_PASSED"
    log_info "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "All network and security tests passed! ✓"
        exit 0
    else
        log_error "Some network and security tests failed! ✗"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi