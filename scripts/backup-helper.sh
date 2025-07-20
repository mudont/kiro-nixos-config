#!/bin/bash
# NixOS Backup Helper Script
# This script provides manual backup operations and setup utilities

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/var/backups"

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
NixOS Backup Helper Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    setup-rclone        Configure rclone for iCloud Drive backup
    backup-db           Run database backup manually
    backup-mac          Run Mac backup manually  
    backup-icloud       Run iCloud backup manually
    restore-db [file]   Restore database from backup file
    status              Show backup status and recent backups
    test-connectivity   Test connectivity to backup destinations
    cleanup             Clean up old backup files

Examples:
    $0 setup-rclone
    $0 backup-db
    $0 restore-db latest
    $0 status
EOF
}

setup_rclone() {
    log_info "Setting up rclone for iCloud Drive..."
    
    if ! command -v rclone &> /dev/null; then
        log_error "rclone is not installed. Please install it first."
        exit 1
    fi
    
    log_info "Starting rclone configuration for iCloud Drive..."
    log_warning "You'll need to configure iCloud Drive manually through rclone config"
    log_info "When prompted:"
    log_info "  1. Choose 'n' for new remote"
    log_info "  2. Name it 'icloud'"
    log_info "  3. Choose WebDAV storage type"
    log_info "  4. Use URL: https://p03-caldav.icloud.com"
    log_info "  5. Choose 'other' for vendor"
    log_info "  6. Enter your iCloud username and app-specific password"
    
    rclone config
    
    # Test the connection
    if rclone lsd icloud: &>/dev/null; then
        log_success "iCloud Drive configured successfully!"
        
        # Create backup directory
        rclone mkdir icloud:nixos-backups
        log_success "Created nixos-backups directory in iCloud Drive"
    else
        log_error "Failed to connect to iCloud Drive. Please check your configuration."
    fi
}

backup_database() {
    log_info "Running database backup..."
    
    if systemctl is-active --quiet postgresql; then
        systemctl start postgres-backup.service
        log_success "Database backup completed"
    else
        log_error "PostgreSQL service is not running"
        exit 1
    fi
}

backup_to_mac() {
    log_info "Running backup to Mac..."
    
    MAC_HOST="murali-mac.local"
    if ping -c 1 "$MAC_HOST" >/dev/null 2>&1; then
        systemctl start backup-to-mac.service
        log_success "Mac backup completed"
    else
        log_error "Cannot reach Mac host: $MAC_HOST"
        exit 1
    fi
}

backup_to_icloud() {
    log_info "Running backup to iCloud Drive..."
    
    if rclone listremotes | grep -q "icloud:"; then
        systemctl start backup-to-icloud.service
        log_success "iCloud backup completed"
    else
        log_error "iCloud remote not configured. Run '$0 setup-rclone' first."
        exit 1
    fi
}

restore_database() {
    local backup_file="$1"
    
    if [ "$backup_file" = "latest" ]; then
        backup_file="$BACKUP_DIR/database/postgres_backup_latest.sql"
    fi
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        list_backups
        exit 1
    fi
    
    log_warning "This will restore the database from: $backup_file"
    log_warning "All current data will be replaced!"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        /etc/nixos/scripts/restore-database.sh "$backup_file"
    else
        log_info "Database restore cancelled"
    fi
}

show_status() {
    log_info "Backup Status Report"
    echo "===================="
    
    # Show local backups
    echo
    log_info "Local Database Backups:"
    if [ -d "$BACKUP_DIR/database" ]; then
        ls -la "$BACKUP_DIR/database/" | tail -5
    else
        echo "  No database backups found"
    fi
    
    echo
    log_info "Backup Service Status:"
    systemctl status postgres-backup.timer backup-to-mac.timer backup-to-icloud.timer --no-pager -l
    
    echo
    log_info "Last Backup Execution Times:"
    echo "  Database: $(systemctl show postgres-backup.service -p ActiveEnterTimestamp --value)"
    echo "  Mac Sync: $(systemctl show backup-to-mac.service -p ActiveEnterTimestamp --value)"
    echo "  iCloud Sync: $(systemctl show backup-to-icloud.service -p ActiveEnterTimestamp --value)"
    
    echo
    log_info "Disk Usage:"
    du -sh "$BACKUP_DIR"/* 2>/dev/null || echo "  No backup directories found"
}

test_connectivity() {
    log_info "Testing backup destination connectivity..."
    
    # Test Mac connectivity
    MAC_HOST="murali-mac.local"
    if ping -c 1 "$MAC_HOST" >/dev/null 2>&1; then
        log_success "Mac host ($MAC_HOST) is reachable"
        
        # Test SSH connectivity
        if ssh -o ConnectTimeout=5 -o BatchMode=yes murali@"$MAC_HOST" exit 2>/dev/null; then
            log_success "SSH connection to Mac is working"
        else
            log_warning "SSH connection to Mac failed - check SSH keys"
        fi
    else
        log_warning "Mac host ($MAC_HOST) is not reachable"
    fi
    
    # Test iCloud connectivity
    if command -v rclone &> /dev/null; then
        if rclone listremotes | grep -q "icloud:"; then
            if rclone lsd icloud: &>/dev/null; then
                log_success "iCloud Drive connection is working"
            else
                log_warning "iCloud Drive connection failed"
            fi
        else
            log_warning "iCloud remote not configured"
        fi
    else
        log_warning "rclone not available"
    fi
}

cleanup_backups() {
    log_info "Cleaning up old backup files..."
    
    # Clean database backups older than 30 days
    if [ -d "$BACKUP_DIR/database" ]; then
        find "$BACKUP_DIR/database" -name "postgres_backup_*.sql" -mtime +30 -delete
        log_success "Cleaned up database backups older than 30 days"
    fi
    
    # Clean system backups older than 7 days
    if [ -d "$BACKUP_DIR/system" ]; then
        find "$BACKUP_DIR/system" -type f -mtime +7 -delete
        log_success "Cleaned up system backups older than 7 days"
    fi
    
    log_info "Cleanup completed"
}

list_backups() {
    log_info "Available database backups:"
    if [ -d "$BACKUP_DIR/database" ]; then
        ls -la "$BACKUP_DIR/database"/postgres_backup_*.sql 2>/dev/null || echo "  No backups found"
    else
        echo "  Backup directory not found"
    fi
}

# Main script logic
case "${1:-}" in
    setup-rclone)
        setup_rclone
        ;;
    backup-db)
        backup_database
        ;;
    backup-mac)
        backup_to_mac
        ;;
    backup-icloud)
        backup_to_icloud
        ;;
    restore-db)
        if [ $# -lt 2 ]; then
            log_error "Please specify backup file or 'latest'"
            list_backups
            exit 1
        fi
        restore_database "$2"
        ;;
    status)
        show_status
        ;;
    test-connectivity)
        test_connectivity
        ;;
    cleanup)
        cleanup_backups
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown command: ${1:-}"
        echo
        show_help
        exit 1
        ;;
esac