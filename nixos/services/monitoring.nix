# Monitoring and logging configuration
{ config, pkgs, ... }:

{
  # Prometheus metrics collection server
  services.prometheus = {
    enable = true;
    port = 9090;
    
    # Prometheus configuration
    globalConfig = {
      scrape_interval = "15s";
      evaluation_interval = "15s";
    };
    
    # Scrape configurations for collecting metrics
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [{
          targets = [ "localhost:9090" ];
        }];
      }
      {
        job_name = "node-exporter";
        static_configs = [{
          targets = [ "localhost:9100" ];
        }];
      }
      {
        job_name = "nginx";
        static_configs = [{
          targets = [ "localhost:9113" ];
        }];
      }
      {
        job_name = "postgres";
        static_configs = [{
          targets = [ "localhost:9187" ];
        }];
      }
    ];
    
    # Rules for alerting (basic system alerts)
    ruleFiles = [
      (pkgs.writeText "prometheus-rules.yml" ''
        groups:
          - name: system_alerts
            rules:
              - alert: HighCPUUsage
                expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "High CPU usage detected"
                  description: "CPU usage is above 80% for more than 5 minutes"
              
              - alert: HighMemoryUsage
                expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "High memory usage detected"
                  description: "Memory usage is above 85% for more than 5 minutes"
              
              - alert: LowDiskSpace
                expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10
                for: 1m
                labels:
                  severity: critical
                annotations:
                  summary: "Low disk space on root filesystem"
                  description: "Root filesystem has less than 10% free space"
              
              - alert: ServiceDown
                expr: up == 0
                for: 1m
                labels:
                  severity: critical
                annotations:
                  summary: "Service is down"
                  description: "{{ $labels.job }} service is down"
      '')
    ];
    
    # Web configuration
    webExternalUrl = "http://localhost:9090";
    
    # Storage configuration
    retentionTime = "30d";
    
    # Enable admin API for management
    extraFlags = [
      "--web.enable-admin-api"
      "--storage.tsdb.wal-compression"
    ];
  };
  
  # Node Exporter for detailed system metrics
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    
    # Enable additional collectors for comprehensive monitoring
    enabledCollectors = [
      "systemd"
      "processes"
      "interrupts"
      "ksmd"
      "logind"
      "meminfo_numa"
      "mountstats"
      "network_route"
      "perf"
      "tcpstat"
      "wifi"
    ];
    
    # Disable collectors that might be problematic or unnecessary
    disabledCollectors = [
      # textfile collector is enabled for custom development metrics
    ];
    
    # Additional flags for node exporter
    extraFlags = [
      "--collector.systemd.unit-whitelist=(sshd|nginx|postgresql|prometheus|grafana|xrdp|smbd|nmbd)\\.service"
      "--collector.filesystem.ignored-mount-points=^/(dev|proc|sys|var/lib/docker/.+)($|/)"
      "--collector.filesystem.ignored-fs-types=^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|squashfs|sysfs|tracefs)$"
      "--collector.textfile.directory=/var/lib/prometheus-node-exporter-text-files"
    ];
  };
  
  # Nginx Prometheus Exporter for web server metrics
  services.prometheus.exporters.nginx = {
    enable = true;
    port = 9113;
    scrapeUri = "http://localhost/nginx_status";
  };
  
  # PostgreSQL Exporter for database metrics
  services.prometheus.exporters.postgres = {
    enable = true;
    port = 9187;
    dataSourceName = "postgresql://prometheus_exporter:monitoring_pass@localhost:5432/postgres?sslmode=require";
  };
  
  # Custom development metrics collection script
  systemd.services.dev-metrics-collector = {
    description = "Development Environment Metrics Collector";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      User = "prometheus";
      Group = "prometheus";
      ExecStart = pkgs.writeShellScript "dev-metrics-collector" ''
        #!/bin/bash
        
        # Create metrics directory if it doesn't exist
        mkdir -p /var/lib/prometheus-node-exporter-text-files
        
        # Collect development environment metrics
        METRICS_FILE="/var/lib/prometheus-node-exporter-text-files/dev_metrics.prom"
        
        # Docker container count
        if command -v docker >/dev/null 2>&1; then
          DOCKER_CONTAINERS=$(docker ps -q | wc -l)
          echo "dev_docker_containers_running $DOCKER_CONTAINERS" > "$METRICS_FILE"
        fi
        
        # Git repositories count (in common development directories)
        GIT_REPOS=0
        for dir in /home/*/dev /home/*/projects /home/*/src; do
          if [ -d "$dir" ]; then
            GIT_REPOS=$((GIT_REPOS + $(find "$dir" -name ".git" -type d 2>/dev/null | wc -l)))
          fi
        done
        echo "dev_git_repositories_total $GIT_REPOS" >> "$METRICS_FILE"
        
        # Development services status
        for service in docker postgresql nginx samba; do
          if systemctl is-active --quiet "$service"; then
            echo "dev_service_status{service=\"$service\"} 1" >> "$METRICS_FILE"
          else
            echo "dev_service_status{service=\"$service\"} 0" >> "$METRICS_FILE"
          fi
        done
        
        # Log file sizes for development services
        for log in /var/log/nginx/access.log /var/log/nginx/error.log; do
          if [ -f "$log" ]; then
            SIZE=$(stat -c%s "$log" 2>/dev/null || echo 0)
            LOG_NAME=$(basename "$log" .log)
            echo "dev_log_file_size_bytes{log=\"$LOG_NAME\"} $SIZE" >> "$METRICS_FILE"
          fi
        done
        
        # Set proper permissions
        chown prometheus:prometheus "$METRICS_FILE"
      '';
    };
  };
  
  # Timer to run development metrics collection every 5 minutes
  systemd.timers.dev-metrics-collector = {
    description = "Run development metrics collector every 5 minutes";
    wantedBy = [ "timers.target" ];
    
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      Unit = "dev-metrics-collector.service";
    };
  };
  
  # Grafana visualization and dashboards
  services.grafana = {
    enable = true;
    
    # Basic configuration
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        domain = "localhost";
        root_url = "http://localhost:3000/";
        serve_from_sub_path = false;
      };
      
      # Database configuration (use SQLite for simplicity)
      database = {
        type = "sqlite3";
        path = "/var/lib/grafana/grafana.db";
      };
      
      # Security settings
      security = {
        admin_user = "admin";
        admin_password = "admin"; # Change this in production
        secret_key = "grafana_secret_key_change_me";
        disable_gravatar = true;
        cookie_secure = false; # Set to true when using HTTPS
        cookie_samesite = "lax";
      };
      
      # Users and authentication
      users = {
        allow_sign_up = false;
        allow_org_create = false;
        auto_assign_org = true;
        auto_assign_org_role = "Viewer";
        default_theme = "dark";
      };
      
      # Anonymous access (disabled for security)
      "auth.anonymous" = {
        enabled = false;
      };
      
      # Logging
      log = {
        mode = "file";
        level = "info";
      };
      
      # Alerting
      alerting = {
        enabled = true;
        execute_alerts = true;
      };
      
      # Unified alerting
      "unified_alerting" = {
        enabled = true;
      };
      
      # Plugins
      plugins = {
        allow_loading_unsigned_plugins = "";
        plugin_admin_enabled = true;
      };
      
      # Feature toggles
      feature_toggles = {
        enable = "ngalert";
      };
    };
    
    # Data source provisioning
    provision = {
      enable = true;
      
      # Configure Prometheus as data source
      datasources.settings = {
        apiVersion = 1;
        datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://localhost:9090";
            isDefault = true;
            editable = true;
            jsonData = {
              timeInterval = "15s";
              queryTimeout = "60s";
              httpMethod = "POST";
            };
          }
        ];
      };
      
      # Dashboard provisioning
      dashboards.settings = {
        apiVersion = 1;
        providers = [
          {
            name = "System Dashboards";
            type = "file";
            disableDeletion = false;
            updateIntervalSeconds = 30;
            allowUiUpdates = true;
            options = {
              path = "/var/lib/grafana/dashboards";
            };
          }
        ];
      };
    };
  };
  
  # Create Grafana dashboards
  systemd.services.grafana-setup-dashboards = {
    description = "Setup Grafana dashboards";
    wantedBy = [ "multi-user.target" ];
    after = [ "grafana.service" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "grafana";
      Group = "grafana";
    };
    
    script = ''
      # Create dashboards directory
      mkdir -p /var/lib/grafana/dashboards
      
      # System Overview Dashboard
      cat > /var/lib/grafana/dashboards/system-overview.json << 'EOF'
      {
        "dashboard": {
          "id": null,
          "title": "System Overview",
          "tags": ["system", "overview"],
          "timezone": "browser",
          "panels": [
            {
              "id": 1,
              "title": "CPU Usage",
              "type": "stat",
              "targets": [
                {
                  "expr": "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
                  "legendFormat": "CPU Usage %"
                }
              ],
              "fieldConfig": {
                "defaults": {
                  "unit": "percent",
                  "min": 0,
                  "max": 100,
                  "thresholds": {
                    "steps": [
                      {"color": "green", "value": null},
                      {"color": "yellow", "value": 70},
                      {"color": "red", "value": 90}
                    ]
                  }
                }
              },
              "gridPos": {"h": 8, "w": 6, "x": 0, "y": 0}
            },
            {
              "id": 2,
              "title": "Memory Usage",
              "type": "stat",
              "targets": [
                {
                  "expr": "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100",
                  "legendFormat": "Memory Usage %"
                }
              ],
              "fieldConfig": {
                "defaults": {
                  "unit": "percent",
                  "min": 0,
                  "max": 100,
                  "thresholds": {
                    "steps": [
                      {"color": "green", "value": null},
                      {"color": "yellow", "value": 70},
                      {"color": "red", "value": 85}
                    ]
                  }
                }
              },
              "gridPos": {"h": 8, "w": 6, "x": 6, "y": 0}
            },
            {
              "id": 3,
              "title": "Disk Usage",
              "type": "stat",
              "targets": [
                {
                  "expr": "(node_filesystem_size_bytes{mountpoint=\"/\"} - node_filesystem_avail_bytes{mountpoint=\"/\"}) / node_filesystem_size_bytes{mountpoint=\"/\"} * 100",
                  "legendFormat": "Root Disk Usage %"
                }
              ],
              "fieldConfig": {
                "defaults": {
                  "unit": "percent",
                  "min": 0,
                  "max": 100,
                  "thresholds": {
                    "steps": [
                      {"color": "green", "value": null},
                      {"color": "yellow", "value": 80},
                      {"color": "red", "value": 90}
                    ]
                  }
                }
              },
              "gridPos": {"h": 8, "w": 6, "x": 12, "y": 0}
            },
            {
              "id": 4,
              "title": "System Load",
              "type": "stat",
              "targets": [
                {
                  "expr": "node_load1",
                  "legendFormat": "1m Load"
                }
              ],
              "fieldConfig": {
                "defaults": {
                  "unit": "short",
                  "thresholds": {
                    "steps": [
                      {"color": "green", "value": null},
                      {"color": "yellow", "value": 2},
                      {"color": "red", "value": 4}
                    ]
                  }
                }
              },
              "gridPos": {"h": 8, "w": 6, "x": 18, "y": 0}
            },
            {
              "id": 5,
              "title": "CPU Usage Over Time",
              "type": "timeseries",
              "targets": [
                {
                  "expr": "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
                  "legendFormat": "CPU Usage %"
                }
              ],
              "fieldConfig": {
                "defaults": {
                  "unit": "percent",
                  "min": 0,
                  "max": 100
                }
              },
              "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
            },
            {
              "id": 6,
              "title": "Memory Usage Over Time",
              "type": "timeseries",
              "targets": [
                {
                  "expr": "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / 1024 / 1024 / 1024",
                  "legendFormat": "Used Memory (GB)"
                },
                {
                  "expr": "node_memory_MemTotal_bytes / 1024 / 1024 / 1024",
                  "legendFormat": "Total Memory (GB)"
                }
              ],
              "fieldConfig": {
                "defaults": {
                  "unit": "decgbytes"
                }
              },
              "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
            }
          ],
          "time": {"from": "now-1h", "to": "now"},
          "refresh": "30s",
          "schemaVersion": 30,
          "version": 1
        }
      }
      EOF
      
      # Network and Disk I/O Dashboard
      cat > /var/lib/grafana/dashboards/network-disk-io.json << 'EOF'
      {
        "dashboard": {
          "id": null,
          "title": "Network & Disk I/O",
          "tags": ["network", "disk", "io"],
          "timezone": "browser",
          "panels": [
            {
              "id": 1,
              "title": "Network Traffic",
              "type": "timeseries",
              "targets": [
                {
                  "expr": "irate(node_network_receive_bytes_total{device!=\"lo\"}[5m]) * 8",
                  "legendFormat": "{{device}} - Receive"
                },
                {
                  "expr": "irate(node_network_transmit_bytes_total{device!=\"lo\"}[5m]) * 8",
                  "legendFormat": "{{device}} - Transmit"
                }
              ],
              "fieldConfig": {
                "defaults": {
                  "unit": "bps"
                }
              },
              "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
            },
            {
              "id": 2,
              "title": "Disk I/O",
              "type": "timeseries",
              "targets": [
                {
                  "expr": "irate(node_disk_read_bytes_total[5m])",
                  "legendFormat": "{{device}} - Read"
                },
                {
                  "expr": "irate(node_disk_written_bytes_total[5m])",
                  "legendFormat": "{{device}} - Write"
                }
              ],
              "fieldConfig": {
                "defaults": {
                  "unit": "Bps"
                }
              },
              "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
            },
            {
              "id": 3,
              "title": "Network Connections",
              "type": "stat",
              "targets": [
                {
                  "expr": "node_netstat_Tcp_CurrEstab",
                  "legendFormat": "Established TCP Connections"
                }
              ],
              "gridPos": {"h": 4, "w": 6, "x": 0, "y": 8}
            },
            {
              "id": 4,
              "title": "Disk IOPS",
              "type": "stat",
              "targets": [
                {
                  "expr": "irate(node_disk_reads_completed_total[5m]) + irate(node_disk_writes_completed_total[5m])",
                  "legendFormat": "Total IOPS"
                }
              ],
              "gridPos": {"h": 4, "w": 6, "x": 6, "y": 8}
            }
          ],
          "time": {"from": "now-1h", "to": "now"},
          "refresh": "30s",
          "schemaVersion": 30,
          "version": 1
        }
      }
      EOF
      
      # Services Dashboard
      cat > /var/lib/grafana/dashboards/services.json << 'EOF'
      {
        "dashboard": {
          "id": null,
          "title": "Services Monitoring",
          "tags": ["services", "monitoring"],
          "timezone": "browser",
          "panels": [
            {
              "id": 1,
              "title": "Service Status",
              "type": "stat",
              "targets": [
                {
                  "expr": "up{job=\"prometheus\"}",
                  "legendFormat": "Prometheus"
                },
                {
                  "expr": "up{job=\"node-exporter\"}",
                  "legendFormat": "Node Exporter"
                },
                {
                  "expr": "up{job=\"nginx\"}",
                  "legendFormat": "Nginx"
                },
                {
                  "expr": "up{job=\"postgres\"}",
                  "legendFormat": "PostgreSQL"
                }
              ],
              "fieldConfig": {
                "defaults": {
                  "mappings": [
                    {"options": {"0": {"text": "DOWN", "color": "red"}}, "type": "value"},
                    {"options": {"1": {"text": "UP", "color": "green"}}, "type": "value"}
                  ]
                }
              },
              "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
            },
            {
              "id": 2,
              "title": "Nginx Requests",
              "type": "timeseries",
              "targets": [
                {
                  "expr": "irate(nginx_http_requests_total[5m])",
                  "legendFormat": "Requests/sec"
                }
              ],
              "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
            },
            {
              "id": 3,
              "title": "PostgreSQL Connections",
              "type": "timeseries",
              "targets": [
                {
                  "expr": "pg_stat_database_numbackends",
                  "legendFormat": "{{datname}} connections"
                }
              ],
              "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
            },
            {
              "id": 4,
              "title": "Development Services",
              "type": "stat",
              "targets": [
                {
                  "expr": "dev_service_status",
                  "legendFormat": "{{service}}"
                }
              ],
              "fieldConfig": {
                "defaults": {
                  "mappings": [
                    {"options": {"0": {"text": "DOWN", "color": "red"}}, "type": "value"},
                    {"options": {"1": {"text": "UP", "color": "green"}}, "type": "value"}
                  ]
                }
              },
              "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
            }
          ],
          "time": {"from": "now-1h", "to": "now"},
          "refresh": "30s",
          "schemaVersion": 30,
          "version": 1
        }
      }
      EOF
      
      # Development Environment Dashboard
      cat > /var/lib/grafana/dashboards/development.json << 'EOF'
      {
        "dashboard": {
          "id": null,
          "title": "Development Environment",
          "tags": ["development", "containers"],
          "timezone": "browser",
          "panels": [
            {
              "id": 1,
              "title": "Docker Containers",
              "type": "stat",
              "targets": [
                {
                  "expr": "dev_docker_containers_running",
                  "legendFormat": "Running Containers"
                }
              ],
              "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0}
            },
            {
              "id": 2,
              "title": "Git Repositories",
              "type": "stat",
              "targets": [
                {
                  "expr": "dev_git_repositories_total",
                  "legendFormat": "Git Repositories"
                }
              ],
              "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0}
            },
            {
              "id": 3,
              "title": "Log File Sizes",
              "type": "timeseries",
              "targets": [
                {
                  "expr": "dev_log_file_size_bytes",
                  "legendFormat": "{{log}} log size"
                }
              ],
              "fieldConfig": {
                "defaults": {
                  "unit": "bytes"
                }
              },
              "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
            },
            {
              "id": 4,
              "title": "System Processes",
              "type": "timeseries",
              "targets": [
                {
                  "expr": "node_procs_running",
                  "legendFormat": "Running Processes"
                },
                {
                  "expr": "node_procs_blocked",
                  "legendFormat": "Blocked Processes"
                }
              ],
              "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4}
            }
          ],
          "time": {"from": "now-1h", "to": "now"},
          "refresh": "30s",
          "schemaVersion": 30,
          "version": 1
        }
      }
      EOF
      
      # Set proper ownership
      chown -R grafana:grafana /var/lib/grafana/dashboards
    '';
  };
  
  # Comprehensive logging system configuration
  
  # Configure systemd journal with persistent storage and rotation
  services.journald.extraConfig = ''
    # Persistent storage
    Storage=persistent
    
    # Journal size limits
    SystemMaxUse=1G
    SystemKeepFree=2G
    SystemMaxFileSize=100M
    SystemMaxFiles=10
    
    # Runtime journal limits
    RuntimeMaxUse=100M
    RuntimeKeepFree=100M
    RuntimeMaxFileSize=50M
    RuntimeMaxFiles=5
    
    # Retention settings
    MaxRetentionSec=30day
    MaxFileSec=1day
    
    # Forward to syslog for additional processing
    ForwardToSyslog=yes
    
    # Compression
    Compress=yes
    
    # Rate limiting
    RateLimitInterval=30s
    RateLimitBurst=10000
  '';
  
  # Enhanced systemd journal configuration (already configured in main config)
  # NixOS uses systemd-journald by default, which is more appropriate than rsyslog
  
  # Log rotation configuration
  services.logrotate = {
    enable = true;
    settings = {
      # Global settings
      header = {
        # Rotate logs weekly
        weekly = true;
        # Keep 4 weeks of logs
        rotate = 4;
        # Create new log files with specific permissions
        create = "0644 root root";
        # Compress old logs
        compress = true;
        # Delay compression until next rotation
        delaycompress = true;
        # Don't rotate empty files
        notifempty = true;
        # Handle missing log files gracefully
        missingok = true;
        # Use date as suffix
        dateext = true;
        # Date format
        dateformat = "-%Y%m%d";
      };
      
      # System logs (handled by systemd journal)
      # Note: These files may not exist since we use systemd-journald
      "/var/log/messages" = {
        rotate = 12;
        monthly = true;
        missingok = true;
      };
      
      "/var/log/secure" = {
        rotate = 12;
        monthly = true;
        missingok = true;
      };
      
      # Service logs
      "/var/log/nginx/*.log" = {
        daily = true;
        rotate = 30;
        postrotate = "systemctl reload nginx";
      };
      
      "/var/log/postgresql/*.log" = {
        daily = true;
        rotate = 7;
        copytruncate = true;
      };
      
      "/var/log/prometheus/*.log" = {
        daily = true;
        rotate = 7;
        copytruncate = true;
      };
      
      "/var/log/grafana/*.log" = {
        daily = true;
        rotate = 7;
        copytruncate = true;
      };
      
      "/var/log/development/*.log" = {
        daily = true;
        rotate = 14;
        copytruncate = true;
      };
      
      "/var/log/json/*.json" = {
        daily = true;
        rotate = 7;
        copytruncate = true;
      };
    };
  };
  
  # Log analysis and search tools
  environment.systemPackages = with pkgs; [
    # Log analysis tools
    lnav          # Advanced log file viewer
    multitail     # Monitor multiple log files
    goaccess      # Web log analyzer (for nginx logs)
    jq            # JSON processor for structured logs
    
    # Search and grep tools
    ripgrep       # Fast text search
    silver-searcher # Another fast search tool
    
    # Log monitoring scripts
    (writeScriptBin "log-monitor" ''
      #!/bin/bash
      
      # Log monitoring script
      case "$1" in
        "errors")
          echo "=== Recent Errors ==="
          journalctl --since "1 hour ago" -p err --no-pager
          ;;
        "services")
          echo "=== Service Status ==="
          for service in nginx postgresql prometheus grafana sshd smbd docker; do
            echo "--- $service ---"
            journalctl -u $service --since "1 hour ago" --no-pager -n 10
          done
          ;;
        "security")
          echo "=== Security Events ==="
          journalctl --since "1 day ago" -u sshd -u fail2ban --no-pager | grep -i "failed\|invalid\|refused\|banned"
          ;;
        "development")
          echo "=== Development Logs ==="
          tail -f /var/log/development/development.log
          ;;
        "nginx")
          echo "=== Nginx Access Logs ==="
          tail -f /var/log/nginx/access.log
          ;;
        "live")
          echo "=== Live System Logs ==="
          journalctl -f
          ;;
        *)
          echo "Usage: log-monitor {errors|services|security|development|nginx|live}"
          echo ""
          echo "  errors      - Show recent error messages"
          echo "  services    - Show recent service logs"
          echo "  security    - Show security-related events"
          echo "  development - Monitor development logs"
          echo "  nginx       - Monitor nginx access logs"
          echo "  live        - Follow live system logs"
          ;;
      esac
    '')
    
    (writeScriptBin "log-search" ''
      #!/bin/bash
      
      if [ $# -eq 0 ]; then
        echo "Usage: log-search <search_term> [time_period]"
        echo "Example: log-search 'error' '1 hour ago'"
        echo "Example: log-search 'failed login' '1 day ago'"
        exit 1
      fi
      
      SEARCH_TERM="$1"
      TIME_PERIOD="''${2:-1 hour ago}"
      
      echo "=== Searching for '$SEARCH_TERM' since $TIME_PERIOD ==="
      echo ""
      
      # Search in journald
      echo "--- Systemd Journal ---"
      journalctl --since "$TIME_PERIOD" --no-pager | grep -i "$SEARCH_TERM" | head -20
      
      echo ""
      echo "--- Log Files ---"
      # Search in log files
      find /var/log -name "*.log" -type f -exec grep -l -i "$SEARCH_TERM" {} \; 2>/dev/null | while read logfile; do
        echo "Found in: $logfile"
        grep -i "$SEARCH_TERM" "$logfile" | tail -5
        echo ""
      done
      
      # Search in JSON logs if they exist
      if [ -d "/var/log/json" ]; then
        echo "--- JSON Logs ---"
        find /var/log/json -name "*.json" -type f -exec jq -r "select(.message | test(\"$SEARCH_TERM\"; \"i\")) | \"\(.timestamp) \(.hostname) \(.message)\"" {} \; 2>/dev/null | head -10
      fi
    '')
    
    (writeScriptBin "log-stats" ''
      #!/bin/bash
      
      echo "=== Log Statistics ==="
      echo ""
      
      # Disk usage
      echo "--- Log Directory Sizes ---"
      du -sh /var/log/* 2>/dev/null | sort -hr | head -10
      echo ""
      
      # Journal size
      echo "--- Journal Size ---"
      journalctl --disk-usage
      echo ""
      
      # Recent activity
      echo "--- Recent Activity (last hour) ---"
      echo "Total log entries: $(journalctl --since '1 hour ago' --no-pager | wc -l)"
      echo "Error entries: $(journalctl --since '1 hour ago' -p err --no-pager | wc -l)"
      echo "Warning entries: $(journalctl --since '1 hour ago' -p warning --no-pager | wc -l)"
      echo ""
      
      # Top services by log volume
      echo "--- Top Services by Log Volume (last hour) ---"
      journalctl --since '1 hour ago' --no-pager -o json | jq -r '._SYSTEMD_UNIT // "unknown"' | sort | uniq -c | sort -nr | head -10
      echo ""
      
      # Log file counts
      echo "--- Log File Counts ---"
      find /var/log -name "*.log" -type f | wc -l | xargs echo "Log files:"
      find /var/log -name "*.gz" -type f | wc -l | xargs echo "Compressed logs:"
    '')
  ];
  
  # Create log directories with proper permissions
  systemd.tmpfiles.rules = [
    # Service-specific log directories
    "d /var/log/nginx 0755 nginx nginx -"
    "d /var/log/postgresql 0755 postgres postgres -"
    "d /var/log/prometheus 0755 prometheus prometheus -"
    "d /var/log/grafana 0755 grafana grafana -"
    "d /var/log/ssh 0755 root root -"
    "d /var/log/samba 0755 root root -"
    "d /var/log/docker 0755 root root -"
    "d /var/log/development 0755 root root -"
    "d /var/log/json 0755 root root -"
    

    
    # Log analysis cache
    "d /var/cache/log-analysis 0755 root root -"
    
    # Prometheus directories
    "d /var/lib/prometheus 0755 prometheus prometheus -"
    "d /var/lib/prometheus-node-exporter-text-files 0755 prometheus prometheus -"
  ];
  
  # Systemd service for log cleanup and maintenance
  systemd.services.log-maintenance = {
    description = "Log maintenance and cleanup";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
    script = ''
      #!/bin/bash
      
      # Clean up old journal files beyond retention policy
      journalctl --vacuum-time=30d
      journalctl --vacuum-size=1G
      
      # Clean up old compressed logs
      find /var/log -name "*.gz" -mtime +30 -delete
      
      # Clean up empty log files
      find /var/log -name "*.log" -size 0 -mtime +1 -delete
      
      # Update log analysis cache
      if command -v goaccess >/dev/null 2>&1; then
        if [ -f /var/log/nginx/access.log ]; then
          goaccess /var/log/nginx/access.log -o /var/cache/log-analysis/nginx-report.html --log-format=COMBINED --html --real-time-html >/dev/null 2>&1 || true
        fi
      fi
      
      echo "Log maintenance completed at $(date)"
    '';
  };
  
  # Timer for log maintenance (run daily)
  systemd.timers.log-maintenance = {
    description = "Daily log maintenance";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };
  
  # Create prometheus user and group
  users.users.prometheus = {
    isSystemUser = true;
    group = "prometheus";
    home = "/var/lib/prometheus";
    createHome = true;
  };
  
  users.groups.prometheus = {};
  

}