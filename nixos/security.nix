{ config, pkgs, ... }:

{
  # Security hardening configuration for NixOS home server
  
  # Kernel security parameters
  boot.kernel.sysctl = {
    # Network security
    "net.ipv4.ip_forward" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_rfc1337" = 1;
    
    # IPv6 security
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
    
    # Memory protection
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.yama.ptrace_scope" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    
    # File system security
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
    "fs.suid_dumpable" = 0;
    
    # Process security
    "kernel.core_uses_pid" = 1;
    "kernel.ctrl-alt-del" = 0;
  };
  
  # Boot security
  boot.tmp.cleanOnBoot = true;
  boot.kernel.sysctl."kernel.unprivileged_userns_clone" = 0;
  
  # Security packages
  environment.systemPackages = with pkgs; [
    fail2ban
    lynis
    chkrootkit
    clamav
    aide
    # rkhunter - not available in current nixpkgs
  ];
  
  # Fail2ban configuration
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      multipliers = "2 4 8 16 32 64";
      maxtime = "168h"; # 1 week
      overalljails = true;
    };
    
    # Basic jail configuration - NixOS fail2ban uses simplified configuration
    jails = {
      # SSH protection (enabled by default)
      sshd.enabled = true;
    };
  };
  
  # Antivirus configuration
  services.clamav = {
    daemon.enable = true;
    updater.enable = true;
    updater.frequency = 24; # Update every 24 hours
    scanner = {
      enable = true;
      scanDirectories = [
        "/home"
        "/srv"
        "/var/www"
      ];
      interval = "daily";
    };
  };
  
  # File integrity monitoring with AIDE
  # Note: AIDE is available as a package but not as a service in NixOS
  # Manual configuration required in /etc/aide/aide.conf
  environment.etc."aide/aide.conf".text = ''
    # AIDE configuration for file integrity monitoring
    database_in = file:/var/lib/aide/aide.db
    database_out = file:/var/lib/aide/aide.db.new
    database_new = file:/var/lib/aide/aide.db.new
    gzip_dbout = yes
    
    # Rules
    All = p+i+n+u+g+s+m+c+md5+sha1+sha256+rmd160+tiger+haval+gost+crc32
    Norm = All-c
    
    # Directories to monitor
    /etc Norm
    /bin Norm
    /sbin Norm
    /usr/bin Norm
    /usr/sbin Norm
    /var/log p+i+n+u+g+s+m+c+md5+sha1
    
    # Exclude temporary and variable files
    !/var/log/.*\.log$
    !/tmp
    !/proc
    !/sys
    !/dev
  '';
  
  # Create AIDE directories
  systemd.tmpfiles.rules = [
    "d /var/lib/aide 0755 root root -"
  ];
  
  # Automatic security updates
  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos";
    flags = [
      "--update-input" "nixpkgs"
      "--commit-lock-file"
    ];
    dates = "04:00";
    randomizedDelaySec = "45min";
    allowReboot = false; # Don't auto-reboot, require manual intervention
  };
  
  # Security-focused systemd services
  systemd.services = {
    # Secure boot verification
    secure-boot-check = {
      description = "Check secure boot status";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'if [ -d /sys/firmware/efi ]; then echo \"UEFI boot detected\"; else echo \"Legacy boot detected\"; fi'";
        StandardOutput = "journal";
      };
    };
    
    # File permission audit
    file-permission-audit = {
      description = "Audit critical file permissions";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeScript "file-permission-audit" ''
          #!${pkgs.bash}/bin/bash
          
          # Check critical file permissions
          echo "Auditing file permissions..."
          
          # Check /etc/shadow
          if [ "$(stat -c %a /etc/shadow)" != "640" ]; then
            echo "WARNING: /etc/shadow has incorrect permissions"
          fi
          
          # Check SSH host keys
          for key in /etc/ssh/ssh_host_*_key; do
            if [ -f "$key" ] && [ "$(stat -c %a "$key")" != "600" ]; then
              echo "WARNING: $key has incorrect permissions"
            fi
          done
          
          # Check sudo configuration
          if [ "$(stat -c %a /etc/sudoers)" != "440" ]; then
            echo "WARNING: /etc/sudoers has incorrect permissions"
          fi
          
          echo "File permission audit completed"
        '';
        StandardOutput = "journal";
      };
    };
    
    # Weekly security scan
    security-scan = {
      description = "Weekly security scan";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeScript "security-scan" ''
          #!${pkgs.bash}/bin/bash
          
          echo "Starting security scan..."
          
          # Run Lynis security audit
          ${pkgs.lynis}/bin/lynis audit system --quick --quiet
          
          # Run rootkit scan with chkrootkit (rkhunter not available)
          ${pkgs.chkrootkit}/bin/chkrootkit
          
          # Check for failed login attempts
          echo "Recent failed login attempts:"
          journalctl --since "7 days ago" | grep "Failed password" | tail -10
          
          # Check for suspicious network connections
          echo "Current network connections:"
          ss -tuln | grep LISTEN
          
          echo "Security scan completed"
        '';
        StandardOutput = "journal";
      };
    };
    
    # Harden SSH service
    sshd.serviceConfig = {
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
    };
    
    # Harden Nginx service
    nginx.serviceConfig = {
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      ReadWritePaths = [ "/var/log/nginx" "/var/cache/nginx" ];
    };
  };
  
  # Security-focused systemd timers
  systemd.timers = {
    file-permission-audit = {
      description = "Run file permission audit daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
    
    security-scan = {
      description = "Run security scan weekly";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "2h";
      };
    };
  };
  

  
  # Secure mount options
  fileSystems = {
    "/tmp" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "nodev" "nosuid" "noexec" "size=2G" ];
    };
  };
  
  # AppArmor security framework
  security.apparmor = {
    enable = true;
    killUnconfinedConfinables = true;
  };
  
  # Audit framework
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = [
      # Monitor authentication events
      "-w /etc/passwd -p wa -k identity"
      "-w /etc/group -p wa -k identity"
      "-w /etc/shadow -p wa -k identity"
      "-w /etc/sudoers -p wa -k identity"
      
      # Monitor system configuration changes
      "-w /etc/nixos -p wa -k config-changes"
      "-w /etc/ssh/sshd_config -p wa -k ssh-config"
      
      # Monitor network configuration
      "-w /etc/hosts -p wa -k network-config"
      "-w /etc/resolv.conf -p wa -k network-config"
      
      # Monitor privilege escalation
      "-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=-1 -k privilege-escalation"
      "-a always,exit -F arch=b32 -S execve -F euid=0 -F auid>=1000 -F auid!=-1 -k privilege-escalation"
      
      # Monitor file access
      "-a always,exit -F arch=b64 -S open,openat,creat -F exit=-EACCES -k file-access-denied"
      "-a always,exit -F arch=b32 -S open,openat,creat -F exit=-EACCES -k file-access-denied"
    ];
  };
  
  # Disable unused network protocols
  boot.blacklistedKernelModules = [
    "dccp"
    "sctp"
    "rds"
    "tipc"
    "n-hdlc"
    "ax25"
    "netrom"
    "x25"
    "rose"
    "decnet"
    "econet"
    "af_802154"
    "ipx"
    "appletalk"
    "psnap"
    "p8023"
    "p8022"
    "can"
    "atm"
  ];
  
  # Secure shared memory
  boot.specialFileSystems."/dev/shm".options = [ "nodev" "nosuid" "noexec" ];
  
  # Security limits
  security.pam.loginLimits = [
    {
      domain = "*";
      type = "hard";
      item = "core";
      value = "0";
    }
    {
      domain = "*";
      type = "hard";
      item = "nofile";
      value = "65536";
    }
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "65536";
    }
  ];
  
  # Disable core dumps globally
  systemd.coredump.enable = false;
}