# Development services configuration
{ config, pkgs, ... }:

{
  # Enable Docker service
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Enable Podman as Docker alternative
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # Enable container networking
  virtualisation.containers.enable = true;

  # Enable fail2ban for security
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "10m";
    bantime-increment = {
      enable = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h";
      overalljails = true;
    };
  };

  # Enable zsh system-wide
  programs.zsh.enable = true;

  # Enable Git system-wide
  programs.git.enable = true;

  # Additional system packages for development
  environment.systemPackages = with pkgs; [
    # System-level development tools
    strace             # System call tracer
    lsof               # List open files
    pciutils           # PCI utilities
    usbutils           # USB utilities
    
    # Build essentials
    pkg-config         # Package configuration tool
    autoconf           # Automatic configure script builder
    automake           # Makefile generator
    libtool            # Generic library support script
    
    # System monitoring at system level
    sysstat            # System performance tools (iostat, vmstat, etc.)
    procps             # Process utilities
    psmisc             # Additional process utilities
  ];
}