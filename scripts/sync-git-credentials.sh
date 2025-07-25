#!/bin/bash
set -euo pipefail

NIXOS_HOST="${NIXOS_HOST:-nixos}"
NIXOS_USER="${NIXOS_USER:-murali}"

echo "Syncing Git credentials from Mac to NixOS..."

# Get Git config from Mac
GIT_NAME=$(git config --global user.name 2>/dev/null || echo "")
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
    echo "Please set up Git on your Mac first:"
    echo "  git config --global user.name 'Your Name'"
    echo "  git config --global user.email 'your.email@example.com'"
    exit 1
fi

echo "Found Git config: $GIT_NAME <$GIT_EMAIL>"

# Sync Git configuration
ssh "$NIXOS_USER@$NIXOS_HOST" "
    git config --global user.name '$GIT_NAME'
    git config --global user.email '$GIT_EMAIL'
    git config --global init.defaultBranch main
    git config --global pull.rebase true
    git config --global core.editor vim
"

# Sync SSH keys if they exist
if [ -f ~/.ssh/id_rsa ]; then
    echo "Syncing SSH private key..."
    scp ~/.ssh/id_rsa "$NIXOS_USER@$NIXOS_HOST:/tmp/id_rsa"
    ssh "$NIXOS_USER@$NIXOS_HOST" "
        mkdir -p ~/.ssh
        mv /tmp/id_rsa ~/.ssh/
        chmod 600 ~/.ssh/id_rsa
    "
fi

if [ -f ~/.ssh/id_rsa.pub ]; then
    echo "Syncing SSH public key..."
    scp ~/.ssh/id_rsa.pub "$NIXOS_USER@$NIXOS_HOST:/tmp/id_rsa.pub"
    ssh "$NIXOS_USER@$NIXOS_HOST" "
        mkdir -p ~/.ssh
        mv /tmp/id_rsa.pub ~/.ssh/
        chmod 644 ~/.ssh/id_rsa.pub
    "
fi

# Copy known_hosts if it exists
if [ -f ~/.ssh/known_hosts ]; then
    echo "Syncing SSH known_hosts..."
    scp ~/.ssh/known_hosts "$NIXOS_USER@$NIXOS_HOST:/tmp/known_hosts"
    ssh "$NIXOS_USER@$NIXOS_HOST" "
        mkdir -p ~/.ssh
        mv /tmp/known_hosts ~/.ssh/
        chmod 644 ~/.ssh/known_hosts
    "
fi

# Test Git access
echo "Testing Git access..."
ssh "$NIXOS_USER@$NIXOS_HOST" "
    echo 'Git configuration:'
    git config --global --list
    echo ''
    echo 'Testing GitHub SSH access:'
    ssh -T git@github.com || echo 'SSH key may need to be added to GitHub'
"

echo "Git credentials sync complete!"
