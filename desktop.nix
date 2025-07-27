# Simple desktop configuration for XFCE on physical screen
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
        greeters.gtk = {
          enable = true;
          theme = {
            name = "Adwaita";
            package = pkgs.gnome-themes-extra;
          };
        };
      };
    };
    
    # Configure keyboard layout
    xkb = {
      layout = "us";
      variant = "";
    };
  };
  
  # Configure display manager session and autologin
  services.displayManager = {
    defaultSession = "xfce";
    autoLogin = {
      enable = true;
      user = "murali";
    };
  };
  
  # Essential desktop applications
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
    
    # Additional packages for stable XFCE session
    xorg.xauth
    xorg.xinit
    xorg.xhost
    xorg.xset
    dbus
    at-spi2-atk
    at-spi2-core
    glib
    
    # Clipboard utilities for VNC
    xclip
    xsel
  ];
  
  # Configure XFCE settings
  services.xserver.desktopManager.xfce.enableXfwm = true;
  
  # Enable sound support with PipeWire
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  
  # Enable essential desktop services
  services.dbus.enable = true;
  services.udisks2.enable = true;
  services.upower.enable = true;
  services.accounts-daemon.enable = true;
  
  # Enable polkit for desktop authentication
  security.polkit.enable = true;
  
  # Configure fonts
  fonts.packages = with pkgs; [
    dejavu_fonts
    liberation_ttf
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
  ];
  
  # Disable XRDP
  services.xrdp.enable = false;
  
  # Configure session environment
  environment.sessionVariables = {
    XFCE_PANEL_MIGRATE_DEFAULT = "1";
  };
  
  # VNC configuration - manual start approach (more reliable)
  # Create a script to start VNC manually
  environment.etc."start-vnc.sh" = {
    text = ''
      #!/bin/bash
      # Kill any existing VNC server
      pkill x11vnc 2>/dev/null || true
      
      # Wait a moment
      sleep 2
      
      # Start VNC server
      DISPLAY=:0 x11vnc -display :0 -forever -shared -nopw -rfbport 5900 -auth /var/run/lightdm/root/:0 -bg -o /var/log/x11vnc.log
      
      echo "VNC server started on port 5900"
    '';
    mode = "0755";
  };
}