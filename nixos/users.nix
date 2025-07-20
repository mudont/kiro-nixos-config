# User account configuration
{ config, pkgs, ... }:

{
  # Define user accounts
  users.users.murali = {
    isNormalUser = true;
    description = "Murali - Development User";
    extraGroups = [ 
      "wheel"          # Enable sudo
      "networkmanager" # Manage network connections
      "docker"         # Docker access
      "podman"         # Podman access
      "audio"          # Audio access for desktop
      "video"          # Video access for desktop
      "input"          # Input device access
      "storage"        # Storage device access
      "optical"        # Optical drive access
      "scanner"        # Scanner access
      "lp"             # Printer access
      "users"          # General users group
    ];
    shell = pkgs.zsh;
    
    # Home directory
    home = "/home/murali";
    createHome = true;
    
    # SSH authorized keys - these will be populated during deployment
    openssh.authorizedKeys.keys = [
      # Placeholder for Mac SSH public key
      # This will be replaced during the deployment process
      # Format: "ssh-rsa AAAAB3NzaC1yc2E... user@hostname"
    ];
    
    # Initial password (should be changed after first login)
    # This is only for emergency access - SSH keys are preferred
    hashedPassword = "$6$rounds=4096$saltsalt$3MEaFIjKWrBtwbsw9/93/runLyXgbHjqq8FgGlrmJ.aJn/PgH.zWOQbp9Early60JmvKxZp.roQ6g/6Otx2e.";
  };
  
  # Enable sudo for wheel group without password
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
    # Additional sudo rules for development
    extraRules = [
      {
        users = [ "murali" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
  
  # Enable zsh system-wide
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    
    # System-wide zsh configuration
    shellAliases = {
      ll = "ls -l";
      la = "ls -la";
      l = "ls -CF";
      ".." = "cd ..";
      "..." = "cd ../..";
      grep = "grep --color=auto";
      fgrep = "fgrep --color=auto";
      egrep = "egrep --color=auto";
      
      # NixOS specific aliases
      rebuild = "sudo nixos-rebuild switch";
      rebuild-test = "sudo nixos-rebuild test";
      rebuild-boot = "sudo nixos-rebuild boot";
      nix-search = "nix search nixpkgs";
      nix-shell-p = "nix-shell -p";
      
      # Development aliases
      dc = "docker-compose";
      dcu = "docker-compose up";
      dcd = "docker-compose down";
      dcl = "docker-compose logs";
      
      # System monitoring
      ports = "netstat -tulanp";
      listening = "lsof -i";
      processes = "ps aux";
      disk = "df -h";
      memory = "free -h";
    };
    
    # Oh My Zsh configuration
    ohMyZsh = {
      enable = true;
      plugins = [ 
        "git" 
        "docker" 
        "docker-compose" 
        "systemd" 
        "ssh-agent" 
        "gpg-agent"
        "history-substring-search"
        "colored-man-pages"
        "command-not-found"
      ];
      theme = "robbyrussell";
    };
  };
  
  # Enable Git system-wide
  programs.git = {
    enable = true;
    # Global Git configuration will be set up during deployment
    # or through home-manager
  };
  
  # Enable GPG for Git signing
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };
  
  # Set default shell for new users
  users.defaultUserShell = pkgs.zsh;
  
  # Ensure home directories are created with proper permissions
  users.users.murali.homeMode = "755";
}