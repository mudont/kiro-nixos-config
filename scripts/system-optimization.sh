#!/usr/bin/env bash

# NixOS System Optimization Script
# This script optimizes system performance and resource usage

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${BLUE}[OPTIMIZATION]${NC} $1"
    echo "================================================="
}

# Function to check if running on NixOS
check_nixos() {
    if [[ ! -f /etc/NIXOS ]]; then
        log_error "This script must be run on a NixOS system"
        exit 1
    fi
}

# Function to optimize Nix store
optimize_nix_store() {
    log_header "Optimizing Nix Store"
    
    log_info "Running nix-store optimization..."
    if sudo nix-store --optimise; then
        log_info "✓ Nix store optimization completed"
    else
        log_warn "Nix store optimization had issues"
    fi
    
    log_info "Collecting garbage..."
    if sudo nix-collect-garbage -d; then
        log_info "✓ Garbage collection completed"
    else
        log_warn "Garbage collection had issues"
    fi
    
    log_info "Cleaning old generations..."
    if sudo nix-env --delete-generations old; then
        log_info "✓ Old generations cleaned"
    else
        log_warn "Generation cleanup had issues"
    fi
    
    # Show disk space saved
    local store_size
    store_size=$(du -sh /nix/store 2>/dev/null | cut -f1 || echo "unknown")
    log_info "Current Nix store size: $store_size"
}

# Function to optimize system services
optimize_services() {
    log_header "Optimizing System Services"
    
    # Restart services to clear memory leaks
    local services_to_restart=("nginx" "postgresql" "grafana" "prometheus")
    
    for service in "${services_to_restart[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            log_info "Restarting $service to clear memory..."
            if sudo systemctl restart "$service"; then
                log_info "✓ $service restarted successfully"
            else
                log_warn "Failed to restart $service"
            fi
        else
            log_info "$service is not running, skipping restart"
        fi
    done
    
    # Reload systemd daemon
    log_info "Reloading systemd daemon..."
    if sudo systemctl daemon-reload; then
        log_info "✓ Systemd daemon reloaded"
    else
        log_warn "Failed to reload systemd daemon"
    fi
}

# Function to optimize database
optimize_database() {
    log_header "Optimizing Database"
    
    if systemctl is-active postgresql >/dev/null 2>&1; then
        log_info "Running PostgreSQL maintenance..."
        
        # Vacuum and analyze all databases
        if sudo -u postgres psql -c "VACUUM ANALYZE;" 2>/dev/null; then
            log_info "✓ PostgreSQL vacuum and analyze completed"
        else
            log_warn "PostgreSQL maintenance had issues"
        fi
        
        # Reindex system catalogs
        if sudo -u postgres reindexdb --system --all 2>/dev/null; then
            log_info "✓ PostgreSQL reindex completed"
        else
            log_warn "PostgreSQL reindex had issues"
        fi
        
        # Show database sizes
        log_info "Database sizes:"
        sudo -u postgres psql -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database;" 2>/dev/null || log_warn "Could not retrieve database sizes"
    else
        log_info "PostgreSQL is not running, skipping database optimization"
    fi
}

# Function to clean system logs
clean_logs() {
    log_header "Cleaning System Logs"
    
    # Clean journald logs older than 30 days
    log_info "Cleaning journald logs older than 30 days..."
    if sudo journalctl --vacuum-time=30d; then
        log_info "✓ Journald logs cleaned"
    else
        log_warn "Failed to clean journald logs"
    fi
    
    # Clean nginx logs older than 30 days
    if [[ -d /var/log/nginx ]]; then
        log_info "Cleaning old nginx logs..."
        if sudo find /var/log/nginx -name "*.log.*" -mtime +30 -delete 2>/dev/null; then
            log_info "✓ Old nginx logs cleaned"
        else
            log_warn "Failed to clean nginx logs"
        fi
    fi
    
    # Show current log sizes
    log_info "Current log directory sizes:"
    sudo du -sh /var/log/* 2>/dev/null | head -10 || log_warn "Could not retrieve log sizes"
}

# Function to optimize memory usage
optimize_memory() {
    log_header "Optimizing Memory Usage"
    
    # Clear page cache, dentries and inodes
    log_info "Clearing system caches..."
    if sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null; then
        log_info "✓ System caches cleared"
    else
        log_warn "Failed to clear system caches"
    fi
    
    # Show memory usage before and after
    log_info "Current memory usage:"
    free -h || log_warn "Could not retrieve memory information"
}

# Function to optimize network settings
optimize_network() {
    log_header "Optimizing Network Settings"
    
    # Flush DNS cache if systemd-resolved is running
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        log_info "Flushing DNS cache..."
        if sudo systemctl restart systemd-resolved; then
            log_info "✓ DNS cache flushed"
        else
            log_warn "Failed to flush DNS cache"
        fi
    fi
    
    # Show network statistics
    log_info "Network interface statistics:"
    ip -s link show | grep -E "^[0-9]+:|RX:|TX:" | head -20 || log_warn "Could not retrieve network statistics"
}

# Function to check and optimize disk usage
optimize_disk() {
    log_header "Optimizing Disk Usage"
    
    # Clean temporary files
    log_info "Cleaning temporary files..."
    if sudo find /tmp -type f -atime +7 -delete 2>/dev/null; then
        log_info "✓ Old temporary files cleaned"
    else
        log_warn "Failed to clean temporary files"
    fi
    
    # Clean user cache directories
    log_info "Cleaning user cache directories..."
    if find ~/.cache -type f -atime +30 -delete 2>/dev/null; then
        log_info "✓ User cache cleaned"
    else
        log_warn "Failed to clean user cache"
    fi
    
    # Show disk usage
    log_info "Current disk usage:"
    df -h | grep -E "^/dev|^tmpfs" || log_warn "Could not retrieve disk usage"
    
    # Show largest directories
    log_info "Largest directories in /:"
    sudo du -sh /* 2>/dev/null | sort -hr | head -10 || log_warn "Could not retrieve directory sizes"
}

# Function to update system packages
update_system() {
    log_header "Updating System Packages"
    
    # Update flake inputs
    log_info "Updating flake inputs..."
    if nix flake update; then
        log_info "✓ Flake inputs updated"
    else
        log_warn "Failed to update flake inputs"
    fi
    
    # Show what would be updated (dry run)
    log_info "Checking for system updates..."
    if nixos-rebuild dry-build --flake .#nixos; then
        log_info "✓ System update check completed"
    else
        log_warn "System update check had issues"
    fi
}

# Function to generate system report
generate_report() {
    log_header "Generating System Report"
    
    local report_file="/tmp/nixos-optimization-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "NixOS System Optimization Report"
        echo "Generated: $(date)"
        echo "========================================"
        echo
        
        echo "System Information:"
        echo "-------------------"
        uname -a
        echo
        
        echo "Memory Usage:"
        echo "-------------"
        free -h
        echo
        
        echo "Disk Usage:"
        echo "-----------"
        df -h
        echo
        
        echo "Load Average:"
        echo "-------------"
        uptime
        echo
        
        echo "Active Services:"
        echo "----------------"
        systemctl list-units --type=service --state=active | head -20
        echo
        
        echo "Network Interfaces:"
        echo "-------------------"
        ip addr show
        echo
        
        echo "Nix Store Size:"
        echo "---------------"
        du -sh /nix/store
        echo
        
        echo "Log Directory Sizes:"
        echo "--------------------"
        sudo du -sh /var/log/* 2>/dev/null | head -10
        echo
        
    } > "$report_file"
    
    log_info "System report generated: $report_file"
    
    # Show summary
    echo
    log_info "System Summary:"
    echo "==============="
    echo "Memory: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
    echo "Disk: $(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $5 " used)"}')"
    echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
    echo "Uptime: $(uptime | awk '{print $3 $4}' | sed 's/,//')"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  --nix-only              Optimize only Nix store"
    echo "  --services-only         Optimize only services"
    echo "  --database-only         Optimize only database"
    echo "  --logs-only             Clean only logs"
    echo "  --memory-only           Optimize only memory"
    echo "  --network-only          Optimize only network"
    echo "  --disk-only             Optimize only disk"
    echo "  --update-only           Update only system packages"
    echo "  --report-only           Generate only system report"
    echo "  --dry-run              Show what would be optimized"
    echo
    echo "Examples:"
    echo "  $0                      Run all optimizations"
    echo "  $0 --nix-only           Optimize only Nix store"
    echo "  $0 --dry-run            Show optimization plan"
}

# Main execution
main() {
    local nix_only=false
    local services_only=false
    local database_only=false
    local logs_only=false
    local memory_only=false
    local network_only=false
    local disk_only=false
    local update_only=false
    local report_only=false
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --nix-only)
                nix_only=true
                shift
                ;;
            --services-only)
                services_only=true
                shift
                ;;
            --database-only)
                database_only=true
                shift
                ;;
            --logs-only)
                logs_only=true
                shift
                ;;
            --memory-only)
                memory_only=true
                shift
                ;;
            --network-only)
                network_only=true
                shift
                ;;
            --disk-only)
                disk_only=true
                shift
                ;;
            --update-only)
                update_only=true
                shift
                ;;
            --report-only)
                report_only=true
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
    
    check_nixos
    
    log_info "NixOS System Optimization"
    log_info "========================="
    echo
    
    if $dry_run; then
        log_info "Optimization plan (dry run):"
        if $nix_only; then
            echo "  - Nix store optimization"
        elif $services_only; then
            echo "  - Service optimization"
        elif $database_only; then
            echo "  - Database optimization"
        elif $logs_only; then
            echo "  - Log cleanup"
        elif $memory_only; then
            echo "  - Memory optimization"
        elif $network_only; then
            echo "  - Network optimization"
        elif $disk_only; then
            echo "  - Disk optimization"
        elif $update_only; then
            echo "  - System updates"
        elif $report_only; then
            echo "  - System report generation"
        else
            echo "  - Nix store optimization"
            echo "  - Service optimization"
            echo "  - Database optimization"
            echo "  - Log cleanup"
            echo "  - Memory optimization"
            echo "  - Network optimization"
            echo "  - Disk optimization"
            echo "  - System report generation"
        fi
        echo
        log_info "Use without --dry-run to execute optimizations"
        exit 0
    fi
    
    # Run selected optimizations
    if $nix_only; then
        optimize_nix_store
    elif $services_only; then
        optimize_services
    elif $database_only; then
        optimize_database
    elif $logs_only; then
        clean_logs
    elif $memory_only; then
        optimize_memory
    elif $network_only; then
        optimize_network
    elif $disk_only; then
        optimize_disk
    elif $update_only; then
        update_system
    elif $report_only; then
        generate_report
    else
        # Run all optimizations
        optimize_nix_store
        optimize_services
        optimize_database
        clean_logs
        optimize_memory
        optimize_network
        optimize_disk
        generate_report
    fi
    
    echo
    log_info "System optimization completed!"
    log_info "=============================="
    
    # Final system status
    echo
    log_info "Final System Status:"
    echo "Memory: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
    echo "Disk: $(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $5 " used)"}')"
    echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
    
    log_info "System optimization completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi