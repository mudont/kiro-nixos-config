# Backup and recovery services configuration
{ config, pkgs, ... }:

{
  # Install backup tools
  environment.systemPackages = with pkgs; [
    rsync
    rclone
    postgresql_16  # For pg_dump
    git
  ];

  # Create backup directories
  systemd.tmpfiles.rules = [
    "d /var/backups 0755 root root -"
    "d /var/backups/database 0755 postgres postgres -"
    "d /var/backups/system 0755 root root -"
    "d /var/backups/config 0755 root root -"
  ];

  # Database backup service
  systemd.services.postgres-backup = {
    description = "PostgreSQL Database Backup";
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      ExecStart = pkgs.writeShellScript "postgres-backup" ''
        #!/bin/bash
        set -euo pipefail
        
        BACKUP_DIR="/var/backups/database"
        DATE=$(date +%Y%m%d_%H%M%S)
        
        # Create backup with timestamp
        ${pkgs.postgresql_16}/bin/pg_dumpall > "$BACKUP_DIR/postgres_backup_$DATE.sql"
        
        # Keep only last 7 days of backups
        find "$BACKUP_DIR" -name "postgres_backup_*.sql" -mtime +7 -delete
        
        # Create a latest symlink
        ln -sf "$BACKUP_DIR/postgres_backup_$DATE.sql" "$BACKUP_DIR/postgres_backup_latest.sql"
        
        echo "Database backup completed: postgres_backup_$DATE.sql"
      '';
    };
  };

  # Database backup timer (daily at 2 AM)
  systemd.timers.postgres-backup = {
    description = "PostgreSQL Database Backup Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  # System backup to Mac service
  systemd.services.backup-to-mac = {
    description = "Backup System Data to Mac";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = pkgs.writeShellScript "backup-to-mac" ''
        #!/bin/bash
        set -euo pipefail
        
        # Configuration
        MAC_HOST="murali-mac.local"
        MAC_USER="murali"
        BACKUP_BASE_DIR="/Users/$MAC_USER/nixos-backups"
        DATE=$(date +%Y%m%d_%H%M%S)
        
        # Check if Mac is reachable
        if ! ping -c 1 "$MAC_HOST" >/dev/null 2>&1; then
          echo "Warning: Mac host $MAC_HOST is not reachable, skipping backup"
          exit 0
        fi
        
        # Create backup directory on Mac
        ssh "$MAC_USER@$MAC_HOST" "mkdir -p $BACKUP_BASE_DIR/{database,system,config}"
        
        # Backup database dumps
        if [ -d "/var/backups/database" ]; then
          echo "Backing up database dumps..."
          rsync -avz --delete /var/backups/database/ "$MAC_USER@$MAC_HOST:$BACKUP_BASE_DIR/database/"
        fi
        
        # Backup important system directories
        echo "Backing up system configuration..."
        rsync -avz --delete \
          --exclude='/nix/store' \
          --exclude='/tmp' \
          --exclude='/var/tmp' \
          --exclude='/proc' \
          --exclude='/sys' \
          --exclude='/dev' \
          --exclude='/run' \
          --exclude='/var/log' \
          /etc/ "$MAC_USER@$MAC_HOST:$BACKUP_BASE_DIR/system/etc/"
        
        # Backup home directories (excluding large files)
        echo "Backing up home directories..."
        rsync -avz --delete \
          --exclude='*.iso' \
          --exclude='*.img' \
          --exclude='.cache' \
          --exclude='.local/share/Trash' \
          --exclude='Downloads' \
          /home/ "$MAC_USER@$MAC_HOST:$BACKUP_BASE_DIR/system/home/"
        
        echo "Backup to Mac completed successfully"
      '';
    };
  };

  # Backup to Mac timer (daily at 3 AM)
  systemd.timers.backup-to-mac = {
    description = "Backup to Mac Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };

  # iCloud backup service (alternative)
  systemd.services.backup-to-icloud = {
    description = "Backup System Data to iCloud Drive";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = pkgs.writeShellScript "backup-to-icloud" ''
        #!/bin/bash
        set -euo pipefail
        
        # Check if rclone is configured for iCloud
        if ! rclone listremotes | grep -q "icloud:"; then
          echo "Warning: iCloud remote not configured in rclone, skipping backup"
          exit 0
        fi
        
        DATE=$(date +%Y%m%d_%H%M%S)
        
        # Backup database dumps to iCloud
        if [ -d "/var/backups/database" ]; then
          echo "Backing up database dumps to iCloud..."
          rclone sync /var/backups/database/ icloud:nixos-backups/database/ \
            --progress --transfers 4 --checkers 8
        fi
        
        # Backup configuration files to iCloud
        echo "Backing up configuration to iCloud..."
        rclone sync /etc/nixos/ icloud:nixos-backups/config/nixos/ \
          --progress --transfers 4 --checkers 8
        
        # Backup important home directory files
        echo "Backing up home directory essentials to iCloud..."
        rclone sync /home/murali/ icloud:nixos-backups/home/ \
          --exclude "*.iso" \
          --exclude "*.img" \
          --exclude ".cache/**" \
          --exclude ".local/share/Trash/**" \
          --exclude "Downloads/**" \
          --progress --transfers 4 --checkers 8
        
        echo "iCloud backup completed successfully"
      '';
    };
  };

  # iCloud backup timer (weekly on Sunday at 4 AM)
  systemd.timers.backup-to-icloud = {
    description = "Backup to iCloud Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 04:00";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Backup status check service
  systemd.services.backup-status = {
    description = "Check Backup Status";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = pkgs.writeShellScript "backup-status" ''
        #!/bin/bash
        
        echo "=== Backup Status Report ==="
        echo "Generated: $(date)"
        echo
        
        # Check local backups
        echo "Local Database Backups:"
        if [ -d "/var/backups/database" ]; then
          ls -la /var/backups/database/ | tail -5
        else
          echo "  No database backups found"
        fi
        echo
        
        # Check last backup times
        echo "Last Backup Times:"
        echo "  Database: $(systemctl show postgres-backup.service -p ActiveEnterTimestamp --value)"
        echo "  Mac Sync: $(systemctl show backup-to-mac.service -p ActiveEnterTimestamp --value)"
        echo "  iCloud Sync: $(systemctl show backup-to-icloud.service -p ActiveEnterTimestamp --value)"
        echo
        
        # Check backup service status
        echo "Backup Service Status:"
        systemctl is-active postgres-backup.timer backup-to-mac.timer backup-to-icloud.timer
      '';
    };
  };

  # Configuration backup with Git service
  systemd.services.config-git-backup = {
    description = "Backup NixOS Configuration to Git";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      WorkingDirectory = "/etc/nixos";
      ExecStart = pkgs.writeShellScript "config-git-backup" ''
        #!/bin/bash
        set -euo pipefail
        
        CONFIG_DIR="/etc/nixos"
        cd "$CONFIG_DIR"
        
        # Initialize git repository if it doesn't exist
        if [ ! -d ".git" ]; then
          echo "Initializing Git repository in $CONFIG_DIR..."
          git init
          git config user.name "NixOS System"
          git config user.email "system@nixos.local"
          
          # Create initial .gitignore
          cat > .gitignore << 'EOF'
# Hardware-specific files
hardware-configuration.nix
# Temporary files
*.tmp
*.bak
*~
# Secrets (if any)
secrets/
*.key
*.pem
EOF
        fi
        
        # Add all configuration files
        git add .
        
        # Check if there are changes to commit
        if git diff --staged --quiet; then
          echo "No configuration changes to commit"
          exit 0
        fi
        
        # Commit changes with timestamp
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        git commit -m "Automatic backup: $TIMESTAMP"
        
        echo "Configuration changes committed to Git"
        
        # Push to remote if configured
        if git remote get-url origin >/dev/null 2>&1; then
          echo "Pushing to remote repository..."
          git push origin main || git push origin master || echo "Failed to push to remote"
        else
          echo "No remote repository configured"
        fi
      '';
    };
  };

  # Configuration backup timer (daily at 1 AM)
  systemd.timers.config-git-backup = {
    description = "Configuration Git Backup Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "01:00";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };

  # Configuration rollback service
  systemd.services.config-rollback = {
    description = "Rollback NixOS Configuration";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      WorkingDirectory = "/etc/nixos";
      ExecStart = pkgs.writeShellScript "config-rollback" ''
        #!/bin/bash
        set -euo pipefail
        
        CONFIG_DIR="/etc/nixos"
        cd "$CONFIG_DIR"
        
        if [ ! -d ".git" ]; then
          echo "Error: No Git repository found in $CONFIG_DIR"
          exit 1
        fi
        
        # Show recent commits
        echo "Recent configuration commits:"
        git log --oneline -10
        echo
        
        if [ $# -eq 0 ]; then
          echo "Usage: systemctl start config-rollback@<commit-hash>.service"
          echo "Or use the rollback script: /etc/nixos/scripts/rollback-config.sh <commit-hash>"
          exit 1
        fi
        
        COMMIT_HASH="$1"
        
        echo "Rolling back to commit: $COMMIT_HASH"
        git checkout "$COMMIT_HASH" -- .
        
        echo "Configuration rolled back. Run 'nixos-rebuild switch' to apply changes."
      '';
    };
  };

  # Point-in-time recovery script
  environment.etc."nixos/scripts/restore-database.sh" = {
    text = ''
      #!/bin/bash
      # PostgreSQL Point-in-Time Recovery Script
      
      set -euo pipefail
      
      BACKUP_DIR="/var/backups/database"
      
      if [ $# -eq 0 ]; then
        echo "Usage: $0 [backup_file|latest]"
        echo "Available backups:"
        ls -la "$BACKUP_DIR"/postgres_backup_*.sql 2>/dev/null || echo "No backups found"
        exit 1
      fi
      
      if [ "$1" = "latest" ]; then
        BACKUP_FILE="$BACKUP_DIR/postgres_backup_latest.sql"
      else
        BACKUP_FILE="$1"
      fi
      
      if [ ! -f "$BACKUP_FILE" ]; then
        echo "Error: Backup file $BACKUP_FILE not found"
        exit 1
      fi
      
      echo "WARNING: This will drop all existing databases and restore from backup!"
      echo "Backup file: $BACKUP_FILE"
      echo "Press Ctrl+C to cancel, or Enter to continue..."
      read
      
      # Stop services that might be using the database
      systemctl stop postgresql
      
      # Start PostgreSQL
      systemctl start postgresql
      
      # Wait for PostgreSQL to be ready
      sleep 5
      
      # Restore from backup
      echo "Restoring database from $BACKUP_FILE..."
      sudo -u postgres psql -f "$BACKUP_FILE"
      
      echo "Database restoration completed successfully"
    '';
    mode = "0755";
  };

  # Configuration rollback script
  environment.etc."nixos/scripts/rollback-config.sh" = {
    text = ''
      #!/bin/bash
      # NixOS Configuration Rollback Script
      
      set -euo pipefail
      
      CONFIG_DIR="/etc/nixos"
      
      if [ $# -eq 0 ]; then
        echo "Usage: $0 <commit-hash>"
        echo "Available commits:"
        cd "$CONFIG_DIR"
        git log --oneline -10 2>/dev/null || echo "No Git repository found"
        exit 1
      fi
      
      COMMIT_HASH="$1"
      
      cd "$CONFIG_DIR"
      
      if [ ! -d ".git" ]; then
        echo "Error: No Git repository found in $CONFIG_DIR"
        echo "Run 'systemctl start config-git-backup.service' to initialize"
        exit 1
      fi
      
      echo "Rolling back configuration to commit: $COMMIT_HASH"
      git show --oneline -s "$COMMIT_HASH"
      echo
      
      echo "WARNING: This will replace current configuration!"
      read -p "Continue? (y/N): " -n 1 -r
      echo
      
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Create backup branch
        BACKUP_BRANCH="backup-$(date +%Y%m%d_%H%M%S)"
        git branch "$BACKUP_BRANCH"
        echo "Created backup branch: $BACKUP_BRANCH"
        
        # Rollback
        git reset --hard "$COMMIT_HASH"
        echo "Configuration rolled back successfully"
        echo "Run 'nixos-rebuild switch' to apply changes"
      else
        echo "Rollback cancelled"
      fi
    '';
    mode = "0755";
  };

  # Git configuration management script
  environment.etc."nixos/scripts/git-config.sh" = {
    text = ''
      #!/bin/bash
      # Quick Git configuration management
      
      CONFIG_DIR="/etc/nixos"
      cd "$CONFIG_DIR"
      
      case "''${1:-status}" in
        init)
          systemctl start config-git-backup.service
          ;;
        backup)
          systemctl start config-git-backup.service
          ;;
        status)
          if [ -d ".git" ]; then
            echo "Git Status:"
            git status --short
            echo
            echo "Recent commits:"
            git log --oneline -5
          else
            echo "Git repository not initialized"
            echo "Run: $0 init"
          fi
          ;;
        log)
          git log --oneline --graph -10
          ;;
        *)
          echo "Usage: $0 {init|backup|status|log}"
          ;;
      esac
    '';
    mode = "0755";
  };
}