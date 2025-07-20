{ config, pkgs, ... }:

{
  # Performance optimization configuration for NixOS home server
  
  # Kernel parameters for performance
  boot.kernel.sysctl = {
    # Network performance
    "net.core.rmem_default" = 262144;
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_default" = 262144;
    "net.core.wmem_max" = 16777216;
    "net.core.netdev_max_backlog" = 5000;
    "net.ipv4.tcp_rmem" = "4096 65536 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.tcp_slow_start_after_idle" = 0;
    "net.ipv4.tcp_tw_reuse" = 1;
    "net.ipv4.tcp_fin_timeout" = 30;
    "net.ipv4.tcp_keepalive_time" = 1200;
    "net.ipv4.tcp_keepalive_probes" = 7;
    "net.ipv4.tcp_keepalive_intvl" = 30;
    "net.ipv4.tcp_max_syn_backlog" = 8192;
    "net.core.somaxconn" = 8192;
    
    # Memory management
    "vm.swappiness" = 10;
    "vm.dirty_ratio" = 15;
    "vm.dirty_background_ratio" = 5;
    "vm.vfs_cache_pressure" = 50;
    "vm.min_free_kbytes" = 65536;
    "vm.overcommit_memory" = 1;
    "vm.overcommit_ratio" = 50;
    
    # File system performance
    "fs.file-max" = 2097152;
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 256;
    
    # Process limits
    "kernel.pid_max" = 4194304;
    "kernel.threads-max" = 4194304;
  };
  
  # I/O scheduler optimization
  boot.kernelParams = [
    "elevator=mq-deadline"  # Better for SSDs
    "transparent_hugepage=madvise"
    "intel_idle.max_cstate=1"  # Reduce CPU latency
    "processor.max_cstate=1"
  ];
  
  # CPU frequency scaling
  powerManagement.cpuFreqGovernor = "performance";
  
  # Enable zram for better memory management
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
  };
  
  # Systemd optimizations
  systemd.extraConfig = ''
    DefaultTimeoutStopSec=10s
    DefaultTimeoutStartSec=10s
    DefaultRestartSec=1s
  '';
  
  # Service-specific optimizations
  systemd.services = {
    # Optimize Nginx
    nginx.serviceConfig = {
      LimitNOFILE = 65536;
      LimitNPROC = 32768;
      OOMScoreAdjust = -100;
    };
    
    # Optimize PostgreSQL
    postgresql.serviceConfig = {
      LimitNOFILE = 65536;
      LimitNPROC = 32768;
      OOMScoreAdjust = -200;
    };
    
    # Optimize Prometheus
    prometheus.serviceConfig = {
      LimitNOFILE = 65536;
      LimitNPROC = 16384;
      OOMScoreAdjust = 100;
    };
    
    # Optimize Grafana
    grafana.serviceConfig = {
      LimitNOFILE = 65536;
      LimitNPROC = 16384;
      OOMScoreAdjust = 100;
    };
    
    # Optimize Docker
    docker.serviceConfig = {
      LimitNOFILE = 1048576;
      LimitNPROC = 1048576;
      OOMScoreAdjust = -500;
    };
  };
  
  # Performance monitoring tools
  environment.systemPackages = with pkgs; [
    htop
    btop
    iotop
    nethogs
    iftop
    nload
    dstat
    sysstat
    perf-tools
    stress-ng
    sysbench
  ];
  
  # Enable performance monitoring services
  services.sysstat.enable = true;
  
  # Optimize journal settings for performance
  services.journald.extraConfig = ''
    SystemMaxUse=1G
    SystemMaxFileSize=100M
    SystemMaxFiles=10
    MaxRetentionSec=1month
    ForwardToSyslog=no
    Compress=yes
  '';
  
  # Optimize tmpfs for performance
  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ 
      "defaults" 
      "size=4G" 
      "mode=1777" 
      "noatime" 
      "nodiratime" 
    ];
  };
  
  # Performance-oriented mount options
  fileSystems."/" = {
    options = [ "noatime" "nodiratime" "commit=60" ];
  };
  
  # Optimize systemd-resolved for performance
  services.resolved = {
    enable = true;
    dnssec = "false";  # Disable for performance
    domains = [ "~." ];
    fallbackDns = [ "8.8.8.8" "1.1.1.1" ];
    extraConfig = ''
      DNS=8.8.8.8 1.1.1.1
      Cache=yes
      CacheFromLocalhost=yes
      DNSStubListener=yes
    '';
  };
  
  # Network interface optimizations
  systemd.network.networks."10-ethernet" = {
    matchConfig.Name = "en*";
    networkConfig = {
      DHCP = "yes";
      IPv6AcceptRA = true;
    };
    dhcpV4Config = {
      UseDNS = false;  # Use systemd-resolved instead
      UseNTP = false;  # Use systemd-timesyncd instead
    };
    linkConfig = {
      # Enable hardware offloading
      GenericSegmentationOffload = true;
      TCPSegmentationOffload = true;
      TCP6SegmentationOffload = true;
      GenericReceiveOffload = true;
      LargeReceiveOffload = true;
    };
  };
  
  # Time synchronization optimization
  services.timesyncd = {
    enable = true;
    servers = [
      "time.nist.gov"
      "pool.ntp.org"
    ];
  };
  
  # Optimize udev rules for performance
  services.udev.extraRules = ''
    # SSD optimization
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/read_ahead_kb}="0"
    
    # Network interface optimization
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="eth*", RUN+="/bin/sh -c 'echo 1 > /sys/class/net/%k/queues/rx-0/rps_cpus'"
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="eth*", RUN+="/bin/sh -c 'echo 32768 > /proc/sys/net/core/rps_sock_flow_entries'"
  '';
  
  # Optimize systemd services startup
  systemd.services = {
    # Parallel service startup
    "systemd-networkd-wait-online".enable = false;
    "NetworkManager-wait-online".enable = false;
    
    # Performance tuning service
    performance-tuning = {
      description = "Apply performance tuning";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeScript "performance-tuning" ''
          #!${pkgs.bash}/bin/bash
          
          # CPU performance tuning
          echo "Applying CPU performance tuning..."
          for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            [ -f "$cpu" ] && echo performance > "$cpu"
          done
          
          # Network interface tuning
          echo "Applying network interface tuning..."
          for iface in $(ls /sys/class/net/ | grep -E '^(eth|en)'); do
            # Enable hardware offloading if available
            ethtool -K "$iface" gso on 2>/dev/null || true
            ethtool -K "$iface" tso on 2>/dev/null || true
            ethtool -K "$iface" gro on 2>/dev/null || true
            ethtool -K "$iface" lro on 2>/dev/null || true
            
            # Set ring buffer sizes
            ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true
          done
          
          # I/O scheduler tuning
          echo "Applying I/O scheduler tuning..."
          for disk in $(lsblk -d -n -o NAME | grep -E '^(sd|nvme)'); do
            echo mq-deadline > "/sys/block/$disk/queue/scheduler" 2>/dev/null || true
            echo 0 > "/sys/block/$disk/queue/read_ahead_kb" 2>/dev/null || true
            echo 2 > "/sys/block/$disk/queue/rq_affinity" 2>/dev/null || true
          done
          
          echo "Performance tuning applied successfully"
        '';
        StandardOutput = "journal";
      };
    };
    
    # System optimization monitoring
    performance-monitor = {
      description = "Monitor system performance";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeScript "performance-monitor" ''
          #!${pkgs.bash}/bin/bash
          
          echo "=== System Performance Report ==="
          echo "Generated: $(date)"
          echo
          
          echo "CPU Information:"
          echo "---------------"
          lscpu | grep -E "(Model name|CPU\(s\)|Thread|Core|Socket)"
          echo
          
          echo "Memory Usage:"
          echo "-------------"
          free -h
          echo
          
          echo "Disk I/O:"
          echo "---------"
          iostat -x 1 1 | tail -n +4
          echo
          
          echo "Network Statistics:"
          echo "-------------------"
          ss -s
          echo
          
          echo "Load Average:"
          echo "-------------"
          uptime
          echo
          
          echo "Top Processes by CPU:"
          echo "---------------------"
          ps aux --sort=-%cpu | head -10
          echo
          
          echo "Top Processes by Memory:"
          echo "------------------------"
          ps aux --sort=-%mem | head -10
          echo
        '';
        StandardOutput = "journal";
      };
    };
  };
  
  # Performance monitoring timer
  systemd.timers.performance-monitor = {
    description = "Run performance monitoring hourly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };
  
  # Optimize systemd-logind for performance
  services.logind = {
    lidSwitch = "ignore";
    lidSwitchExternalPower = "ignore";
    extraConfig = ''
      HandlePowerKey=ignore
      HandleSuspendKey=ignore
      HandleHibernateKey=ignore
      IdleAction=ignore
      RuntimeDirectorySize=10%
    '';
  };
  
  # Disable unnecessary services for performance
  systemd.services = {
    "systemd-random-seed".enable = false;
    "systemd-backlight@".enable = false;
  };
  
  # Optimize kernel modules loading
  boot.kernelModules = [
    "tcp_bbr"  # Better congestion control
    "zstd"     # Better compression
  ];
  
  # Performance-oriented environment variables
  environment.variables = {
    # Optimize compilation
    MAKEFLAGS = "-j$(nproc)";
    
    # Optimize Node.js
    NODE_OPTIONS = "--max-old-space-size=4096";
    
    # Optimize Python
    PYTHONUNBUFFERED = "1";
    PYTHONDONTWRITEBYTECODE = "1";
  };
}