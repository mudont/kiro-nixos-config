# Remote desktop configuration (XFCE + XRDP)
{ config, pkgs, ... }:

{
  # Enable X11 windowing system
  services.xserver = {
    enable = true;
    
    # Use XFCE desktop environment
    desktopManager.xfce.enable = true;
    
    # Configure display manager
    displayManager = {
      lightdm = {
        enable = true;
        autoLogin = {
          enable = true;
          user = "murali";
        };
      };
    };
    
    # Configure keyboard layout
    xkb = {
      layout = "us";
      variant = "";
    };
    
    # Optimize for remote desktop performance
    deviceSection = ''
      Option "AccelMethod" "none"
      Option "DRI" "false"
    '';
  };
  
  # Configure display manager (moved from services.xserver.displayManager)
  services.displayManager = {
    defaultSession = "xfce";
    autoLogin = {
      enable = true;
      user = "murali";
    };
  };
  
  # Essential desktop applications and utilities
  environment.systemPackages = with pkgs; [
    # File managers and utilities
    xfce.thunar
    xfce.thunar-volman
    xfce.thunar-archive-plugin
    
    # Text editors
    xfce.mousepad
    gedit
    
    # Terminal emulator
    xfce.xfce4-terminal
    
    # Web browser
    firefox
    
    # Archive tools
    file-roller
    unzip
    zip
    p7zip
    
    # Image viewer
    xfce.ristretto
    
    # PDF viewer
    evince
    
    # System utilities
    xfce.xfce4-taskmanager
    xfce.xfce4-settings
    
    # Network tools
    networkmanagerapplet
    
    # Audio control
    pavucontrol
    
    # Screenshot tool
    xfce.xfce4-screenshooter
    
    # Clipboard manager
    xfce.xfce4-clipman-plugin
    
    # VNC packages for remote desktop
    x11vnc
    tigervnc
  ];
  
  # Configure XFCE settings for optimal remote desktop performance
  services.xserver.desktopManager.xfce.enableXfwm = true;
  
  # Enable sound support with PipeWire (modern audio system)
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  
  # NetworkManager is already enabled in networking.nix
  
  # Configure fonts for better remote desktop experience
  fonts.packages = with pkgs; [
    dejavu_fonts
    liberation_ttf
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
  ];
  
  # VNC configuration for remote desktop access (more reliable than XRDP)
  # Create a standalone VNC server with virtual display
  systemd.services.vnc-server = {
    description = "TigerVNC Server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "forking";
      User = "murali";
      Group = "users";
      WorkingDirectory = "/home/murali";
      ExecStartPre = [
        "${pkgs.coreutils}/bin/mkdir -p /home/murali/.vnc"
        "${pkgs.bash}/bin/bash -c 'echo murali | ${pkgs.tigervnc}/bin/vncpasswd -f > /home/murali/.vnc/passwd'"
        "${pkgs.coreutils}/bin/chmod 600 /home/murali/.vnc/passwd"
      ];
      ExecStart = "${pkgs.tigervnc}/bin/vncserver :1 -geometry 1920x1080 -depth 24 -localhost no";
      ExecStop = "${pkgs.tigervnc}/bin/vncserver -kill :1";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };
  
  # Create VNC startup script for XFCE
  environment.etc."vnc-xstartup" = {
    text = ''
      #!/bin/sh
      unset SESSION_MANAGER
      unset DBUS_SESSION_BUS_ADDRESS
      exec ${pkgs.xfce.xfce4-session}/bin/xfce4-session
    '';
    mode = "0755";
  };
  
  # Create VNC config directory and startup script for user
  systemd.tmpfiles.rules = [
    "d /home/murali/.vnc 0755 murali users -"
    "L+ /home/murali/.vnc/xstartup - - - - /etc/vnc-xstartup"
  ];
  
  # Disable XRDP since we're using VNC
  services.xrdp.enable = false;
  
  # Configure session environment for remote desktop
  environment.sessionVariables = {
    # Optimize for remote desktop
    XFCE_PANEL_MIGRATE_DEFAULT = "1";
    # Disable compositing for better performance over network
    XFWM4_USE_COMPOSITING = "0";
  };
}