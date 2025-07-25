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
    # Note: npm is included with nodejs_20, so we don't need to install it separately
    nodePackages.yarn  # Alternative package manager
    nodePackages.typescript # TypeScript compiler
    # nodePackages.ts-node    # TypeScript execution - removing to avoid conflicts
    # nodePackages.eslint     # JavaScript/TypeScript linter - removing to avoid conflicts
    # nodePackages.prettier   # Code formatter - removing to avoid conflicts
    
    # Java development environment
    openjdk21          # OpenJDK 21
    maven              # Maven build tool
    gradle             # Gradle build tool
    
    # C++ development environment
    # Choose only one C compiler to avoid conflicts
    gcc                # GNU Compiler Collection
    # clang              # Clang compiler - removed to avoid conflict with gcc
    cmake              # CMake build system
    gnumake            # GNU Make
    gdb                # GNU Debugger
    
    # Rust development environment
    rustc              # Rust compiler
    cargo              # Rust package manager
    rust-analyzer      # Rust language server
    
    # Python development environment
    python312          # Python 3.12
    python312Packages.pip      # Python package installer
    
    # Modern sysadmin CLI tools - File operations
    eza                # Modern ls replacement (exa successor)
    bat                # Modern cat replacement with syntax highlighting
    fd                 # Modern find replacement
    ripgrep            # Modern grep replacement
    
    # System monitoring tools
    htop               # Interactive process viewer
    
    # Network analysis tools
    curl               # Data transfer tool
    wget               # File downloader
    
    # Container development environment
    docker             # Docker container runtime
    docker-compose     # Docker Compose for multi-container apps
    
    # Additional development utilities
    git                # Version control system
    gh                 # GitHub CLI
    jq                 # JSON processor
    tree               # Directory tree viewer
    unzip              # Archive extraction
    zip                # Archive creation
    
    # Text editors and development tools
    neovim             # Modern Vim
    tmux               # Terminal multiplexer
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
    };
    
    # Oh My Zsh configuration
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "docker"
        "docker-compose"
        "node"
        "npm"
        "systemd"
        "ssh-agent"
        "history-substring-search"
        "colored-man-pages"
        "command-not-found"
        "extract"
      ];
      theme = "robbyrussell";
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