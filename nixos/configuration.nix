# Main NixOS configuration file
{ config, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./networking.nix
    ./users.nix
    ./security.nix
    ./performance.nix
    ./services/web.nix
    ./services/database.nix
    ./services/samba.nix
    ./services/desktop.nix
    ./services/development.nix
    ./services/monitoring.nix
    ./services/backup.nix
  ];

  # System configuration
  system.stateVersion = "24.05";
  
  # Enable flakes and new nix command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # Basic system settings
  networking.hostName = "nixos";
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  
  # Additional locale settings
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };
  
  # Enable unfree packages
  nixpkgs.config.allowUnfree = true;
  
  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Enable automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  
  # Optimize nix store
  nix.settings.auto-optimise-store = true;
}