# Minimal NixOS configuration for initial deployment
{ config, pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ./users.nix
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
  
  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };
  
  # Open firewall for SSH
  networking.firewall.allowedTCPPorts = [ 22 ];
  
  # Enable automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  
  # Optimize nix store
  nix.settings.auto-optimise-store = true;
}