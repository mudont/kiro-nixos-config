#!/usr/bin/env bash

# Master Test Runner for NixOS Configuration
# This script runs all validation tests in the correct order

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

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

# Function to run a test suite
run_test_suite() {
    local test_script="$1"
    local suite_name="$2"
    
    ((TOTAL_SUITES++))
    
    log_header "$suite_name"
    
    if [[ -x "$test_script" ]]; then
        if "$test_script"; then
            ((PASSED_SUITES++))
            log_info "✓ $suite_name completed successfully"
        else
            ((FAILED_SUITES++))
            log_error "✗ $suite_name failed"
        fi
    else
        ((FAILED_SUITES++))
        log_error "✗ Test script $test_script is not executable or not found"
    fi
    
    echo
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if running on NixOS (allow macOS for integration tests)
    if [[ ! -f /etc/NIXOS ]] && [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script must be run on a NixOS system or macOS for integration tests"
        exit 1
    fi
    
    # Check if we're in the right directory
    if [[ ! -f "flake.nix" ]]; then
        log_error "This script must be run from the NixOS configuration root directory"
        exit 1
    fi
    
    # Check if test scripts exist
    local test_scripts=(
        "tests/validate-config.sh"
        "tests/test-services.sh"
        "tests/test-network-security.sh"
        "tests/integration-tests.sh"
        "tests/test-end-to-end.sh"
    )
    
    for script in "${test_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            log_error "Test script $script not found"
            exit 1
        fi
        
        if [[ ! -x "$script" ]]; then
            log_warn "Making $script executable..."
            chmod +x "$script"
        fi
    done
    
    log_info "Prerequisites check passed"
    echo
}

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -c, --config-only       Run only configuration validation tests"
    echo "  -s, --services-only     Run only service tests"
    echo "  -n, --network-only      Run only network and security tests"
    echo "  -i, --integration-only  Run only integration tests (from macOS)"
    echo "  -e, --end-to-end        Run only end-to-end workflow tests (from macOS)"
    echo "  -v, --verbose           Enable verbose output"
    echo "  --dry-run              Show what tests would be run without executing them"
    echo
    echo "Examples:"
    echo "  $0                      Run all tests"
    echo "  $0 --config-only        Run only configuration validation"
    echo "  $0 --services-only      Run only service tests"
    echo "  $0 --dry-run            Show test plan without execution"
}

# Main execution
main() {
    local config_only=false
    local services_only=false
    local network_only=false
    local integration_only=false
    local end_to_end_only=false
    local verbose=false
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--config-only)
                config_only=true
                shift
                ;;
            -s|--services-only)
                services_only=true
                shift
                ;;
            -n|--network-only)
                network_only=true
                shift
                ;;
            -i|--integration-only)
                integration_only=true
                shift
                ;;
            -e|--end-to-end)
                end_to_end_only=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set verbose mode if requested
    if $verbose; then
        set -x
    fi
    
    log_info "NixOS Configuration Test Suite"
    log_info "=============================="
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Show test plan if dry run
    if $dry_run; then
        log_info "Test execution plan:"
        if $config_only; then
            echo "  - Configuration validation tests"
        elif $services_only; then
            echo "  - Service startup tests"
        elif $network_only; then
            echo "  - Network and security tests"
        elif $integration_only; then
            echo "  - Integration tests (macOS to NixOS)"
        elif $end_to_end_only; then
            echo "  - End-to-end workflow tests (macOS to NixOS)"
        else
            echo "  - Configuration validation tests"
            echo "  - Service startup tests"
            echo "  - Network and security tests"
            echo "  - Integration tests (if on macOS)"
            echo "  - End-to-end workflow tests (if on macOS)"
        fi
        echo
        log_info "Use without --dry-run to execute tests"
        exit 0
    fi
    
    # Run selected test suites
    if $config_only; then
        run_test_suite "tests/validate-config.sh" "Configuration Validation"
    elif $services_only; then
        run_test_suite "tests/test-services.sh" "Service Testing"
    elif $network_only; then
        run_test_suite "tests/test-network-security.sh" "Network and Security Testing"
    elif $integration_only; then
        run_test_suite "tests/integration-tests.sh" "Integration Testing"
    elif $end_to_end_only; then
        run_test_suite "tests/test-end-to-end.sh" "End-to-End Workflow Testing"
    else
        # Run all test suites in order
        run_test_suite "tests/validate-config.sh" "Configuration Validation"
        
        # Only run system tests on NixOS
        if [[ -f /etc/NIXOS ]]; then
            run_test_suite "tests/test-services.sh" "Service Testing"
            run_test_suite "tests/test-network-security.sh" "Network and Security Testing"
        else
            log_info "Skipping system tests (not on NixOS)"
        fi
        
        # Run integration tests if on macOS
        if [[ "$(uname)" == "Darwin" ]]; then
            run_test_suite "tests/integration-tests.sh" "Integration Testing"
            run_test_suite "tests/test-end-to-end.sh" "End-to-End Workflow Testing"
        else
            log_info "Skipping integration tests (not on macOS)"
        fi
    fi
    
    # Print final summary
    log_info "Final Test Summary"
    log_info "=================="
    log_info "Total test suites: $TOTAL_SUITES"
    log_info "Passed: $PASSED_SUITES"
    log_info "Failed: $FAILED_SUITES"
    
    if [[ $FAILED_SUITES -eq 0 ]]; then
        log_info "All test suites passed! ✓"
        echo
        log_info "Your NixOS configuration appears to be valid and properly configured."
        exit 0
    else
        log_error "Some test suites failed! ✗"
        echo
        log_error "Please review the failed tests and fix any issues before deployment."
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi