# Database services configuration (PostgreSQL)
{ config, pkgs, ... }:

{
  # Enable PostgreSQL database service
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15; # Use PostgreSQL 15 (stable and modern)
    
    # Data directory
    dataDir = "/var/lib/postgresql/15";
    
    # Basic settings - keep it simple to avoid issues
    settings = {
      listen_addresses = "localhost";
      port = 5432;
      max_connections = 100;
      shared_buffers = "128MB";
      # Explicitly disable SSL
      ssl = false;
      # Disable custom logging to avoid file system issues
      log_destination = "stderr";
      logging_collector = false;
    };
    
    # Authentication configuration (localhost trust for development)
    authentication = pkgs.lib.mkOverride 10 ''
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      
      # "local" is for Unix domain socket connections only
      local   all             all                                     trust
      
      # IPv4 local connections (localhost only)
      host    all             all             127.0.0.1/32            trust
      host    all             all             ::1/128                 trust
      
      # Reject all other connections
      host    all             all             0.0.0.0/0               reject
    '';
    
    # Initial database setup
    initialScript = pkgs.writeText "backend-initScript" ''
      -- Create development user
      CREATE USER developer WITH PASSWORD 'devpass' CREATEDB;
      
      -- Create monitoring user for Prometheus PostgreSQL exporter
      CREATE USER prometheus_exporter WITH PASSWORD 'monitoring_pass';
      GRANT CONNECT ON DATABASE postgres TO prometheus_exporter;
      GRANT pg_monitor TO prometheus_exporter;
      
      -- Create development databases
      CREATE DATABASE development OWNER developer;
      CREATE DATABASE testing OWNER developer;
      CREATE DATABASE staging OWNER developer;
      
      -- Grant necessary permissions
      GRANT ALL PRIVILEGES ON DATABASE development TO developer;
      GRANT ALL PRIVILEGES ON DATABASE testing TO developer;
      GRANT ALL PRIVILEGES ON DATABASE staging TO developer;
      
      -- Grant monitoring access to development databases
      GRANT CONNECT ON DATABASE development TO prometheus_exporter;
      GRANT CONNECT ON DATABASE testing TO prometheus_exporter;
      GRANT CONNECT ON DATABASE staging TO prometheus_exporter;
      
      -- Create extensions that are commonly needed
      \c development;
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
      CREATE EXTENSION IF NOT EXISTS "pgcrypto";
      CREATE EXTENSION IF NOT EXISTS "hstore";
      
      \c testing;
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
      CREATE EXTENSION IF NOT EXISTS "pgcrypto";
      CREATE EXTENSION IF NOT EXISTS "hstore";
      
      \c staging;
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
      CREATE EXTENSION IF NOT EXISTS "pgcrypto";
      CREATE EXTENSION IF NOT EXISTS "hstore";
    '';
    
    # Enable additional extensions
    extensions = with pkgs.postgresql_15.pkgs; [
      pg_repack
      pgvector
      postgis
    ];
  };
  
  # Create PostgreSQL log directory
  systemd.tmpfiles.rules = [
    "d /var/log/postgresql 0755 postgres postgres -"
    "d /var/lib/postgresql/backups 0755 postgres postgres -"
  ];
  
  # Database backup automation
  systemd.timers.postgresql-backup = {
    description = "PostgreSQL database backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };
  
  systemd.services.postgresql-backup = {
    description = "PostgreSQL database backup";
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
    };
    script = ''
      #!/bin/bash
      set -e
      
      BACKUP_DIR="/var/lib/postgresql/backups"
      DATE=$(date +%Y%m%d_%H%M%S)
      
      # Create backup directory if it doesn't exist
      mkdir -p "$BACKUP_DIR"
      
      # Function to backup a database
      backup_database() {
        local db_name=$1
        local backup_file="$BACKUP_DIR/''${db_name}_$DATE.sql.gz"
        
        echo "Backing up database: $db_name"
        ${pkgs.postgresql_15}/bin/pg_dump -h localhost -U postgres "$db_name" | gzip > "$backup_file"
        
        if [ $? -eq 0 ]; then
          echo "Successfully backed up $db_name to $backup_file"
        else
          echo "Failed to backup $db_name" >&2
          return 1
        fi
      }
      
      # Backup all development databases
      backup_database "development"
      backup_database "testing"
      backup_database "staging"
      
      # Also create a full cluster backup
      echo "Creating full cluster backup"
      ${pkgs.postgresql_15}/bin/pg_dumpall -h localhost -U postgres | gzip > "$BACKUP_DIR/full_cluster_$DATE.sql.gz"
      
      # Clean up old backups (keep last 7 days)
      find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete
      
      echo "Backup completed successfully"
    '';
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };
  
  # Database restore script (manual execution)
  environment.systemPackages = with pkgs; [
    postgresql_15
    (pkgs.writeScriptBin "db-restore" ''
      #!/bin/bash
      
      if [ $# -ne 2 ]; then
        echo "Usage: db-restore <database_name> <backup_file>"
        echo "Example: db-restore development /var/lib/postgresql/backups/development_20240101_120000.sql.gz"
        exit 1
      fi
      
      DB_NAME=$1
      BACKUP_FILE=$2
      
      if [ ! -f "$BACKUP_FILE" ]; then
        echo "Error: Backup file $BACKUP_FILE not found"
        exit 1
      fi
      
      echo "Restoring database $DB_NAME from $BACKUP_FILE"
      echo "This will DROP and recreate the database. Are you sure? (y/N)"
      read -r response
      
      if [[ "$response" =~ ^[Yy]$ ]]; then
        # Drop and recreate database
        sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;"
        sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER developer;"
        
        # Restore from backup
        if [[ "$BACKUP_FILE" == *.gz ]]; then
          zcat "$BACKUP_FILE" | sudo -u postgres psql "$DB_NAME"
        else
          sudo -u postgres psql "$DB_NAME" < "$BACKUP_FILE"
        fi
        
        echo "Database $DB_NAME restored successfully"
      else
        echo "Restore cancelled"
      fi
    '')
    
    (pkgs.writeScriptBin "db-status" ''
      #!/bin/bash
      
      echo "=== PostgreSQL Status ==="
      systemctl status postgresql.service --no-pager -l
      
      echo -e "\n=== Database List ==="
      sudo -u postgres psql -l
      
      echo -e "\n=== Connection Test ==="
      sudo -u postgres psql -c "SELECT version();"
      
      echo -e "\n=== Recent Backups ==="
      ls -la /var/lib/postgresql/backups/ | tail -10
      
      echo -e "\n=== Disk Usage ==="
      du -sh /var/lib/postgresql/
    '')
  ];
  
  # Ensure PostgreSQL starts after network is available
  systemd.services.postgresql = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}