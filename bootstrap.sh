#!/usr/bin/env bash
# Bootstrap a new workstation for homelab management.
# Requirements: curl, sudo (Linux) or Homebrew (macOS)
# Usage: fill in .env then run bash bootstrap.sh
set -euo pipefail

HOMELAB_DIR="${HOMELAB_DIR:-$HOME/homelab2}"
HOMELAB_REPO="git@github.com:mfmseth/homelab2.git"
SSH_DIR="$HOME/.ssh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Detect platform ────────────────────────────────────────────────────────
if [[ "$OSTYPE" == "darwin"* ]]; then
  PLATFORM="mac"
elif grep -qi microsoft /proc/version 2>/dev/null; then
  PLATFORM="wsl"
else
  PLATFORM="linux"
fi

echo "==> Platform: $PLATFORM"

# ── Load .env if present ───────────────────────────────────────────────────
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  echo "==> Loaded .env"
fi

# ── 1Password service account token ───────────────────────────────────────
if [[ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
  read -rsp "Enter 1Password Service Account Token: " OP_SERVICE_ACCOUNT_TOKEN
  echo
fi
export OP_SERVICE_ACCOUNT_TOKEN

# ── Install op CLI ─────────────────────────────────────────────────────────
if ! command -v op &>/dev/null; then
  echo "==> Installing 1Password CLI..."
  if [[ "$PLATFORM" == "mac" ]]; then
    brew install --cask 1password-cli
  else
    sudo mkdir -p /etc/apt/keyrings
    curl -sS https://downloads.1password.com/linux/keys/1password.asc \
      | gpg --dearmor \
      | sudo tee /etc/apt/keyrings/1password-archive-keyring.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/1password-archive-keyring.gpg] \
https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" \
      | sudo tee /etc/apt/sources.list.d/1password.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y 1password-cli
  fi
fi

echo "==> op $(op --version)"

# ── Verify token works ─────────────────────────────────────────────────────
if ! op vault list &>/dev/null; then
  echo "ERROR: OP_SERVICE_ACCOUNT_TOKEN is invalid or lacks access to the homelab vault."
  exit 1
fi

# ── Install git ────────────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
  echo "==> Installing git..."
  if [[ "$PLATFORM" == "mac" ]]; then
    brew install git
  else
    sudo apt-get install -y git
  fi
fi

# ── Install ansible ────────────────────────────────────────────────────────
if ! command -v ansible &>/dev/null; then
  echo "==> Installing Ansible..."
  if [[ "$PLATFORM" == "mac" ]]; then
    brew install ansible
  else
    sudo apt-get install -y python3-pip
    pip3 install --user ansible
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

echo "==> ansible $(ansible --version | head -1)"

# ── Fetch GitHub SSH key from 1Password ───────────────────────────────────
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

echo "==> Fetching GitHub SSH key from 1Password..."
op read "op://homelab/Homelab GitHub Key/private key" > "$SSH_DIR/id_rsa"
chmod 600 "$SSH_DIR/id_rsa"

# ── Clone homelab2 repo ────────────────────────────────────────────────────
if [[ ! -d "$HOMELAB_DIR/.git" ]]; then
  echo "==> Cloning homelab2..."
  GIT_SSH_COMMAND="ssh -i $SSH_DIR/id_rsa -o StrictHostKeyChecking=no" \
    git clone "$HOMELAB_REPO" "$HOMELAB_DIR"
fi

# ── Run the bootstrap playbook ─────────────────────────────────────────────
echo "==> Running bootstrap-workstation playbook..."
cd "$HOMELAB_DIR"
ansible-galaxy collection install -r requirements.yml -q
ansible-playbook playbooks/bootstrap-workstation.yml \
  --connection=local \
  --inventory localhost, \
  --extra-vars "homelab_dir=$HOMELAB_DIR ansible_python_interpreter=auto_silent"

echo ""
echo "==> Bootstrap complete."
echo "    Run: source $HOMELAB_DIR/.env"
