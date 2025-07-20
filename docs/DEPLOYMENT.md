# Deployment Workflow Documentation

This document provides detailed procedures for deploying and maintaining the NixOS home server configuration.

## Deployment Overview

The deployment process uses automated scripts to push configuration changes from a macOS development machine to the NixOS server. The workflow ensures consistent, reliable deployments with automatic rollback capabilities.

## Deployment Architecture

```mermaid
graph LR
    A[Mac Development] --> B[Git Repository]
    B --> C[Deployment Script]
    C --> D[SSH Connection]
    D --> E[NixOS Server]
    E --> F[Configuration Apply]
    F --> G[Service Verification]
    G --> H[Success/Rollback]
```

## Initial Deployment Setup

### Prerequisites

Before running the initial deployment, ensure:

1. **NixOS server is accessible** via SSH
2. **Git repository is cloned** on the Mac
3. **Network connectivity** between Mac and NixOS server
4. **Basic NixOS installation** is complete on target hardware

### Step-by-Step Initial Deployment

#### 1. Prepare the Mac Environment

```bash
# Clone the repository
git clone <repository-url> nixos-home-server
cd nixos-home-server

# Make scripts executable
chmod +x scripts/*.sh

# Verify script permissions
ls -la scripts/
```

#### 2. Configure Network Settings

Edit the network configuration before deployment:

```bash
# Edit networking configuration
nano nixos/networking.nix

# Key settings to configure:
# - hostName: Set your desired hostname
# - Static IP configuration (optional but recommended)
# - DNS servers
# - Default gateway
```

Example configuration:
```nix
{
  networking = {
    hostName = "nixos-dev";
    
    # Static IP configuration
    interfaces.eth0.ipv4.addresses = [{
      address = "192.168.1.100";
      prefixLength = 24;
    }];
    
    defaultGateway = "192.168.1.1";
    nameservers = [ "8.8.8.8" "1.1.1.1" ];
    
    # Enable NetworkManager for easier management
    networkmanager.enable = true;
  };
}
```

#### 3. Configure User Accounts

```bash
# Edit user configuration
nano nixos/users.nix

# Update username and groups as needed
# SSH keys will be added automatically during deployment
```

#### 4. Run Initial Deployment

```bash
# Execute the deployment script
./scripts/deploy-from-mac.sh

# The script will prompt for:
# - NixOS server IP address
# - Username for SSH connection
# - Confirmation of settings
```

#### 5. Verify Deployment

After successful deployment:

```bash
# SSH into the server
ssh username@nixos-server-ip

# Check system status
systemctl status nginx postgresql samba xrdp

# Verify services are listening
sudo netstat -tlnp | grep -E "(80|443|22|3389|139|445)"

# Check system logs
journalctl -f --since "5 minutes ago"
```

## Ongoing Deployment Procedures

### Regular Configuration Updates

#### 1. Making Configuration Changes

```bash
# On your Mac, edit configuration files
nano nixos/services/web.nix
nano nixos/services/development.nix
# ... other configuration files

# Test configuration syntax locally (optional)
nix flake check
```

#### 2. Commit Changes to Git

```bash
# Add changes to git
git add .

# Commit with descriptive message
git commit -m "Update nginx configuration for new virtual host"

# Push to remote repository
git push origin main
```

#### 3. Deploy Changes

```bash
# Run deployment script
./scripts/deploy-from-mac.sh

# The script will:
# 1. Sync latest changes to the server
# 2. Backup current configuration
# 3. Apply new configuration
# 4. Verify services are running
# 5. Rollback if deployment fails
```

#### 4. Verify Deployment

```bash
# Check deployment logs
ssh username@nixos ./check-deployment-status.sh

# Verify specific services if changes were made
ssh username@nixos "systemctl status nginx"
ssh username@nixos "journalctl -u nginx --since '1 minute ago'"
```

### Emergency Rollback Procedures

#### Automatic Rollback

The deployment script includes automatic rollback on failure:

```bash
# If deployment fails, the script will:
# 1. Detect the failure
# 2. Restore previous configuration
# 3. Restart affected services
# 4. Report rollback status
```

#### Manual Rollback

If you need to manually rollback:

```bash
# SSH into the server
ssh username@nixos-server

# List available generations
sudo nixos-rebuild list-generations

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Or rollback to specific generation
sudo nixos-rebuild switch --switch-generation 42

# Verify rollback success
systemctl status --failed
```

### Deployment Script Details

#### deploy-from-mac.sh Workflow

The deployment script performs these steps:

1. **Pre-deployment Checks**
   ```bash
   # Verify SSH connectivity
   ssh -o ConnectTimeout=5 username@server "echo 'Connection OK'"
   
   # Check Git repository status
   git status --porcelain
   
   # Validate flake configuration
   nix flake check
   ```

2. **SSH Key Setup** (first run only)
   ```bash
   # Generate SSH key if not exists
   ssh-keygen -t ed25519 -f ~/.ssh/nixos_server
   
   # Copy public key to server
   ssh-copy-id -i ~/.ssh/nixos_server.pub username@server
   
   # Test passwordless authentication
   ssh -i ~/.ssh/nixos_server username@server "whoami"
   ```

3. **Configuration Sync**
   ```bash
   # Sync configuration files
   rsync -av --delete \
     --exclude='.git' \
     --exclude='docs' \
     ./ username@server:~/nixos-config/
   
   # Sync Git credentials
   ./scripts/sync-git-credentials.sh
   ```

4. **Remote Deployment**
   ```bash
   # Execute remote rebuild
   ssh username@server "cd ~/nixos-config && sudo nixos-rebuild switch --flake ."
   
   # Verify services
   ssh username@server "./scripts/verify-services.sh"
   ```

5. **Post-deployment Verification**
   ```bash
   # Check system health
   ssh username@server "systemctl --failed"
   
   # Verify network services
   ssh username@server "curl -I http://localhost"
   
   # Check logs for errors
   ssh username@server "journalctl --since '1 minute ago' -p err"
   ```

## Advanced Deployment Scenarios

### Deploying to Multiple Servers

For managing multiple NixOS servers:

```bash
# Create server-specific configurations
mkdir -p configs/server1 configs/server2

# Deploy to specific server
NIXOS_SERVER=server1 ./scripts/deploy-from-mac.sh

# Deploy to all servers
./scripts/deploy-all-servers.sh
```

### Staged Deployments

For testing changes before production:

```bash
# Deploy to staging server first
NIXOS_ENV=staging ./scripts/deploy-from-mac.sh

# Run integration tests
./scripts/run-integration-tests.sh staging

# Deploy to production after verification
NIXOS_ENV=production ./scripts/deploy-from-mac.sh
```

### Blue-Green Deployments

For zero-downtime deployments:

```bash
# Deploy to inactive environment
./scripts/deploy-blue-green.sh --target green

# Switch traffic after verification
./scripts/switch-traffic.sh --to green

# Keep blue environment as rollback option
```

## Deployment Monitoring

### Real-time Deployment Monitoring

```bash
# Monitor deployment progress
tail -f /var/log/deployment.log

# Watch system resources during deployment
watch -n 1 'free -h && df -h && systemctl --failed'

# Monitor network connectivity
ping -c 5 nixos-server && curl -I http://nixos-server
```

### Deployment Metrics

Track deployment metrics:

```bash
# Deployment duration
echo "Deployment started: $(date)" >> deployment-metrics.log

# Service restart times
systemctl show nginx --property=ActiveEnterTimestamp

# Configuration validation time
time nix flake check
```

### Automated Deployment Notifications

Set up notifications for deployment events:

```bash
# Slack notification on deployment success
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"NixOS deployment successful"}' \
  $SLACK_WEBHOOK_URL

# Email notification on deployment failure
echo "Deployment failed at $(date)" | mail -s "NixOS Deployment Alert" admin@example.com
```

## Troubleshooting Deployments

### Common Deployment Issues

#### 1. SSH Connection Failures

```bash
# Debug SSH connectivity
ssh -vvv username@server

# Check SSH service on server
systemctl status sshd

# Verify firewall allows SSH
sudo iptables -L | grep ssh
```

#### 2. Configuration Syntax Errors

```bash
# Validate configuration before deployment
nix flake check

# Check specific module syntax
nix-instantiate --eval --strict nixos/services/web.nix

# Test configuration in VM
nixos-rebuild build-vm --flake .
```

#### 3. Service Startup Failures

```bash
# Check failed services
systemctl --failed

# Analyze service logs
journalctl -u service-name --since "10 minutes ago"

# Check service dependencies
systemctl list-dependencies service-name
```

#### 4. Network Configuration Issues

```bash
# Check network interfaces
ip addr show

# Verify routing table
ip route show

# Test DNS resolution
nslookup nixos-server
```

#### 5. Disk Space Issues

```bash
# Check disk usage
df -h

# Clean old generations
sudo nix-collect-garbage -d

# Check Nix store usage
du -sh /nix/store
```

### Deployment Recovery Procedures

#### Configuration Corruption Recovery

```bash
# Boot from NixOS installation media
# Mount the system
mount /dev/sda1 /mnt

# Chroot into the system
nixos-enter --root /mnt

# Rollback to working configuration
nixos-rebuild switch --rollback

# Or restore from backup
cp -r /backup/nixos-config/* /etc/nixos/
nixos-rebuild switch
```

#### Service Recovery

```bash
# Reset failed services
systemctl reset-failed

# Restart all services
systemctl restart nginx postgresql samba xrdp

# Verify service health
./scripts/health-check.sh
```

## Deployment Best Practices

### Pre-deployment Checklist

- [ ] Configuration changes tested locally
- [ ] Git repository is up to date
- [ ] Backup of current configuration exists
- [ ] Network connectivity verified
- [ ] Sufficient disk space available
- [ ] No critical services in maintenance mode

### During Deployment

- [ ] Monitor deployment progress
- [ ] Watch for error messages
- [ ] Verify service startup
- [ ] Check system resources
- [ ] Test critical functionality

### Post-deployment Verification

- [ ] All services running correctly
- [ ] Network connectivity working
- [ ] Remote access functional
- [ ] Backup systems operational
- [ ] Monitoring systems active
- [ ] Documentation updated

### Deployment Security

```bash
# Use SSH keys, not passwords
ssh-keygen -t ed25519 -f ~/.ssh/nixos_deploy

# Limit SSH access to deployment key
echo 'command="nixos-rebuild switch --flake ." ssh-ed25519 AAAA...' >> ~/.ssh/authorized_keys

# Use sudo with limited permissions
echo 'deploy ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/nixos-rebuild' >> /etc/sudoers
```

### Deployment Automation

```bash
# Set up automated deployments with GitHub Actions
# .github/workflows/deploy.yml
name: Deploy to NixOS
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Deploy to server
        run: ./scripts/deploy-from-mac.sh
```

This deployment documentation provides comprehensive procedures for managing the NixOS home server configuration with automated, reliable deployments and proper error handling.