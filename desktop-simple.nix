# Simple desktop configuration for XFCE on physical screen
{ config, pkgs, ... }:

{
  # Enable X11 windowing system
  services.xserver = {
    enable = true;
    
    # Use XFCE desktop environment
    desktopManager.xfce.enable = true;
    
    # Configure display manager with autologin
    displayManager = {
      lightdm.enable = true;
    };
    
    # Configure keyboard layout
    xkb = {
      layout = "us";
      variant = "";
    };
  };
  
  # Configure display manager autologin
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
}