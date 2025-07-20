# Home Manager configuration for user environment
{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "murali";
  home.homeDirectory = "/home/murali";

  # This value determines the Home Manager release that your
  # configuration is compatible with.
  home.stateVersion = "24.05";

  # Development environment packages
  home.packages = with pkgs; [
    # TypeScript/Node.js development environment
    nodejs_20          # Latest LTS Node.js
    nodePackages.npm   # Node package manager
    nodePackages.yarn  # Alternative package manager
    nodePackages.typescript # TypeScript compiler
    nodePackages.ts-node    # TypeScript execution
    nodePackages.eslint     # JavaScript/TypeScript linter
    nodePackages.prettier   # Code formatter
    
    # Java development environment
    openjdk21          # OpenJDK 21
    maven              # Maven build tool
    gradle             # Gradle build tool
    
    # C++ development environment
    gcc                # GNU Compiler Collection
    clang              # Clang compiler
    cmake              # CMake build system
    gnumake            # GNU Make
    gdb                # GNU Debugger
    valgrind           # Memory debugging tool
    
    # Rust development environment
    rustc              # Rust compiler
    cargo              # Rust package manager
    rust-analyzer      # Rust language server
    rustfmt            # Rust code formatter
    clippy             # Rust linter
    
    # Python development environment
    python312          # Python 3.12
    python312Packages.pip      # Python package installer
    python312Packages.poetry   # Python dependency management
    python312Packages.virtualenv # Virtual environment tool
    python312Packages.pipenv    # Pipeline virtual environment
    
    # Modern sysadmin CLI tools - File operations
    eza                # Modern ls replacement (exa successor)
    bat                # Modern cat replacement with syntax highlighting
    fd                 # Modern find replacement
    ripgrep            # Modern grep replacement
    
    # System monitoring tools
    htop               # Interactive process viewer
    btop               # Modern htop alternative
    glances            # Cross-platform system monitoring
    iotop              # I/O monitoring
    nethogs            # Network bandwidth monitoring per process
    
    # Network analysis tools
    nmap               # Network discovery and security auditing
    tcpdump            # Network packet analyzer
    httpie             # Modern curl alternative
    
    # Disk management and security tools
    ncdu               # Disk usage analyzer
    duf                # Modern df replacement
    fail2ban           # Intrusion prevention system
    lynis              # Security auditing tool
    
    # Container development environment
    docker             # Docker container runtime
    docker-compose     # Docker Compose for multi-container apps
    podman             # Alternative container runtime
    podman-compose     # Podman Compose
    dive               # Docker image analysis tool
    ctop               # Container monitoring tool
    
    # Additional development utilities
    git                # Version control system
    gh                 # GitHub CLI
    curl               # Data transfer tool
    wget               # File downloader
    jq                 # JSON processor
    yq                 # YAML processor
    tree               # Directory tree viewer
    unzip              # Archive extraction
    zip                # Archive creation
    
    # Text editors and development tools
    neovim             # Modern Vim
    tmux               # Terminal multiplexer
    screen             # Terminal session manager
  ];

  # Git configuration placeholder
  programs.git = {
    enable = true;
    # Configuration will be added in task 9.2
  };

  # Shell configuration with zsh and best practices
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    # User-specific shell aliases
    shellAliases = {
      # Enhanced ls commands with eza
      ls = "eza";
      ll = "eza -l";
      la = "eza -la";
      lt = "eza --tree";
      
      # Enhanced cat with bat
      cat = "bat";
      
      # Enhanced find with fd
      find = "fd";
      
      # Enhanced grep with ripgrep
      grep = "rg";
      
      # Development workflow aliases
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
      
      # System monitoring shortcuts
      top = "btop";
      du = "ncdu";
      df = "duf";
    };
    
    # User-specific shell functions
    initExtra = ''
      # Function to create and enter a directory
      mkcd() {
        mkdir -p "$1" && cd "$1"
      }
      
      # Function to find and kill processes by name
      killp() {
        ps aux | grep "$1" | grep -v grep | awk '{print $2}' | xargs kill -9
      }
      
      # Function to show listening ports
      ports() {
        netstat -tulanp | grep LISTEN
      }
      
      # Function to show disk usage of current directory
      usage() {
        du -sh * | sort -hr
      }
      
      # Function to extract various archive formats
      extract() {
        if [ -f $1 ] ; then
          case $1 in
            *.tar.bz2)   tar xjf $1     ;;
            *.tar.gz)    tar xzf $1     ;;
            *.bz2)       bunzip2 $1     ;;
            *.rar)       unrar e $1     ;;
            *.gz)        gunzip $1      ;;
            *.tar)       tar xf $1      ;;
            *.tbz2)      tar xjf $1     ;;
            *.tgz)       tar xzf $1     ;;
            *.zip)       unzip $1       ;;
            *.Z)         uncompress $1  ;;
            *.7z)        7z x $1        ;;
            *)     echo "'$1' cannot be extracted via extract()" ;;
          esac
        else
          echo "'$1' is not a valid file"
        fi
      }
      
      # Function to show system information
      sysinfo() {
        echo "System Information:"
        echo "=================="
        echo "Hostname: $(hostname)"
        echo "Uptime: $(uptime -p)"
        echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
        echo "Memory: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
        echo "Disk: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}')"
        echo "Network: $(ip route get 8.8.8.8 | awk '{print $7}' | head -1)"
      }
      
      # Set up development environment variables
      export EDITOR="nvim"
      export BROWSER="firefox"
      export TERM="xterm-256color"
      
      # Add local bin to PATH
      export PATH="$HOME/.local/bin:$PATH"
      
      # Node.js development
      export NODE_OPTIONS="--max-old-space-size=4096"
      
      # Rust development
      export RUST_BACKTRACE=1
      
      # Python development
      export PYTHONDONTWRITEBYTECODE=1
      export PYTHONUNBUFFERED=1
      
      # Java development
      export JAVA_HOME="${pkgs.openjdk21}/lib/openjdk"
      
      # Docker development
      export DOCKER_BUILDKIT=1
      export COMPOSE_DOCKER_CLI_BUILD=1
    '';
    
    # Oh My Zsh configuration
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "docker"
        "docker-compose"
        "node"
        "npm"
        "rust"
        "python"
        "systemd"
        "ssh-agent"
        "history-substring-search"
        "colored-man-pages"
        "command-not-found"
        "extract"
        "web-search"
        "z"
      ];
      theme = "agnoster";
    };
    
    # History configuration
    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      ignoreSpace = true;
      extended = true;
    };
  };

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;
}