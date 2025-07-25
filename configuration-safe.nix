# Safe minimal NixOS configuration for recovery
{ config, pkgs, ... }:

{
  imports = [
    ./hardware.nix
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
  
  # User configuration - minimal
  users.users.murali = {
    isNormalUser = true;
    description = "Murali - Development User";
    extraGroups = [ "wheel" ];
    shell = pkgs.bash;  # Use bash for safety
    home = "/home/murali";
    createHome = true;
    
    # SSH authorized keys for passwordless access from Mac
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDJOZDTATW1BrvtVR2pjgkFWZaawT5qKdNM3Z7o8KHmf59zB8LbRNnUXgRBe+Ir5jA0Wcsknup/u+eLGkPIJi0LqHtr2IPu5UFgJ10M0HQNqHrDZW+uiLWvZymSKHROOCnOOPvTWvV9zcIn16PDX0Zwdmg6tzTxkf4J657vj5+nSKkHm8v5Bfau7rWFzyLTAIDi+jEb+KDkvHrC6z8tYzHY+GoZoG8rHXXoxZQBKjPSNI5O4MI3K+GDBQmRgxQDyOnDAtbGSsFJCms0khEUl387VQTvtjUKRZo0gOnZkCiVKlGycydz8WyrozQ7JDQZkXKd2jELFyUWgOHzjekvyQTJ murali@Mac-Pro-de-Abhi.local"
    ];
    
    # Initial password for emergency access
    hashedPassword = "$6$rounds=4096$saltsalt$3MEaFIjKWrBtwbsw9/93/runLyXgbHjqq8FgGlrmJ.aJn/PgH.zWOQbp9Early60JmvKxZp.roQ6g/6Otx2e.";
  };
  
  # Enable sudo for wheel group without password
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };
  
  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;  # Force key-based auth
      PubkeyAuthentication = true;
    };
  };
  
  # Minimal firewall - only SSH
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };
  
  # Essential packages only
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    tree
    file
    which
    man-pages
  ];
  
  # Enable automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  
  # Optimize nix store
  nix.settings.auto-optimise-store = true;
}