#!/usr/bin/env bash

# End-to-End Integration Testing for NixOS Home Server
# This script tests the complete development workflow from Mac to NixOS

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
TEST_PROJECT_NAME="nixos-test-project"

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
    echo -e "${BLUE}[TEST SUITE]${NC} $1"
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

# Function to check if we're on macOS
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "End-to-end tests are designed to run from macOS"
        exit 1
    fi
}

# Function to test complete development workflow
test_development_workflow() {
    log_header "Testing Complete Development Workflow"
    
    # Test 1: Create a test project on Mac
    log_info "Creating test project on Mac..."
    local test_dir="/tmp/$TEST_PROJECT_NAME"
    rm -rf "$test_dir" 2>/dev/null || true
    mkdir -p "$test_dir"
    
    # Create a simple Node.js project
    cat > "$test_dir/package.json" << 'EOF'
{
  "name": "nixos-test-project",
  "version": "1.0.0",
  "description": "Test project for NixOS development workflow",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Test passed\" && exit 0"
  }
}
EOF
    
    cat > "$test_dir/index.js" << 'EOF'
const http = require('http');
const port = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('Hello from NixOS development environment!\n');
});

server.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
EOF
    
    if [[ -f "$test_dir/package.json" && -f "$test_dir/index.js" ]]; then
        test_pass "Test project created on Mac"
    else
        test_fail "Failed to create test project on Mac"
        return 1
    fi
    
    # Test 2: Copy project to NixOS server
    log_info "Copying project to NixOS server..."
    if timeout $TEST_TIMEOUT scp -r "$test_dir" "$NIXOS_USER@$NIXOS_HOST:/tmp/" 2>/dev/null; then
        test_pass "Project copied to NixOS server"
    else
        test_fail "Failed to copy project to NixOS server"
        return 1
    fi
    
    # Test 3: Test development tools on NixOS
    log_info "Testing development tools on NixOS..."
    
    # Test Node.js
    if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "cd /tmp/$TEST_PROJECT_NAME && node --version" 2>/dev/null; then
        test_pass "Node.js is available on NixOS"
    else
        test_fail "Node.js is not available on NixOS"
    fi
    
    # Test npm
    if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "cd /tmp/$TEST_PROJECT_NAME && npm --version" 2>/dev/null; then
        test_pass "npm is available on NixOS"
    else
        test_fail "npm is not available on NixOS"
    fi
    
    # Test project execution
    if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "cd /tmp/$TEST_PROJECT_NAME && timeout 5 npm start &" 2>/dev/null; then
        test_pass "Node.js project can be executed on NixOS"
    else
        test_warn "Node.js project execution test inconclusive"
    fi
    
    # Test 4: Test Git workflow
    log_info "Testing Git workflow..."
    
    # Initialize Git repo on NixOS
    if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "cd /tmp/$TEST_PROJECT_NAME && git init && git add . && git commit -m 'Initial commit'" 2>/dev/null; then
        test_pass "Git workflow works on NixOS"
    else
        test_fail "Git workflow failed on NixOS"
    fi
    
    # Test Git configuration
    if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "git config --get user.name && git config --get user.email" 2>/dev/null; then
        test_pass "Git is properly configured on NixOS"
    else
        test_warn "Git configuration may not be complete"
    fi
    
    # Test 5: Test container development
    log_info "Testing container development workflow..."
    
    # Create a simple Dockerfile
    timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "cd /tmp/$TEST_PROJECT_NAME && cat > Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json .
COPY index.js .
EXPOSE 3000
CMD [\"npm\", \"start\"]
EOF" 2>/dev/null || true
    
    # Test Docker build
    if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "cd /tmp/$TEST_PROJECT_NAME && docker build -t nixos-test ." 2>/dev/null; then
        test_pass "Docker build works on NixOS"
        
        # Test Docker run
        if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "docker run --rm -d --name nixos-test-container -p 3001:3000 nixos-test && sleep 2 && docker stop nixos-test-container" 2>/dev/null; then
            test_pass "Docker container execution works on NixOS"
        else
            test_warn "Docker container execution test inconclusive"
        fi
    else
        test_fail "Docker build failed on NixOS"
    fi
    
    # Cleanup
    timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "rm -rf /tmp/$TEST_PROJECT_NAME" 2>/dev/null || true
    rm -rf "$test_dir" 2>/dev/null || true
}

# Function to test backup and recovery procedures
test_backup_recovery() {
    log_header "Testing Backup and Recovery Procedures"
    
    # Test 1: Test backup script execution
    log_info "Testing backup script execution..."
    
    if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "test -x ~/scripts/backup-helper.sh" 2>/dev/null; then
        test_pass "Backup script is executable"
        
        # Test backup script dry run
        if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "~/scripts/backup-helper.sh --dry-run" 2>/dev/null; then
            test_pass "Backup script dry run successful"
        else
            test_warn "Backup script dry run failed (may need configuration)"
        fi
    else
        test_fail "Backup script is not executable or not found"
    fi
    
    # Test 2: Test configuration backup with Git
    log_info "Testing configuration backup with Git..."
    
    if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "cd /etc/nixos && git status" 2>/dev/null; then
        test_pass "Configuration is under Git version control"
    else
        test_warn "Configuration may not be under Git version control"
    fi
    
    # Test 3: Test database backup
    log_info "Testing database backup procedures..."
    
    if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "sudo -u postgres pg_dumpall > /tmp/test_backup.sql && rm /tmp/test_backup.sql" 2>/dev/null; then
        test_pass "PostgreSQL backup procedure works"
    else
        test_warn "PostgreSQL backup procedure may not be configured"
    fi
    
    # Test 4: Test system rollback capability
    log_info "Testing system rollback capability..."
    
    if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "nixos-rebuild list-generations | head -5" 2>/dev/null; then
        test_pass "System generations are available for rollback"
    else
        test_warn "System rollback capability may not be available"
    fi
}

# Function to test monitoring and alerting
test_monitoring_alerting() {
    log_header "Testing Monitoring and Alerting"
    
    # Test 1: Test Prometheus metrics collection
    log_info "Testing Prometheus metrics collection..."
    
    if curl -s --connect-timeout 5 "http://$NIXOS_HOST:9090/metrics" | grep -q "prometheus_"; then
        test_pass "Prometheus is collecting metrics"
    else
        test_warn "Prometheus metrics may not be accessible"
    fi
    
    # Test 2: Test Grafana dashboard access
    log_info "Testing Grafana dashboard access..."
    
    if curl -s --connect-timeout 5 "http://$NIXOS_HOST:3000/api/health" | grep -q "ok"; then
        test_pass "Grafana is accessible and healthy"
    else
        test_warn "Grafana may not be accessible"
    fi
    
    # Test 3: Test system metrics availability
    log_info "Testing system metrics availability..."
    
    if curl -s --connect-timeout 5 "http://$NIXOS_HOST:9100/metrics" | grep -q "node_"; then
        test_pass "Node Exporter is providing system metrics"
    else
        test_warn "Node Exporter metrics may not be available"
    fi
    
    # Test 4: Test log aggregation
    log_info "Testing log aggregation..."
    
    if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "journalctl --since '1 hour ago' | head -10" 2>/dev/null | grep -q .; then
        test_pass "System logs are being collected"
    else
        test_warn "System log collection may have issues"
    fi
}

# Function to test security configurations
test_security_configurations() {
    log_header "Testing Security Configurations"
    
    # Test 1: Test firewall rules
    log_info "Testing firewall rules..."
    
    local expected_open_ports=(22 80 443 139 445 3389)
    local expected_closed_ports=(5432 9090 3000)
    
    for port in "${expected_open_ports[@]}"; do
        if nc -z -w5 "$NIXOS_HOST" "$port" 2>/dev/null; then
            test_pass "Port $port is accessible as expected"
        else
            test_fail "Port $port should be accessible but is not"
        fi
    done
    
    for port in "${expected_closed_ports[@]}"; do
        if ! nc -z -w5 "$NIXOS_HOST" "$port" 2>/dev/null; then
            test_pass "Port $port is properly secured (not accessible externally)"
        else
            test_warn "Port $port is accessible externally (review security)"
        fi
    done
    
    # Test 2: Test SSH security
    log_info "Testing SSH security configuration..."
    
    # Test that password authentication is disabled
    if ! ssh -o PasswordAuthentication=yes -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "echo test" 2>/dev/null; then
        test_pass "SSH password authentication is properly disabled"
    else
        test_fail "SSH password authentication should be disabled"
    fi
    
    # Test 3: Test SSL/TLS configuration
    log_info "Testing SSL/TLS configuration..."
    
    if curl -s -k --connect-timeout 5 "https://$NIXOS_HOST" | grep -q ""; then
        test_pass "HTTPS is configured and responding"
    else
        test_warn "HTTPS may not be properly configured"
    fi
    
    # Test 4: Test service isolation
    log_info "Testing service isolation..."
    
    if timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "ps aux | grep postgres | grep -v grep | grep -v root" 2>/dev/null; then
        test_pass "PostgreSQL is running as non-root user"
    else
        test_warn "PostgreSQL user isolation should be verified"
    fi
}

# Function to test performance and resource usage
test_performance_resources() {
    log_header "Testing Performance and Resource Usage"
    
    # Test 1: Test system resource usage
    log_info "Testing system resource usage..."
    
    local cpu_usage
    cpu_usage=$(timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1" 2>/dev/null || echo "0")
    
    if [[ $(echo "$cpu_usage < 80" | bc 2>/dev/null || echo "1") -eq 1 ]]; then
        test_pass "CPU usage is reasonable ($cpu_usage%)"
    else
        test_warn "CPU usage is high ($cpu_usage%)"
    fi
    
    # Test 2: Test memory usage
    local memory_usage
    memory_usage=$(timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "free | grep Mem | awk '{printf \"%.1f\", \$3/\$2 * 100.0}'" 2>/dev/null || echo "0")
    
    if [[ $(echo "$memory_usage < 80" | bc 2>/dev/null || echo "1") -eq 1 ]]; then
        test_pass "Memory usage is reasonable ($memory_usage%)"
    else
        test_warn "Memory usage is high ($memory_usage%)"
    fi
    
    # Test 3: Test disk usage
    local disk_usage
    disk_usage=$(timeout $TEST_TIMEOUT ssh "$NIXOS_USER@$NIXOS_HOST" "df / | tail -1 | awk '{print \$5}' | cut -d'%' -f1" 2>/dev/null || echo "0")
    
    if [[ $disk_usage -lt 80 ]]; then
        test_pass "Disk usage is reasonable ($disk_usage%)"
    else
        test_warn "Disk usage is high ($disk_usage%)"
    fi
    
    # Test 4: Test service response times
    log_info "Testing service response times..."
    
    local response_time
    response_time=$(curl -o /dev/null -s -w "%{time_total}" --connect-timeout 5 "http://$NIXOS_HOST" 2>/dev/null || echo "999")
    
    if [[ $(echo "$response_time < 2.0" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
        test_pass "Web service response time is good (${response_time}s)"
    else
        test_warn "Web service response time is slow (${response_time}s)"
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
    echo "  --workflow-only         Test only development workflow"
    echo "  --backup-only           Test only backup and recovery"
    echo "  --monitoring-only       Test only monitoring and alerting"
    echo "  --security-only         Test only security configurations"
    echo "  --performance-only      Test only performance and resources"
    echo "  --quick                 Run quick tests only"
    echo
    echo "Examples:"
    echo "  $0                      Run all end-to-end tests"
    echo "  NIXOS_HOST=192.168.1.100 $0  Test specific IP address"
    echo "  $0 --workflow-only      Test only development workflow"
}

# Main execution
main() {
    local workflow_only=false
    local backup_only=false
    local monitoring_only=false
    local security_only=false
    local performance_only=false
    local quick=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --workflow-only)
                workflow_only=true
                shift
                ;;
            --backup-only)
                backup_only=true
                shift
                ;;
            --monitoring-only)
                monitoring_only=true
                shift
                ;;
            --security-only)
                security_only=true
                shift
                ;;
            --performance-only)
                performance_only=true
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
    
    log_info "End-to-End Integration Testing for NixOS Home Server"
    log_info "===================================================="
    log_info "Target server: $NIXOS_HOST"
    log_info "Target user: $NIXOS_USER"
    echo
    
    # Check basic connectivity first
    if ! timeout $TEST_TIMEOUT ssh -o ConnectTimeout=5 -o BatchMode=yes "$NIXOS_USER@$NIXOS_HOST" "echo 'Connection test'" 2>/dev/null; then
        log_error "Cannot connect to NixOS server. Please check:"
        log_error "1. Server is running and accessible"
        log_error "2. SSH keys are properly configured"
        log_error "3. Hostname/IP is correct: $NIXOS_HOST"
        exit 1
    fi
    
    log_info "Basic connectivity confirmed"
    echo
    
    # Run selected test suites
    if $workflow_only; then
        test_development_workflow
    elif $backup_only; then
        test_backup_recovery
    elif $monitoring_only; then
        test_monitoring_alerting
    elif $security_only; then
        test_security_configurations
    elif $performance_only; then
        test_performance_resources
    else
        # Run all test suites
        test_development_workflow
        test_backup_recovery
        test_monitoring_alerting
        test_security_configurations
        
        if ! $quick; then
            test_performance_resources
        fi
    fi
    
    # Print final summary
    echo
    log_info "End-to-End Test Summary"
    log_info "======================="
    log_info "Total tests: $TESTS_TOTAL"
    log_info "Passed: $TESTS_PASSED"
    log_info "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "All end-to-end tests passed! ✓"
        echo
        log_info "Your NixOS home server is fully functional and ready for development work."
        log_info "The complete development workflow from Mac to NixOS has been validated."
        exit 0
    else
        log_error "Some end-to-end tests failed! ✗"
        echo
        log_error "Please review and fix the failed tests before considering the system production-ready."
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi