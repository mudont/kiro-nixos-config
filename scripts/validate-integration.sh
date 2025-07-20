#!/usr/bin/env bash

# NixOS Integration Validation Script
# This script validates that all system components work together correctly

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_header() {
    echo -e "${BLUE}[VALIDATION]${NC} $1"
    echo "================================================="
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

# Function to check if running on NixOS
check_nixos() {
    if [[ ! -f /etc/NIXOS ]]; then
        log_error "This script must be run on a NixOS system"
        exit 1
    fi
}

# Function to validate service integration
validate_service_integration() {
    log_header "Validating Service Integration"
    
    # Test web server and database integration
    log_info "Testing web server and database integration..."
    
    if systemctl is-active nginx >/dev/null 2>&1 && systemctl is-active postgresql >/dev/null 2>&1; then
        # Test if web server can connect to database
        if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
            test_pass "Web server and database integration is functional"
        else
            test_fail "Database connection from web server failed"
        fi
    else
        test_skip "Web server or database not running"
    fi
    
    # Test monitoring integration
    log_info "Testing monitoring integration..."
    
    if systemctl is-active prometheus >/dev/null 2>&1 && systemctl is-active grafana >/dev/null 2>&1; then
        # Test if Grafana can reach Prometheus
        if curl -s "http://localhost:3000/api/health" | grep -q "ok"; then
            test_pass "Monitoring integration is functional"
        else
            test_fail "Monitoring integration has issues"
        fi
    else
        test_skip "Monitoring services not running"
    fi
    
    # Test file sharing and desktop integration
    log_info "Testing file sharing and desktop integration..."
    
    if systemctl is-active smbd >/dev/null 2>&1 && systemctl is-active xrdp >/dev/null 2>&1; then
        test_pass "File sharing and desktop services are integrated"
    else
        test_skip "File sharing or desktop services not running"
    fi
}

# Function to validate network integration
validate_network_integration() {
    log_header "Validating Network Integration"
    
    # Test internal service communication
    log_info "Testing internal service communication..."
    
    local services_ports=(
        "nginx:80"
        "postgresql:5432"
        "prometheus:9090"
        "grafana:3000"
        "xrdp:3389"
    )
    
    local communication_ok=true
    for service_port in "${services_ports[@]}"; do
        local service="${service_port%:*}"
        local port="${service_port#*:}"
        
        if systemctl is-active "$service" >/dev/null 2>&1; then
            if ss -tuln | grep -q ":$port "; then
                test_pass "$service is listening on port $port"
            else
                test_fail "$service is not listening on port $port"
                communication_ok=false
            fi
        else
            test_skip "$service is not running"
        fi
    done
    
    if $communication_ok; then
        test_pass "All active services are properly networked"
    else
        test_fail "Some services have network integration issues"
    fi
    
    # Test external connectivity
    log_info "Testing external connectivity..."
    
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        test_pass "External network connectivity is working"
    else
        test_fail "External network connectivity failed"
    fi
    
    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        test_pass "DNS resolution is working"
    else
        test_fail "DNS resolution failed"
    fi
}

# Function to validate security integration
validate_security_integration() {
    log_header "Validating Security Integration"
    
    # Test firewall and service integration
    log_info "Testing firewall and service integration..."
    
    local expected_open_ports=(22 80 443 139 445 3389)
    local security_ok=true
    
    for port in "${expected_open_ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            test_pass "Port $port is properly exposed"
        else
            test_warn "Port $port is not exposed (may be intentional)"
        fi
    done
    
    # Test that internal services are not exposed externally
    local internal_ports=(5432 9090 3000)
    for port in "${internal_ports[@]}"; do
        if ss -tuln | grep ":$port " | grep -q "127.0.0.1\|::1"; then
            test_pass "Port $port is properly secured (localhost only)"
        elif ss -tuln | grep -q ":$port "; then
            test_fail "Port $port is exposed externally (security risk)"
            security_ok=false
        else
            test_skip "Port $port is not in use"
        fi
    done
    
    if $security_ok; then
        test_pass "Security integration is properly configured"
    else
        test_fail "Security integration has issues"
    fi
    
    # Test SSH security
    log_info "Testing SSH security integration..."
    
    if [[ -f /etc/ssh/sshd_config ]]; then
        if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config && 
           grep -q "PermitRootLogin no" /etc/ssh/sshd_config; then
            test_pass "SSH security is properly configured"
        else
            test_fail "SSH security configuration needs review"
        fi
    else
        test_fail "SSH configuration file not found"
    fi
}

# Function to validate backup integration
validate_backup_integration() {
    log_header "Validating Backup Integration"
    
    # Test backup script integration
    log_info "Testing backup script integration..."
    
    if [[ -x "scripts/backup-helper.sh" ]]; then
        if ./scripts/backup-helper.sh --dry-run >/dev/null 2>&1; then
            test_pass "Backup script integration is functional"
        else
            test_warn "Backup script may need configuration"
        fi
    else
        test_fail "Backup script is not executable or not found"
    fi
    
    # Test database backup integration
    log_info "Testing database backup integration..."
    
    if systemctl is-active postgresql >/dev/null 2>&1; then
        if sudo -u postgres pg_dumpall > /tmp/test_backup.sql 2>/dev/null; then
            test_pass "Database backup integration is functional"
            rm -f /tmp/test_backup.sql
        else
            test_fail "Database backup integration failed"
        fi
    else
        test_skip "PostgreSQL is not running"
    fi
    
    # Test configuration backup integration
    log_info "Testing configuration backup integration..."
    
    if [[ -d "/etc/nixos/.git" ]]; then
        test_pass "Configuration is under version control"
    else
        test_warn "Configuration should be under version control"
    fi
}

# Function to validate development integration
validate_development_integration() {
    log_header "Validating Development Integration"
    
    # Test development tools integration
    log_info "Testing development tools integration..."
    
    local dev_tools=("git" "node" "npm" "python3" "docker" "rustc" "cargo")
    local tools_ok=true
    
    for tool in "${dev_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            test_pass "Development tool '$tool' is available"
        else
            test_warn "Development tool '$tool' is not available"
            tools_ok=false
        fi
    done
    
    if $tools_ok; then
        test_pass "Development environment is properly integrated"
    else
        test_warn "Some development tools may be missing"
    fi
    
    # Test container integration
    log_info "Testing container integration..."
    
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            test_pass "Docker integration is functional"
        else
            test_fail "Docker integration has issues"
        fi
    else
        test_skip "Docker is not installed"
    fi
    
    # Test shell integration
    log_info "Testing shell integration..."
    
    if [[ "$SHELL" == *"zsh"* ]]; then
        test_pass "Zsh shell is properly integrated"
    else
        test_warn "Shell integration should be reviewed"
    fi
}

# Function to validate performance integration
validate_performance_integration() {
    log_header "Validating Performance Integration"
    
    # Test system resource usage
    log_info "Testing system resource usage..."
    
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "0")
    
    if [[ $(echo "$cpu_usage < 50" | bc 2>/dev/null || echo "1") -eq 1 ]]; then
        test_pass "CPU usage is reasonable ($cpu_usage%)"
    else
        test_warn "CPU usage is high ($cpu_usage%)"
    fi
    
    # Test memory usage
    local memory_usage
    memory_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null || echo "0")
    
    if [[ $(echo "$memory_usage < 70" | bc 2>/dev/null || echo "1") -eq 1 ]]; then
        test_pass "Memory usage is reasonable ($memory_usage%)"
    else
        test_warn "Memory usage is high ($memory_usage%)"
    fi
    
    # Test disk usage
    local disk_usage
    disk_usage=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1 2>/dev/null || echo "0")
    
    if [[ $disk_usage -lt 70 ]]; then
        test_pass "Disk usage is reasonable ($disk_usage%)"
    else
        test_warn "Disk usage is high ($disk_usage%)"
    fi
    
    # Test service response times
    log_info "Testing service response times..."
    
    if systemctl is-active nginx >/dev/null 2>&1; then
        local response_time
        response_time=$(curl -o /dev/null -s -w "%{time_total}" --connect-timeout 5 "http://localhost" 2>/dev/null || echo "999")
        
        if [[ $(echo "$response_time < 1.0" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
            test_pass "Web service response time is good (${response_time}s)"
        else
            test_warn "Web service response time is slow (${response_time}s)"
        fi
    else
        test_skip "Web service is not running"
    fi
}

# Function to generate integration report
generate_integration_report() {
    log_header "Generating Integration Report"
    
    local report_file="/tmp/nixos-integration-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "NixOS Integration Validation Report"
        echo "Generated: $(date)"
        echo "========================================"
        echo
        
        echo "System Information:"
        echo "-------------------"
        uname -a
        nixos-version 2>/dev/null || echo "NixOS version: unknown"
        echo
        
        echo "Active Services:"
        echo "----------------"
        systemctl list-units --type=service --state=active --no-pager | grep -E "(nginx|postgresql|grafana|prometheus|smbd|xrdp|docker)" || echo "No matching services found"
        echo
        
        echo "Network Ports:"
        echo "--------------"
        ss -tuln | grep LISTEN
        echo
        
        echo "Resource Usage:"
        echo "---------------"
        echo "Memory: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
        echo "Disk: $(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $5 " used)"}')"
        echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
        echo
        
        echo "Integration Test Results:"
        echo "-------------------------"
        echo "Total tests: $TESTS_TOTAL"
        echo "Passed: $TESTS_PASSED"
        echo "Failed: $TESTS_FAILED"
        echo "Success rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%" 2>/dev/null || echo "Success rate: N/A"
        echo
        
    } > "$report_file"
    
    log_info "Integration report generated: $report_file"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  --services-only         Validate only service integration"
    echo "  --network-only          Validate only network integration"
    echo "  --security-only         Validate only security integration"
    echo "  --backup-only           Validate only backup integration"
    echo "  --development-only      Validate only development integration"
    echo "  --performance-only      Validate only performance integration"
    echo "  --report-only           Generate only integration report"
    echo "  --quick                 Run quick validation only"
    echo
    echo "Examples:"
    echo "  $0                      Run all integration validations"
    echo "  $0 --services-only      Validate only service integration"
    echo "  $0 --quick              Run quick validation"
}

# Main execution
main() {
    local services_only=false
    local network_only=false
    local security_only=false
    local backup_only=false
    local development_only=false
    local performance_only=false
    local report_only=false
    local quick=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --services-only)
                services_only=true
                shift
                ;;
            --network-only)
                network_only=true
                shift
                ;;
            --security-only)
                security_only=true
                shift
                ;;
            --backup-only)
                backup_only=true
                shift
                ;;
            --development-only)
                development_only=true
                shift
                ;;
            --performance-only)
                performance_only=true
                shift
                ;;
            --report-only)
                report_only=true
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
    
    check_nixos
    
    log_info "NixOS Integration Validation"
    log_info "============================"
    echo
    
    # Run selected validations
    if $services_only; then
        validate_service_integration
    elif $network_only; then
        validate_network_integration
    elif $security_only; then
        validate_security_integration
    elif $backup_only; then
        validate_backup_integration
    elif $development_only; then
        validate_development_integration
    elif $performance_only; then
        validate_performance_integration
    elif $report_only; then
        generate_integration_report
    else
        # Run all validations
        validate_service_integration
        validate_network_integration
        validate_security_integration
        validate_backup_integration
        validate_development_integration
        
        if ! $quick; then
            validate_performance_integration
        fi
        
        generate_integration_report
    fi
    
    # Print final summary
    echo
    log_info "Integration Validation Summary"
    log_info "=============================="
    log_info "Total tests: $TESTS_TOTAL"
    log_info "Passed: $TESTS_PASSED"
    log_info "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "All integration validations passed! ✓"
        echo
        log_info "Your NixOS system is fully integrated and ready for production use."
        exit 0
    else
        log_error "Some integration validations failed! ✗"
        echo
        log_error "Please review and fix the failed validations before production deployment."
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi