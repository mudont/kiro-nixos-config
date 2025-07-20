#!/usr/bin/env bash

# NixOS Configuration Validation Tests
# This script validates the NixOS configuration syntax and basic functionality

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

# Check if running on NixOS (allow macOS for development)
check_nixos() {
    if [[ ! -f /etc/NIXOS ]] && [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script must be run on a NixOS system or macOS for development"
        exit 1
    fi
    
    if [[ "$(uname)" == "Darwin" ]]; then
        log_warn "Running on macOS - some tests will be skipped"
    fi
}

# Test 1: Validate flake configuration syntax
test_flake_syntax() {
    log_info "Testing flake configuration syntax..."
    
    if nix flake check --no-build 2>/dev/null; then
        test_pass "Flake configuration syntax is valid"
    else
        test_fail "Flake configuration has syntax errors"
        nix flake check --no-build 2>&1 | head -10
    fi
}

# Test 2: Validate NixOS configuration can be built
test_nixos_build() {
    log_info "Testing NixOS configuration build..."
    
    if [[ "$(uname)" == "Darwin" ]]; then
        log_warn "Skipping NixOS build test on macOS"
        return
    fi
    
    if nixos-rebuild dry-build --flake .#nixos 2>/dev/null; then
        test_pass "NixOS configuration builds successfully"
    else
        test_fail "NixOS configuration build failed"
        nixos-rebuild dry-build --flake .#nixos 2>&1 | tail -20
    fi
}

# Test 3: Validate home-manager configuration
test_home_manager() {
    log_info "Testing home-manager configuration..."
    
    if nix build .#homeConfigurations.murali.activationPackage --no-link 2>/dev/null; then
        test_pass "Home-manager configuration builds successfully"
    else
        test_fail "Home-manager configuration build failed"
        nix build .#homeConfigurations.murali.activationPackage --no-link 2>&1 | tail -10
    fi
}

# Test 4: Check for common configuration issues
test_configuration_issues() {
    log_info "Checking for common configuration issues..."
    
    # Check for duplicate imports
    if find nixos/ -name "*.nix" -exec grep -l "import.*import" {} \; | grep -q .; then
        test_fail "Found potential duplicate imports"
    else
        test_pass "No duplicate imports found"
    fi
    
    # Check for missing semicolons (basic check)
    if find nixos/ home-manager/ -name "*.nix" -exec grep -l "[^;]$" {} \; | head -1 | grep -q .; then
        log_warn "Some lines may be missing semicolons (manual review recommended)"
    fi
    
    # Check for proper module structure
    local modules_valid=true
    for module in nixos/services/*.nix; do
        if [[ -f "$module" ]]; then
            if ! grep -q "{ config, pkgs, ... }:" "$module"; then
                modules_valid=false
                log_error "Module $module missing proper function signature"
            fi
        fi
    done
    
    if $modules_valid; then
        test_pass "All service modules have proper structure"
    else
        test_fail "Some service modules have structural issues"
    fi
}

# Test 5: Validate required files exist
test_required_files() {
    log_info "Checking for required configuration files..."
    
    local required_files=(
        "flake.nix"
        "nixos/configuration.nix"
        "nixos/hardware.nix"
        "nixos/networking.nix"
        "nixos/users.nix"
        "home-manager/home.nix"
    )
    
    local all_files_exist=true
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Found: $file"
        else
            all_files_exist=false
            log_error "Missing: $file"
        fi
    done
    
    if $all_files_exist; then
        test_pass "All required configuration files exist"
    else
        test_fail "Some required configuration files are missing"
    fi
}

# Test 6: Check service module imports
test_service_imports() {
    log_info "Validating service module imports..."
    
    local service_modules=(
        "web.nix"
        "database.nix"
        "samba.nix"
        "desktop.nix"
        "development.nix"
        "monitoring.nix"
        "backup.nix"
    )
    
    local imports_valid=true
    for module in "${service_modules[@]}"; do
        if [[ -f "nixos/services/$module" ]]; then
            if grep -q "./services/$module" nixos/configuration.nix; then
                log_info "Service module $module is properly imported"
            else
                imports_valid=false
                log_error "Service module $module is not imported in configuration.nix"
            fi
        else
            log_warn "Service module $module does not exist"
        fi
    done
    
    if $imports_valid; then
        test_pass "All existing service modules are properly imported"
    else
        test_fail "Some service modules are not properly imported"
    fi
}

# Main execution
main() {
    log_info "Starting NixOS Configuration Validation Tests"
    log_info "=============================================="
    
    # Change to the configuration directory
    cd "$(dirname "$0")/.."
    
    # Run all tests
    test_required_files
    test_flake_syntax
    test_nixos_build
    test_home_manager
    test_configuration_issues
    test_service_imports
    
    # Print summary
    echo
    log_info "Test Summary"
    log_info "============"
    log_info "Total tests: $TESTS_TOTAL"
    log_info "Passed: $TESTS_PASSED"
    log_info "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "All tests passed! ✓"
        exit 0
    else
        log_error "Some tests failed! ✗"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi