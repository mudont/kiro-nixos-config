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
      lightdm.enable = true;
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
  services.displayManager.defaultSession = "xfce";
  
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
  
  # XRDP configuration for remote desktop access
  services.xrdp = {
    enable = true;
    defaultWindowManager = "xfce4-session";
    
    # Security settings
    confDir = pkgs.writeTextDir "xrdp.ini" ''
      [Globals]
      ini_version=1
      fork=true
      port=3389
      tcp_nodelay=true
      tcp_keepalive=true
      security_layer=negotiate
      crypt_level=high
      certificate=
      key_file=
      ssl_protocols=TLSv1.2, TLSv1.3
      autorun=
      allow_channels=true
      allow_multimon=true
      bitmap_cache=true
      bitmap_compression=true
      bulk_compression=true
      max_bpp=32
      new_cursors=true
      use_fastpath=both
      
      [Logging]
      LogFile=xrdp.log
      LogLevel=INFO
      EnableSyslog=true
      SyslogLevel=INFO
      
      [Channels]
      rdpdr=true
      rdpsnd=true
      drdynvc=true
      cliprdr=true
      rail=true
      xrdpvr=true
      
      [xrdp1]
      name=sesman-Xvnc
      lib=libvnc.so
      username=ask
      password=ask
      ip=127.0.0.1
      port=-1
      code=20
    '';
  };
  
  # Note: sesman is automatically configured with xrdp service
  
  # Additional XRDP configuration files
  environment.etc."xrdp/sesman.ini".text = ''
    [Globals]
    ListenAddress=127.0.0.1
    ListenPort=3350
    EnableUserWindowManager=true
    UserWindowManager=xfce4-session
    DefaultWindowManager=xfce4-session
    ReconnectSh=/etc/xrdp/reconnectwm.sh
    
    [Security]
    AllowRootLogin=false
    MaxLoginRetry=3
    TerminalServerUsers=tsusers
    TerminalServerAdmins=tsadmins
    AlwaysGroupCheck=false
    
    [Sessions]
    X11DisplayOffset=10
    MaxSessions=10
    KillDisconnected=false
    IdleTimeLimit=0
    DisconnectedTimeLimit=0
    Policy=UBP
    
    [Logging]
    LogFile=xrdp-sesman.log
    LogLevel=INFO
    EnableSyslog=1
    SyslogLevel=INFO
    
    [X11rdp]
    param1=-bs
    param2=-nolisten
    param3=tcp
    param4=-uds
    
    [Xvnc]
    param1=-bs
    param2=-nolisten
    param3=tcp
    param4=-localhost
    param5=-dpi
    param6=96
  '';
  
  # Create reconnect script for session management
  environment.etc."xrdp/reconnectwm.sh" = {
    text = ''
      #!/bin/bash
      export PULSE_RUNTIME_PATH="/run/user/$(id -u)/pulse"
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      export XDG_SESSION_TYPE="x11"
      export XDG_CURRENT_DESKTOP="XFCE"
      export DESKTOP_SESSION="xfce"
      
      # Start XFCE session
      exec xfce4-session
    '';
    mode = "0755";
  };
  
  # Create startup script for XFCE in XRDP sessions
  environment.etc."xrdp/startwm.sh" = {
    text = ''
      #!/bin/bash
      
      # Set up environment for XFCE
      export XDG_SESSION_DESKTOP="xfce"
      export XDG_CURRENT_DESKTOP="XFCE"
      export DESKTOP_SESSION="xfce"
      export XDG_SESSION_TYPE="x11"
      
      # Set up audio
      export PULSE_RUNTIME_PATH="/run/user/$(id -u)/pulse"
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      
      # Disable compositing for better remote performance
      export XFWM4_USE_COMPOSITING=0
      
      # Start XFCE session
      if [ -r /etc/default/locale ]; then
        . /etc/default/locale
        export LANG LANGUAGE LC_ALL LC_CTYPE
      fi
      
      # Start the session
      exec xfce4-session
    '';
    mode = "0755";
  };
  
  # Configure session environment for remote desktop
  environment.sessionVariables = {
    # Optimize for remote desktop
    XFCE_PANEL_MIGRATE_DEFAULT = "1";
    # Disable compositing for better performance over network
    XFWM4_USE_COMPOSITING = "0";
  };
}