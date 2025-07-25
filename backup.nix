# Backup and recovery system configuration
{ config, pkgs, ... }:

{
  # Backup system packages are included in development.nix

  # Daily backup service
  systemd.services.daily-backup = {
    description = "Daily backup to Mac";
    serviceConfig = {
      Type = "oneshot";
      User = "murali";
      Group = "users";
    };
    script = ''
      #!/bin/bash
      set -e
      
      # Configuration
      BACKUP_HOST="murali@192.168.1.100"  # Mac IP address
      BACKUP_BASE_DIR="/Users/murali/nixos-backups"
      DATE=$(date +%Y%m%d_%H%M%S)
      LOG_FILE="/var/log/backup/backup_$DATE.log"
      
      # Create log directory
      mkdir -p /var/log/backup
      
      echo "Starting backup at $(date)" | tee -a "$LOG_FILE"
      
      # Function to backup a directory
      backup_directory() {
        local source_dir=$1
        local backup_name=$2
        local exclude_file=$3
        
        echo "Backing up $source_dir to $backup_name..." | tee -a "$LOG_FILE"
        
        local rsync_cmd="rsync -avz --delete"
        if [ -n "$exclude_file" ] && [ -f "$exclude_file" ]; then
          rsync_cmd="$rsync_cmd --exclude-from=$exclude_file"
        fi
        
        $rsync_cmd "$source_dir/" "$BACKUP_HOST:$BACKUP_BASE_DIR/$backup_name/" 2>&1 | tee -a "$LOG_FILE"
        
        if [ $? -eq 0 ]; then
          echo "Successfully backed up $backup_name" | tee -a "$LOG_FILE"
        else
          echo "Failed to backup $backup_name" | tee -a "$LOG_FILE"
          return 1
        fi
      }
      
      # Create backup exclusion files
      cat > /tmp/home_exclude << 'EOF'
.cache/
.local/share/Trash/
.mozilla/firefox/*/Cache/
.docker/
node_modules/
target/
build/
dist/
*.log
*.tmp
.DS_Store
EOF
      
      cat > /tmp/config_exclude << 'EOF'
*.log
*.tmp
result
result-*
EOF
      
      # Backup user home directory (excluding cache and temporary files)
      if [ -d "/home/murali" ]; then
        backup_directory "/home/murali" "home" "/tmp/home_exclude"
      fi
      
      # Backup NixOS configuration
      if [ -d "/etc/nixos" ]; then
        backup_directory "/etc/nixos" "nixos-config" "/tmp/config_exclude"
      fi
      
      # Backup this project directory
      if [ -d "$(pwd)" ]; then
        backup_directory "$(pwd)" "project-config" "/tmp/config_exclude"
      fi
      
      # Backup PostgreSQL databases
      echo "Backing up PostgreSQL databases..." | tee -a "$LOG_FILE"
      mkdir -p /tmp/db_backup
      
      # Export each database
      for db in development testing staging; do
        if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$db"; then
          echo "Exporting database: $db" | tee -a "$LOG_FILE"
          sudo -u postgres pg_dump "$db" > "/tmp/db_backup/$db.sql" 2>&1 | tee -a "$LOG_FILE"
        fi
      done
      
      # Backup database exports
      if [ -d "/tmp/db_backup" ]; then
        backup_directory "/tmp/db_backup" "databases"
        rm -rf /tmp/db_backup
      fi
      
      # Backup system logs (last 7 days)
      echo "Backing up system logs..." | tee -a "$LOG_FILE"
      mkdir -p /tmp/log_backup
      journalctl --since "7 days ago" --output=json > /tmp/log_backup/journal_7days.json 2>&1 | tee -a "$LOG_FILE"
      
      if [ -d "/var/log" ]; then
        find /var/log -name "*.log" -mtime -7 -exec cp {} /tmp/log_backup/ \; 2>&1 | tee -a "$LOG_FILE"
      fi
      
      backup_directory "/tmp/log_backup" "logs"
      rm -rf /tmp/log_backup
      
      # Clean up temporary files
      rm -f /tmp/home_exclude /tmp/config_exclude
      
      echo "Backup completed at $(date)" | tee -a "$LOG_FILE"
      
      # Keep only last 30 days of backup logs
      find /var/log/backup -name "backup_*.log" -mtime +30 -delete
    '';
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  # Timer for daily backups
  systemd.timers.daily-backup = {
    description = "Run daily backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };

  # Git configuration backup service
  systemd.services.git-config-backup = {
    description = "Backup Git configuration and credentials";
    serviceConfig = {
      Type = "oneshot";
      User = "murali";
      Group = "users";
    };
    script = ''
      #!/bin/bash
      set -e
      
      BACKUP_HOST="murali@192.168.1.100"
      BACKUP_DIR="/Users/murali/nixos-backups/git-config"
      
      echo "Backing up Git configuration..."
      
      # Create temporary backup directory
      mkdir -p /tmp/git_backup
      
      # Copy Git configuration files
      if [ -f "/home/murali/.gitconfig" ]; then
        cp /home/murali/.gitconfig /tmp/git_backup/
      fi
      
      if [ -d "/home/murali/.ssh" ]; then
        cp -r /home/murali/.ssh /tmp/git_backup/
      fi
      
      # Backup to Mac
      rsync -avz /tmp/git_backup/ "$BACKUP_HOST:$BACKUP_DIR/"
      
      # Clean up
      rm -rf /tmp/git_backup
      
      echo "Git configuration backup completed"
    '';
  };

  # Manual backup scripts are defined in development.nix to avoid conflicts

  # Create backup log directory
  systemd.tmpfiles.rules = [
    "d /var/log/backup 0755 murali users -"
  ];
}