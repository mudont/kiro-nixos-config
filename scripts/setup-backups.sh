#!/bin/bash
set -euo pipefail

NIXOS_HOST="${NIXOS_HOST:-nixos}"
NIXOS_USER="${NIXOS_USER:-murali}"
MAC_USER="${MAC_USER:-$(whoami)}"
MAC_HOST="${MAC_HOST:-$(hostname)}"

echo "Setting up automated backups from NixOS to Mac..."

# Create backup directories on Mac
mkdir -p ~/nixos-backups/{config,data,databases}

# Create backup script on NixOS
ssh "$NIXOS_USER@$NIXOS_HOST" "cat > /home/murali/backup-to-mac.sh << 'BACKUP_EOF'
#!/bin/bash
set -euo pipefail

MAC_USER=\"$MAC_USER\"
MAC_HOST=\"$MAC_HOST\"
BACKUP_DATE=\$(date +%Y%m%d_%H%M%S)
LOG_FILE=\"/home/murali/backups/backup_\${BACKUP_DATE}.log\"

echo \"Starting backup at \$(date)\" | tee \$LOG_FILE

# Create local backup directory
mkdir -p /home/murali/backups

# 1. Backup NixOS configuration
echo \"Backing up NixOS configuration...\" | tee -a \$LOG_FILE
rsync -avz --delete /etc/nixos/ \"\$MAC_USER@\$MAC_HOST:~/nixos-backups/config/\" 2>&1 | tee -a \$LOG_FILE

# 2. Backup user data
echo \"Backing up user data...\" | tee -a \$LOG_FILE
rsync -avz --delete \
    --exclude='.cache' \
    --exclude='.local/share/Trash' \
    --exclude='node_modules' \
    --exclude='.git' \
    /home/murali/ \"\$MAC_USER@\$MAC_HOST:~/nixos-backups/data/\" 2>&1 | tee -a \$LOG_FILE

# 3. Backup databases
echo \"Backing up databases...\" | tee -a \$LOG_FILE
mkdir -p /tmp/db-backup
pg_dumpall -h localhost -U murali > /tmp/db-backup/all-databases-\${BACKUP_DATE}.sql
rsync -avz /tmp/db-backup/ \"\$MAC_USER@\$MAC_HOST:~/nixos-backups/databases/\" 2>&1 | tee -a \$LOG_FILE
rm -rf /tmp/db-backup

# 4. Backup important system files
echo \"Backing up system files...\" | tee -a \$LOG_FILE
sudo tar -czf /tmp/system-backup-\${BACKUP_DATE}.tar.gz \
    /var/www \
    /srv/samba \
    /var/log 2>/dev/null || true
rsync -avz /tmp/system-backup-\${BACKUP_DATE}.tar.gz \"\$MAC_USER@\$MAC_HOST:~/nixos-backups/\" 2>&1 | tee -a \$LOG_FILE
rm -f /tmp/system-backup-\${BACKUP_DATE}.tar.gz

# 5. Copy log to Mac
rsync -avz \$LOG_FILE \"\$MAC_USER@\$MAC_HOST:~/nixos-backups/logs/\" 2>&1

echo \"Backup completed at \$(date)\" | tee -a \$LOG_FILE

# Keep only last 7 days of local logs
find /home/murali/backups -name \"backup_*.log\" -mtime +7 -delete
BACKUP_EOF

chmod +x /home/murali/backup-to-mac.sh"

# Create backup directories on NixOS
ssh "$NIXOS_USER@$NIXOS_HOST" "mkdir -p /home/murali/backups"

# Create log directory on Mac
mkdir -p ~/nixos-backups/logs

echo "Testing backup script..."
ssh "$NIXOS_USER@$NIXOS_HOST" "/home/murali/backup-to-mac.sh"

echo "Setting up automated backup schedule..."

# Create systemd service for backup
ssh "$NIXOS_USER@$NIXOS_HOST" "sudo tee /etc/systemd/system/nixos-backup.service > /dev/null << 'SERVICE_EOF'
[Unit]
Description=NixOS Backup to Mac
After=network.target

[Service]
Type=oneshot
User=murali
ExecStart=/home/murali/backup-to-mac.sh
SERVICE_EOF"

# Create systemd timer for daily backups
ssh "$NIXOS_USER@$NIXOS_HOST" "sudo tee /etc/systemd/system/nixos-backup.timer > /dev/null << 'TIMER_EOF'
[Unit]
Description=Daily NixOS Backup
Requires=nixos-backup.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
TIMER_EOF"

# Enable and start the backup timer
ssh "$NIXOS_USER@$NIXOS_HOST" "
    sudo systemctl daemon-reload
    sudo systemctl enable nixos-backup.timer
    sudo systemctl start nixos-backup.timer
    sudo systemctl status nixos-backup.timer --no-pager
"

echo ""
echo "Backup automation setup complete!"
echo ""
echo "Backup locations on your Mac:"
echo "  ~/nixos-backups/config/     - NixOS configuration files"
echo "  ~/nixos-backups/data/       - User data and files"
echo "  ~/nixos-backups/databases/  - PostgreSQL database dumps"
echo "  ~/nixos-backups/logs/       - Backup logs"
echo ""
echo "Backup schedule: Daily at midnight"
echo "Manual backup: ssh murali@nixos '/home/murali/backup-to-mac.sh'"
echo "Check backup status: ssh murali@nixos 'sudo systemctl status nixos-backup.timer'"
