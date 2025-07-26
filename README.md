# NixOS Home Server Configuration

A comprehensive NixOS configuration for a development-focused home server that provides both server functionality and a complete development environment. This system is optimized for remote access from macOS devices while maintaining security best practices.

## Features

- **Complete Development Environment**: TypeScript, Java, C++, Rust, Python with modern tooling
- **Remote Desktop Access**: XFCE desktop with VNC for reliable cross-platform access
- **Web Services**: Nginx with HTTP/HTTPS, PostgreSQL database
- **File Sharing**: Samba shares accessible from iOS and macOS devices
- **Container Support**: Docker and Podman for containerized development
- **Monitoring**: Prometheus and Grafana for system monitoring
- **Automated Backups**: Multiple backup strategies including Mac folder sync
- **Security**: Firewall configuration, SSH key authentication, fail2ban protection
- **Deployment Automation**: Scripts for easy deployment from macOS

## Quick Start

### Prerequisites

- NixOS installed on target hardware
- macOS machine for deployment and remote access
- Network connectivity between Mac and NixOS server
- SSH access to the NixOS server

### Current System Status

This configuration provides:
- ✅ **XFCE Desktop**: Running on physical display with autologin
- ✅ **VNC Remote Access**: Port 5900 with clipboard support (VNC Viewer)
- ✅ **Web Server**: Nginx running on ports 80/443
- ✅ **Database**: PostgreSQL for development
- ✅ **File Sharing**: Samba shares for macOS/iOS access
- ✅ **Development Environment**: Node.js, Python, Java, Rust, Docker
- ✅ **Security**: Firewall, SSH keys, fail2ban protection

### Deployment

1. **Clone the repository on your Mac:**
   ```bash
   git clone <repository-url> nixos-home-server
   cd nixos-home-server
   ```

2. **Deploy the configuration:**
   ```bash
   # Make deployment script executable
   chmod +x scripts/deploy-from-mac.sh
   
   # Deploy with automatic approval of uncommitted changes
   ./scripts/deploy-from-mac.sh deploy-and-rebuild --allow-uncommitted
   ```

3. **The deployment script will:**
   - Validate the NixOS configuration
   - Transfer files to the NixOS server
   - Rebuild the system with new configuration
   - Run health checks to verify services
   - Provide rollback if deployment fails

## Detailed Setup Guide

### Step 1: Hardware Preparation

1. **Install NixOS** on your target hardware using the standard installation process
2. **Set a temporary password** for the initial user account
3. **Configure basic networking** to ensure internet connectivity
4. **Note the IP address** of your NixOS machine

### Step 2: Network Configuration

Edit `nixos/networking.nix` to configure your network settings:

```nix
{
  networking = {
    hostName = "nixos";  # Change this to your preferred hostname
    
    # Configure static IP (optional but recommended)
    interfaces.eth0.ipv4.addresses = [{
      address = "192.168.1.100";  # Change to your desired IP
      prefixLength = 24;
    }];
    
    defaultGateway = "192.168.1.1";  # Your router's IP
    nameservers = [ "8.8.8.8" "1.1.1.1" ];
  };
}
```

### Step 3: User Account Configuration

Edit `nixos/users.nix` to configure your user account:

```nix
{
  users.users.murali = {  # Change 'murali' to your username
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "networkmanager" ];
    shell = pkgs.zsh;
    # SSH keys will be added automatically by the deployment script
  };
}
```

### Step 4: Service Configuration

The configuration includes several service modules that can be customized:

#### Web Services (`nixos/services/web.nix`)
- **Nginx**: Reverse proxy and static file serving
- **SSL**: Automatic certificate management with Let's Encrypt
- **PostgreSQL**: Database service for development

#### File Sharing (`nixos/services/samba.nix`)
- **Public Share**: `/srv/public-share` accessible from internet
- **Private Shares**: Local network only
- **iOS Compatibility**: SMB3 protocol support

#### Remote Desktop (`desktop.nix`)
- **XFCE**: Lightweight desktop environment with autologin
- **VNC**: x11vnc server for reliable remote desktop access
- **Screen Lock**: Disabled for seamless remote access

#### Development Environment (`nixos/services/development.nix`)
- **Languages**: Node.js, Java, C++, Rust, Python
- **Containers**: Docker and Podman
- **Modern CLI Tools**: exa, bat, fd, ripgrep, htop, and more

### Step 5: Deployment

1. **Make the deployment script executable:**
   ```bash
   chmod +x scripts/deploy-from-mac.sh
   ```

2. **Run the deployment:**
   ```bash
   ./scripts/deploy-from-mac.sh
   ```

   The script will:
   - Prompt for the NixOS server IP address
   - Set up passwordless SSH authentication
   - Copy Git credentials and SSH keys
   - Transfer the configuration
   - Rebuild the NixOS system
   - Verify all services are running

3. **Verify the deployment:**
   ```bash
   # SSH into your server
   ssh murali@nixos  # or use the IP address
   
   # Check system status
   systemctl status nginx postgresql samba-smbd display-manager
   
   # Check VNC server
   ps aux | grep x11vnc
   ```

## Configuration Options

### Firewall Settings

The firewall is configured in `nixos/networking.nix` with the following ports:

- **SSH (22)**: Local network only
- **HTTP (80)**: All interfaces 
- **HTTPS (443)**: All interfaces (when SSL configured)
- **Samba (139/445)**: All interfaces for file sharing
- **VNC (5900)**: Local network only for remote desktop

### Development Tools

Customize the development environment in `nixos/services/development.nix`:

```nix
environment.systemPackages = with pkgs; [
  # Add or remove development tools as needed
  nodejs_20 typescript
  openjdk21 maven gradle
  gcc clang cmake
  rustc cargo
  python312 poetry
  
  # Modern CLI tools
  exa bat fd ripgrep
  htop btop glances
  docker podman
];
```

### Monitoring Configuration

Monitoring services are configured in `monitoring.nix`:

- **Prometheus**: Metrics collection on port 9090 (local network only)
- **Grafana**: Visualization dashboards on port 3000 (local network only)
- **Node Exporter**: System metrics on port 9100 (local network only)

Access Grafana at `http://nixos:3000` from local network (admin/admin default login).

### Backup Configuration

Backup services are configured in `nixos/services/backup.nix`:

- **Rsync to Mac**: Primary backup method
- **iCloud via rclone**: Alternative backup (requires setup)
- **Git configuration backup**: Automatic commits

## Current Service Status

### Working Services ✅

| Service | Status | Port | Access |
|---------|--------|------|--------|
| **SSH** | ✅ Active | 22 | Local network |
| **VNC** | ✅ Active | 5900 | Local network |
| **HTTP** | ✅ Active | 80 | All interfaces |
| **Samba** | ✅ Active | 139/445 | All interfaces |
| **PostgreSQL** | ✅ Active | 5432 | Localhost only |
| **Docker** | ✅ Active | - | Local access |
| **XFCE Desktop** | ✅ Active | Physical display | Autologin enabled |

### Service Health Check

```bash
# Quick health check
ssh nixos "systemctl is-active sshd nginx postgresql samba-smbd docker"

# Detailed status
ssh nixos "systemctl status display-manager"

# Check VNC server
ssh nixos "ps aux | grep x11vnc"
```

## Usage Guide

### Remote Desktop Access

#### VNC Access (Recommended)

1. **Using VNC Viewer (Best Experience)**:
   - Install: `brew install --cask vnc-viewer`
   - Connection: `nixos:5900`
   - Password: `murali` (or your username)
   - Features: Full clipboard support, better performance

2. **Using macOS Built-in Screen Sharing**:
   - Finder → `Cmd+K` → `vnc://nixos:5900`
   - Password: `murali` (or your username)
   - Note: No clipboard support, but works as fallback

3. **Session Details**:
   - Shares the physical XFCE desktop session
   - Screen lock is disabled for seamless access
   - Autologin configured for immediate desktop availability

### File Sharing Access

1. **From macOS Finder**:
   - Go → Connect to Server
   - `smb://nixos.local` or `smb://server-ip`

2. **From iOS Files app**:
   - Browse → Connect to Server
   - `smb://nixos.local` or server IP

### Development Workflow

1. **SSH into the server**:
   ```bash
   ssh murali@nixos
   ```

2. **Start development**:
   ```bash
   # Clone your projects
   git clone your-repo
   
   # Use modern CLI tools
   exa -la        # Better ls
   bat file.txt   # Better cat
   fd pattern     # Better find
   rg "search"    # Better grep
   ```

3. **Container development**:
   ```bash
   # Docker
   docker run -it ubuntu
   
   # Podman (rootless)
   podman run -it ubuntu
   ```

### Web Development

1. **Database access**:
   ```bash
   sudo -u postgres psql
   ```

2. **Web root**: `/var/www/html`

3. **SSL certificates**: Managed automatically via Let's Encrypt

## Maintenance

### System Updates

```bash
# Update the flake inputs
nix flake update

# Rebuild the system
sudo nixos-rebuild switch --flake .
```

### Backup Verification

```bash
# Check backup status
systemctl status backup-to-mac.timer
journalctl -u backup-to-mac.service

# Manual backup
sudo systemctl start backup-to-mac.service
```

### Service Management

```bash
# Check service status
systemctl status nginx postgresql samba-smbd display-manager

# Check VNC server
ps aux | grep x11vnc

# Restart a service
sudo systemctl restart nginx

# View logs
journalctl -u nginx -f
```

### Monitoring

- **System metrics**: Access Grafana at `https://server-ip:3000`
- **Logs**: Use `journalctl` for centralized logging
- **Resource usage**: Use `htop`, `btop`, or `glances`

## Troubleshooting

### Common Issues

#### 1. Cannot SSH to server

**Symptoms**: Connection refused or timeout when trying to SSH

**Solutions**:
```bash
# Check if SSH service is running on the server
systemctl status sshd

# Verify firewall allows SSH
sudo iptables -L | grep ssh

# Check network connectivity
ping nixos.local
```

#### 2. VNC remote desktop connection fails

**Symptoms**: Cannot connect via VNC from macOS

**Solutions**:
```bash
# Check if x11vnc is running
ps aux | grep x11vnc

# Verify VNC port is open
sudo netstat -tlnp | grep 5900

# Check firewall rules
sudo iptables -L | grep 5900

# Check if XFCE desktop is running
ps aux | grep xfce

# Manually start VNC if needed
sudo DISPLAY=:0 x11vnc -display :0 -forever -shared -nopw -rfbport 5900 -auth /var/run/lightdm/root/:0 -bg
```

#### 3. File sharing not accessible

**Symptoms**: Cannot see or connect to Samba shares

**Solutions**:
```bash
# Check Samba service
systemctl status smbd nmbd

# Test Samba configuration
sudo testparm

# Check share permissions
ls -la /srv/public-share

# Restart Samba services
sudo systemctl restart smbd nmbd
```

#### 4. Web services not working

**Symptoms**: Cannot access web pages or SSL certificate issues

**Solutions**:
```bash
# Check Nginx status
systemctl status nginx

# Test Nginx configuration
sudo nginx -t

# Check SSL certificates
sudo certbot certificates

# Renew certificates manually
sudo certbot renew

# Check PostgreSQL
systemctl status postgresql
sudo -u postgres psql -c "SELECT version();"
```

#### 5. Development tools missing

**Symptoms**: Command not found for development tools

**Solutions**:
```bash
# Rebuild the system to ensure all packages are installed
sudo nixos-rebuild switch --flake .

# Check if packages are in the system profile
nix-env -q

# Verify shell environment
echo $PATH
which node java rustc python3
```

#### 6. Backup failures

**Symptoms**: Backup services failing or not running

**Solutions**:
```bash
# Check backup service logs
journalctl -u backup-to-mac.service

# Verify SSH connectivity to Mac
ssh mac-username@mac-ip

# Check backup directory permissions
ls -la /backup/

# Test manual backup
rsync -av /home/ mac-username@mac-ip:/backup/nixos/
```

#### 7. Monitoring services down

**Symptoms**: Cannot access Grafana or Prometheus

**Solutions**:
```bash
# Check Prometheus
systemctl status prometheus
curl http://localhost:9090

# Check Grafana
systemctl status grafana
curl http://localhost:3000

# Check Node Exporter
systemctl status prometheus-node-exporter
curl http://localhost:9100/metrics
```

### Network Troubleshooting

```bash
# Check network interfaces
ip addr show

# Check routing
ip route show

# Check DNS resolution
nslookup nixos.local
dig nixos.local

# Check firewall status
sudo iptables -L -n

# Check listening ports
sudo netstat -tlnp
```

### Log Analysis

```bash
# System logs
journalctl -f

# Service-specific logs
journalctl -u nginx -f
journalctl -u postgresql -f
journalctl -u sshd -f

# Boot logs
journalctl -b

# Error logs only
journalctl -p err
```

### Performance Issues

```bash
# Check system resources
htop
btop
glances

# Check disk usage
df -h
ncdu /

# Check memory usage
free -h

# Check network usage
nethogs
iotop
```

## Security Considerations

### SSH Security
- Password authentication is disabled
- Root login is disabled
- fail2ban protects against brute force attacks
- SSH keys are required for access

### Firewall Configuration
- Only necessary ports are open
- Local network restrictions for sensitive services
- Regular security updates via NixOS

### SSL/TLS
- Automatic certificate management
- Strong cipher suites
- HSTS headers enabled

### File Sharing Security
- User-based authentication required
- Rate limiting for internet access
- Separate shares for public and private data

## Advanced Configuration

### Custom Services

To add custom services, create a new module in `nixos/services/`:

```nix
# nixos/services/custom.nix
{ config, pkgs, ... }:

{
  systemd.services.my-service = {
    description = "My Custom Service";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      ExecStart = "${pkgs.my-package}/bin/my-service";
      Restart = "always";
      User = "my-user";
    };
  };
}
```

Then import it in `nixos/configuration.nix`:

```nix
imports = [
  ./services/custom.nix
];
```

### Environment Customization

Customize the shell environment in `home-manager/home.nix`:

```nix
{
  programs.zsh = {
    enable = true;
    shellAliases = {
      ll = "exa -la";
      cat = "bat";
      find = "fd";
      grep = "rg";
    };
    
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "docker" "kubectl" ];
      theme = "robbyrussell";
    };
  };
}
```

## Support and Contributing

### Getting Help

1. Check the troubleshooting section above
2. Review NixOS documentation: https://nixos.org/manual/
3. Check system logs with `journalctl`
4. Verify configuration with `nixos-rebuild dry-run`

### Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description

### Reporting Issues

When reporting issues, please include:
- NixOS version: `nixos-version`
- System information: `uname -a`
- Relevant logs: `journalctl -u service-name`
- Configuration changes made
- Steps to reproduce the issue

## License

This configuration is provided as-is for educational and personal use. Modify as needed for your specific requirements.