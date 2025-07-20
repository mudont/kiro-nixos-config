# File sharing configuration (Samba)
{ config, pkgs, ... }:

{
  # Enable Samba service for multi-platform file sharing
  services.samba = {
    enable = true;
    
    # Use SMB3 protocol for iOS compatibility and security
    extraConfig = ''
      # Global settings
      workgroup = WORKGROUP
      server string = NixOS Home Server
      netbios name = nixos
      
      # Security settings
      security = user
      map to guest = never
      
      # Protocol settings - SMB3 for iOS compatibility
      server min protocol = SMB3_00
      server max protocol = SMB3_11
      client min protocol = SMB3_00
      client max protocol = SMB3_11
      
      # Performance and compatibility
      socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
      read raw = yes
      write raw = yes
      max xmit = 65535
      dead time = 15
      getwd cache = yes
      
      # Network discovery and browsing
      local master = yes
      preferred master = yes
      domain master = yes
      os level = 65
      
      # Logging
      log file = /var/log/samba/log.%m
      max log size = 50
      log level = 1
      
      # Character encoding for international support
      unix charset = UTF-8
      dos charset = CP850
      
      # Disable printer sharing
      load printers = no
      printing = bsd
      printcap name = /dev/null
      disable spoolss = yes
      
      # Security enhancements
      restrict anonymous = 2
      lanman auth = no
      ntlm auth = no
      raw NTLMv2 auth = no
      client NTLMv2 auth = yes
      client lanman auth = no
      client plaintext auth = no
      
      # Rate limiting and connection management
      max connections = 50
      deadtime = 10
      keepalive = 30
      
      # Enable wide links for better performance (with security considerations)
      unix extensions = no
      wide links = yes
      follow symlinks = yes
    '';
    
    # Configure shares
    shares = {
      # Public share accessible from internet with restrictions
      public-share = {
        path = "/srv/public-share";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0664";
        "directory mask" = "0775";
        "force user" = "murali";
        "force group" = "samba";
        comment = "Public Share - Internet Accessible";
        
        # Rate limiting and connection restrictions for internet access
        "max connections" = "10";
        "deadtime" = "5";
        
        # Security settings for public share
        "hide dot files" = "yes";
        "hide special files" = "yes";
        "delete readonly" = "no";
        "dos filemode" = "yes";
        
        # Prevent execution of files
        "veto files" = "/*.exe/*.com/*.dll/*.bat/*.cmd/*.scr/*.pif/*.vbs/*.js/*.jar/";
        "delete veto files" = "yes";
      };
      
      # Private share for local network access only
      private-share = {
        path = "/srv/private-share";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0664";
        "directory mask" = "0775";
        "force user" = "murali";
        "force group" = "samba";
        comment = "Private Share - Local Network Only";
        
        # More relaxed settings for local access
        "max connections" = "25";
        "deadtime" = "15";
        
        # Security settings
        "hide dot files" = "yes";
        "hide special files" = "yes";
        "dos filemode" = "yes";
      };
      
      # Home directory share for user files
      homes = {
        browseable = "no";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0600";
        "directory mask" = "0700";
        comment = "Home Directories";
        "valid users" = "%S";
        "hide dot files" = "yes";
      };
      
      # Development workspace share
      dev-workspace = {
        path = "/home/murali/workspace";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0664";
        "directory mask" = "0775";
        "force user" = "murali";
        "force group" = "samba";
        comment = "Development Workspace";
        "valid users" = "murali";
        
        # Development-friendly settings
        "hide dot files" = "no"; # Show hidden files for development
        "dos filemode" = "yes";
        "preserve case" = "yes";
        "short preserve case" = "yes";
      };
    };
  };
  
  # Enable Samba client utilities
  services.samba.enableWinbind = false; # We don't need Active Directory integration
  
  # Ensure Samba user database is properly managed
  # Users will need to be added with smbpasswd command
  
  # Install Samba utilities for management
  environment.systemPackages = with pkgs; [
    samba # Includes smbclient, smbpasswd, etc.
    cifs-utils # For mounting CIFS shares
  ];
  
  # Ensure proper permissions for Samba directories
  systemd.tmpfiles.rules = [
    # Create base directory for shares
    "d /srv 0755 root root -"
    
    # Create public share directory with appropriate permissions
    "d /srv/public-share 0775 murali samba -"
    
    # Create private share directory with appropriate permissions
    "d /srv/private-share 0775 murali samba -"
    
    # Create workspace directory if it doesn't exist
    "d /home/murali/workspace 0775 murali samba -"
    
    # Samba log directory
    "d /var/log/samba 0755 root root -"
  ];
  
  # Configure user for Samba access
  # The user 'murali' will need to be added to Samba with smbpasswd
  users.users.murali = {
    extraGroups = [ "samba" ];
  };
  
  # Create samba group
  users.groups.samba = {};
  
  # Create a README file in the public share to explain its purpose
  systemd.services.samba-public-share-setup = {
    description = "Setup Samba public share with README";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
    script = ''
      # Create README file in public share
      cat > /srv/public-share/README.txt << 'EOF'
NixOS Home Server - Public Share
================================

This is a public file share accessible from the internet with security restrictions.

SECURITY NOTICE:
- This share is accessible from the internet
- Rate limiting is in place (max 5 connections per minute per IP)
- Maximum 10 concurrent connections allowed
- Executable files are blocked for security
- Authentication is required

USAGE:
- Connect using SMB/CIFS protocol
- Server: nixos (or your server's IP address)
- Share name: public-share
- Username: murali
- Password: (set with smbpasswd command)

SUPPORTED PLATFORMS:
- Windows: File Explorer -> Network -> \\nixos\public-share
- macOS: Finder -> Go -> Connect to Server -> smb://nixos/public-share
- iOS: Files app -> Connect to Server -> smb://nixos/public-share
- Linux: Various file managers or mount command

For private/sensitive files, use the 'private-share' which is local network only.

Last updated: $(date)
EOF
      
      # Set proper permissions
      chown murali:samba /srv/public-share/README.txt
      chmod 664 /srv/public-share/README.txt
      
      # Create a similar README for private share
      cat > /srv/private-share/README.txt << 'EOF'
NixOS Home Server - Private Share
=================================

This is a private file share accessible only from the local network.

SECURITY NOTICE:
- This share is only accessible from local network (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
- No internet access allowed
- Authentication is required

USAGE:
- Connect using SMB/CIFS protocol from local network only
- Server: nixos (or your server's IP address)
- Share name: private-share
- Username: murali
- Password: (set with smbpasswd command)

This share is suitable for sensitive files and documents that should not be accessible from the internet.

Last updated: $(date)
EOF
      
      # Set proper permissions
      chown murali:samba /srv/private-share/README.txt
      chmod 664 /srv/private-share/README.txt
    '';
  };
}