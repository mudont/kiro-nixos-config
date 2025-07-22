# Network and firewall configuration
{ config, pkgs, ... }:

{
  # Hostname is set in main configuration.nix
  
  # Enable NetworkManager for network management
  networking.networkmanager.enable = true;
  
  # DNS configuration
  networking.nameservers = [ "192.168.1.1" ];
  
  # Firewall configuration
  networking.firewall = {
    enable = true;
    
    # TCP ports allowed from anywhere
    allowedTCPPorts = [
      80    # HTTP (will redirect to HTTPS)
      443   # HTTPS
      139   # NetBIOS (for Samba)
      445   # SMB (for Samba)
    ];
    
    # UDP ports allowed from anywhere
    allowedUDPPorts = [
      137   # NetBIOS Name Service
      138   # NetBIOS Datagram Service
      5353  # mDNS for network discovery
    ];
    
    # Interfaces configuration for local network restrictions
    interfaces = {
      # Allow SSH and RDP only from local network interfaces
      # This will be automatically applied to the primary network interface
    };
    
    # Custom firewall rules for more granular control
    extraCommands = ''
      # Allow SSH from local network only (assuming 192.168.0.0/16 and 10.0.0.0/8)
      iptables -A nixos-fw -p tcp --dport 22 -s 192.168.0.0/16 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 22 -s 10.0.0.0/8 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 22 -s 172.16.0.0/12 -j ACCEPT
      
      # Allow RDP from local network only
      iptables -A nixos-fw -p tcp --dport 3389 -s 192.168.0.0/16 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 3389 -s 10.0.0.0/8 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 3389 -s 172.16.0.0/12 -j ACCEPT
      
      # Allow Prometheus and monitoring services from local network only
      iptables -A nixos-fw -p tcp --dport 9090 -s 192.168.0.0/16 -j ACCEPT  # Prometheus
      iptables -A nixos-fw -p tcp --dport 9090 -s 10.0.0.0/8 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 9090 -s 172.16.0.0/12 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 9100 -s 192.168.0.0/16 -j ACCEPT  # Node Exporter
      iptables -A nixos-fw -p tcp --dport 9100 -s 10.0.0.0/8 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 9100 -s 172.16.0.0/12 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 3000 -s 192.168.0.0/16 -j ACCEPT  # Grafana (for task 7.2)
      iptables -A nixos-fw -p tcp --dport 3000 -s 10.0.0.0/8 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 3000 -s 172.16.0.0/12 -j ACCEPT
      
      # Allow PostgreSQL only from localhost
      iptables -A nixos-fw -p tcp --dport 5432 -s 127.0.0.1 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 5432 -j DROP
      
      # Rate limiting for Samba connections from internet (non-local networks)
      # Allow unlimited connections from local networks
      iptables -A nixos-fw -p tcp --dport 445 -s 192.168.0.0/16 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 445 -s 10.0.0.0/8 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 445 -s 172.16.0.0/12 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 139 -s 192.168.0.0/16 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 139 -s 10.0.0.0/8 -j ACCEPT
      iptables -A nixos-fw -p tcp --dport 139 -s 172.16.0.0/12 -j ACCEPT
      
      # Rate limit Samba connections from internet (max 5 connections per minute per IP)
      iptables -A nixos-fw -p tcp --dport 445 -m recent --name samba_limit --set
      iptables -A nixos-fw -p tcp --dport 445 -m recent --name samba_limit --update --seconds 60 --hitcount 6 -j DROP
      iptables -A nixos-fw -p tcp --dport 139 -m recent --name samba_limit --update --seconds 60 --hitcount 6 -j DROP
      
      # Connection limiting for internet Samba access (max 10 concurrent connections)
      iptables -A nixos-fw -p tcp --dport 445 -m connlimit --connlimit-above 10 --connlimit-mask 32 -j DROP
      iptables -A nixos-fw -p tcp --dport 139 -m connlimit --connlimit-above 10 --connlimit-mask 32 -j DROP
    '';
    
    extraStopCommands = ''
      # Clean up custom rules when stopping firewall
      iptables -D nixos-fw -p tcp --dport 22 -s 192.168.0.0/16 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 22 -s 10.0.0.0/8 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 22 -s 172.16.0.0/12 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 3389 -s 192.168.0.0/16 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 3389 -s 10.0.0.0/8 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 3389 -s 172.16.0.0/12 -j ACCEPT 2>/dev/null || true
      
      # Clean up monitoring service firewall rules
      iptables -D nixos-fw -p tcp --dport 9090 -s 192.168.0.0/16 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 9090 -s 10.0.0.0/8 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 9090 -s 172.16.0.0/12 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 9100 -s 192.168.0.0/16 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 9100 -s 10.0.0.0/8 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 9100 -s 172.16.0.0/12 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 3000 -s 192.168.0.0/16 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 3000 -s 10.0.0.0/8 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 3000 -s 172.16.0.0/12 -j ACCEPT 2>/dev/null || true
      
      iptables -D nixos-fw -p tcp --dport 5432 -s 127.0.0.1 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 5432 -j DROP 2>/dev/null || true
      
      # Clean up Samba firewall rules
      iptables -D nixos-fw -p tcp --dport 445 -s 192.168.0.0/16 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 445 -s 10.0.0.0/8 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 445 -s 172.16.0.0/12 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 139 -s 192.168.0.0/16 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 139 -s 10.0.0.0/8 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 139 -s 172.16.0.0/12 -j ACCEPT 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 445 -m recent --name samba_limit --set 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 445 -m recent --name samba_limit --update --seconds 60 --hitcount 6 -j DROP 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 139 -m recent --name samba_limit --update --seconds 60 --hitcount 6 -j DROP 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 445 -m connlimit --connlimit-above 10 --connlimit-mask 32 -j DROP 2>/dev/null || true
      iptables -D nixos-fw -p tcp --dport 139 -m connlimit --connlimit-above 10 --connlimit-mask 32 -j DROP 2>/dev/null || true
    '';
  };
  
  # Enable SSH with security settings
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
      AllowUsers = [ "murali" ]; # Only allow specific user
    };
    # Additional security settings
    extraConfig = ''
      ClientAliveInterval 300
      ClientAliveCountMax 2
      MaxAuthTries 3
      MaxSessions 10
    '';
  };
  
  # Enable fail2ban for additional security
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      multipliers = "2 4 8 16 32 64";
      maxtime = "168h"; # 1 week
    };
  };
  
  # Enable Avahi for network discovery (needed for Samba)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };
}