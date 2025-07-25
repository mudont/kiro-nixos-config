# Development environment configuration
{ config, pkgs, ... }:

{
  # Development and system packages
  environment.systemPackages = with pkgs; [
    # Essential tools
    vim
    git
    curl
    wget
    htop
    tree
    file
    which
    man-pages
    
    # Modern CLI tools
    eza          # Better ls
    bat          # Better cat
    fd           # Better find
    ripgrep      # Better grep
    jq           # JSON processor
    yq           # YAML processor
    
    # Development tools - TypeScript/Node.js
    nodejs_20    # Node.js LTS
    nodePackages.typescript
    nodePackages.yarn
    
    # Development tools - Java
    openjdk21
    maven
    gradle
    
    # Development tools - C++
    gcc          # C compiler
    clang        # Alternative C compiler
    cmake        # Build system
    gnumake      # Make
    gdb          # Debugger
    
    # Development tools - Rust
    rustc
    cargo
    rust-analyzer
    
    # Development tools - Python
    python312
    python312Packages.pip
    poetry  # Now a top-level package
    python312Packages.virtualenv
    
    # System monitoring
    btop         # Better htop
    iotop        # I/O monitoring
    nethogs      # Network monitoring
    glances      # System overview
    
    # Network tools
    nmap
    tcpdump
    inetutils  # Provides netstat
    wireshark-cli
    httpie
    
    # Process management
    procps  # Provides pgrep, pkill, ps, top, etc.
    lsof
    strace
    
    # Disk management
    ncdu         # Disk usage analyzer
    duf          # Better df
    smartmontools
    
    # Text processing
    gnused  # GNU sed
    gawk    # GNU awk
    
    # Performance analysis
    linuxPackages.perf
    sysstat  # Provides vmstat, iostat
    
    # Security tools
    lynis
    # rkhunter and chkrootkit may not be available in current nixpkgs
    
    # Backup & sync
    rsync
    rclone
    borgbackup
    restic
    
    # Container tools
    docker
    docker-compose
    podman
    podman-compose
    dive         # Docker image analysis
    ctop         # Container monitoring
    
    # Archive tools
    unzip
    zip
    p7zip
    
    # Text editors
    neovim
    tmux
    
    # Version control
    gh           # GitHub CLI
    
    # Backup management scripts
    (writeScriptBin "backup-now" ''
      #!/bin/bash
      echo "Starting manual backup..."
      systemctl start daily-backup.service
      echo "Backup started. Check status with: systemctl status daily-backup.service"
      echo "View logs with: journalctl -u daily-backup.service -f"
    '')
    
    (writeScriptBin "backup-status" ''
      #!/bin/bash
      echo "=== Backup Service Status ==="
      systemctl status daily-backup.service --no-pager
      
      echo -e "\n=== Last Backup Logs ==="
      if [ -d "/var/log/backup" ]; then
        latest_log=$(ls -t /var/log/backup/backup_*.log 2>/dev/null | head -1)
        if [ -n "$latest_log" ]; then
          echo "Latest log: $latest_log"
          tail -20 "$latest_log"
        else
          echo "No backup logs found"
        fi
      fi
      
      echo -e "\n=== Backup Timer Status ==="
      systemctl status daily-backup.timer --no-pager
      
      echo -e "\n=== Next Backup Schedule ==="
      systemctl list-timers daily-backup.timer --no-pager
    '')
    
    (writeScriptBin "restore-from-backup" ''
      #!/bin/bash
      
      if [ $# -ne 2 ]; then
        echo "Usage: restore-from-backup <backup_type> <target_directory>"
        echo "Available backup types: home, nixos-config, project-config, databases, logs"
        echo "Example: restore-from-backup home /home/murali"
        exit 1
      fi
      
      BACKUP_TYPE=$1
      TARGET_DIR=$2
      BACKUP_HOST="murali@192.168.1.100"
      BACKUP_BASE_DIR="/Users/murali/nixos-backups"
      
      echo "Restoring $BACKUP_TYPE to $TARGET_DIR"
      echo "This will overwrite existing files. Are you sure? (y/N)"
      read -r response
      
      if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Restoring from backup..."
        rsync -avz --delete "$BACKUP_HOST:$BACKUP_BASE_DIR/$BACKUP_TYPE/" "$TARGET_DIR/"
        echo "Restore completed"
      else
        echo "Restore cancelled"
      fi
    '')
  ];
  
  # Enable zsh system-wide
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    
    # System-wide zsh configuration
    shellAliases = {
      ll = "eza -l";
      la = "eza -la";
      l = "eza -CF";
      ls = "eza";
      ".." = "cd ..";
      "..." = "cd ../..";
      grep = "rg";
      cat = "bat";
      find = "fd";
      
      # NixOS specific aliases
      rebuild = "sudo nixos-rebuild switch --flake .";
      rebuild-test = "sudo nixos-rebuild test --flake .";
      rebuild-boot = "sudo nixos-rebuild boot --flake .";
      nix-search = "nix search nixpkgs";
      
      # System monitoring
      ports = "netstat -tulanp";
      listening = "lsof -i";
      processes = "ps aux";
      disk = "df -h";
      memory = "free -h";
      top = "btop";
      
      # Development aliases
      dev = "cd ~/dev";
      proj = "cd ~/projects";
      
      # Git aliases
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git log --oneline";
      gd = "git diff";
      
      # Docker aliases
      d = "docker";
      dc = "docker-compose";
      dps = "docker ps";
      di = "docker images";
    };
    
    # Oh My Zsh configuration
    ohMyZsh = {
      enable = true;
      plugins = [ 
        "git" 
        "docker"
        "docker-compose"
        "node"
        "systemd" 
        "ssh-agent" 
        "history-substring-search"
        "colored-man-pages"
        "command-not-found"
        "extract"
      ];
      theme = "robbyrussell";
    };
  };
  
  # Enable Git system-wide
  programs.git = {
    enable = true;
  };
  
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
    dockerCompat = false;  # Disabled because Docker is enabled
    defaultNetwork.settings.dns_enabled = true;
  };
  
  # Create development directories
  systemd.tmpfiles.rules = [
    "d /home/murali/dev 0755 murali murali -"
    "d /home/murali/projects 0755 murali murali -"
    "d /home/murali/workspace 0755 murali murali -"
  ];
}