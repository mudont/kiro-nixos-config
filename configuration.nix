# Comprehensive NixOS Home Server Configuration
{ config, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./networking.nix
    ./users.nix
    ./web.nix
    ./database.nix
    ./samba.nix
    ./desktop.nix
    ./monitoring.nix
    ./backup.nix
    ./development.nix
  ];

  # System configuration
  system.stateVersion = "24.05";
  
  # Enable flakes and new nix command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # Basic system settings
  networking.hostName = "nixos";
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  
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