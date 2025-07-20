#!/usr/bin/env bash

# NixOS Service Startup Testing
# This script tests that all configured services start properly

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

# Test service status
test_service_status() {
    local service_name="$1"
    local service_description="$2"
    
    if systemctl is-enabled "$service_name" &>/dev/null; then
        if systemctl is-active "$service_name" &>/dev/null; then
            test_pass "$service_description is running"
        else
            test_fail "$service_description is enabled but not running"
            systemctl status "$service_name" --no-pager -l | head -10
        fi
    else
        test_skip "$service_description is not enabled"
    fi
}

# Test service can be started (if not already running)
test_service_start() {
    local service_name="$1"
    local service_description="$2"
    
    if systemctl is-enabled "$service_name" &>/dev/null; then
        if ! systemctl is-active "$service_name" &>/dev/null; then
            log_info "Attempting to start $service_description..."
            if sudo systemctl start "$service_name" 2>/dev/null; then
                sleep 2
                if systemctl is-active "$service_name" &>/dev/null; then
                    test_pass "$service_description can be started successfully"
                    # Stop it again to restore original state
                    sudo systemctl stop "$service_name" 2>/dev/null || true
                else
                    test_fail "$service_description failed to start properly"
                fi
            else
                test_fail "$service_description failed to start"
            fi
        else
            test_pass "$service_description is already running"
        fi
    else
        test_skip "$service_description is not enabled"
    fi
}

# Test port availability for services
test_service_port() {
    local port="$1"
    local service_description="$2"
    local protocol="${3:-tcp}"
    
    if ss -tuln | grep -q ":$port "; then
        test_pass "$service_description is listening on port $port"
    else
        test_fail "$service_description is not listening on port $port"
    fi
}

# Test SSH service
test_ssh_service() {
    log_info "Testing SSH service..."
    test_service_status "sshd" "SSH daemon"
    test_service_port "22" "SSH service"
    
    # Test SSH configuration
    if [[ -f /etc/ssh/sshd_config ]]; then
        if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
            test_pass "SSH password authentication is disabled"
        else
            test_fail "SSH password authentication should be disabled"
        fi
        
        if grep -q "PermitRootLogin no" /etc/ssh/sshd_config; then
            test_pass "SSH root login is disabled"
        else
            test_fail "SSH root login should be disabled"
        fi
    else
        test_fail "SSH configuration file not found"
    fi
}

# Test web services
test_web_services() {
    log_info "Testing web services..."
    test_service_status "nginx" "Nginx web server"
    test_service_port "80" "HTTP service"
    test_service_port "443" "HTTPS service"
    
    # Test if nginx configuration is valid
    if command -v nginx >/dev/null 2>&1; then
        if sudo nginx -t 2>/dev/null; then
            test_pass "Nginx configuration is valid"
        else
            test_fail "Nginx configuration has errors"
        fi
    else
        test_skip "Nginx not installed"
    fi
}

# Test database services
test_database_services() {
    log_info "Testing database services..."
    test_service_status "postgresql" "PostgreSQL database"
    test_service_port "5432" "PostgreSQL service"
    
    # Test PostgreSQL connection
    if command -v psql >/dev/null 2>&1; then
        if sudo -u postgres psql -c "SELECT version();" >/dev/null 2>&1; then
            test_pass "PostgreSQL accepts connections"
        else
            test_fail "PostgreSQL connection failed"
        fi
    else
        test_skip "PostgreSQL client not available"
    fi
}

# Test file sharing services
test_file_sharing() {
    log_info "Testing file sharing services..."
    test_service_status "smbd" "Samba SMB daemon"
    test_service_status "nmbd" "Samba NetBIOS daemon"
    test_service_port "139" "NetBIOS service"
    test_service_port "445" "SMB service"
    
    # Test Samba configuration
    if command -v testparm >/dev/null 2>&1; then
        if testparm -s >/dev/null 2>&1; then
            test_pass "Samba configuration is valid"
        else
            test_fail "Samba configuration has errors"
        fi
    else
        test_skip "Samba testparm not available"
    fi
}

# Test remote desktop services
test_remote_desktop() {
    log_info "Testing remote desktop services..."
    test_service_status "xrdp" "XRDP remote desktop"
    test_service_port "3389" "RDP service"
    
    # Test display manager
    if systemctl is-enabled "display-manager" &>/dev/null; then
        test_service_status "display-manager" "Display manager"
    else
        test_skip "Display manager not configured"
    fi
}

# Test monitoring services
test_monitoring_services() {
    log_info "Testing monitoring services..."
    test_service_status "prometheus" "Prometheus monitoring"
    test_service_status "grafana" "Grafana dashboard"
    test_service_port "9090" "Prometheus service"
    test_service_port "3000" "Grafana service"
    
    # Test if Prometheus config is valid
    if command -v promtool >/dev/null 2>&1; then
        local prom_config="/etc/prometheus/prometheus.yml"
        if [[ -f "$prom_config" ]]; then
            if promtool check config "$prom_config" >/dev/null 2>&1; then
                test_pass "Prometheus configuration is valid"
            else
                test_fail "Prometheus configuration has errors"
            fi
        else
            test_skip "Prometheus configuration file not found"
        fi
    else
        test_skip "Prometheus tools not available"
    fi
}

# Test container services
test_container_services() {
    log_info "Testing container services..."
    test_service_status "docker" "Docker daemon"
    
    # Test Docker functionality
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            test_pass "Docker daemon is accessible"
        else
            test_fail "Docker daemon is not accessible"
        fi
    else
        test_skip "Docker not installed"
    fi
    
    # Test Podman
    if command -v podman >/dev/null 2>&1; then
        if podman info >/dev/null 2>&1; then
            test_pass "Podman is functional"
        else
            test_fail "Podman is not functional"
        fi
    else
        test_skip "Podman not installed"
    fi
}

# Test firewall status
test_firewall() {
    log_info "Testing firewall configuration..."
    
    if systemctl is-active "firewall" &>/dev/null; then
        test_pass "Firewall is active"
    else
        test_fail "Firewall is not active"
    fi
    
    # Check if iptables has rules
    if command -v iptables >/dev/null 2>&1; then
        local rule_count=$(sudo iptables -L | wc -l)
        if [[ $rule_count -gt 10 ]]; then
            test_pass "Firewall rules are configured"
        else
            test_fail "Firewall appears to have minimal rules"
        fi
    else
        test_skip "iptables not available"
    fi
}

# Main execution
main() {
    log_info "Starting NixOS Service Testing"
    log_info "=============================="
    
    check_nixos
    
    # Run all service tests
    test_ssh_service
    test_web_services
    test_database_services
    test_file_sharing
    test_remote_desktop
    test_monitoring_services
    test_container_services
    test_firewall
    
    # Print summary
    echo
    log_info "Service Test Summary"
    log_info "==================="
    log_info "Total tests: $TESTS_TOTAL"
    log_info "Passed: $TESTS_PASSED"
    log_info "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "All service tests passed! ✓"
        exit 0
    else
        log_error "Some service tests failed! ✗"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi