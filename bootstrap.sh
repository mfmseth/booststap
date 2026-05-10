#!/usr/bin/env bash
# Bootstrap a new workstation for homelab management.
# Requirements: curl, sudo (Linux) or Homebrew (macOS)
# Usage: OP_SERVICE_ACCOUNT_TOKEN=ops_... bash bootstrap.sh
set -euo pipefail

BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-$HOME/booststap}"
BOOTSTRAP_REPO="git@github.com:mfmseth/booststap.git"
HOMELAB2_DIR="${HOMELAB2_DIR:-$HOME/homelab2}"
HOMELAB2_REPO="git@github.com:mfmseth/homelab2.git"
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

# ── Check sudo availability ────────────────────────────────────────────────
if sudo -n true 2>/dev/null; then
  CAN_SUDO=true
else
  CAN_SUDO=false
  echo "==> No sudo access — using user-local installs (~/.local/bin)"
  mkdir -p "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"
fi

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
  elif [[ "$CAN_SUDO" == true ]]; then
    sudo mkdir -p /etc/apt/keyrings
    curl -sS https://downloads.1password.com/linux/keys/1password.asc \
      | gpg --dearmor \
      | sudo tee /etc/apt/keyrings/1password-archive-keyring.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/1password-archive-keyring.gpg] \
https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" \
      | sudo tee /etc/apt/sources.list.d/1password.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y 1password-cli
  else
    # No sudo — download op binary directly to ~/.local/bin
    OP_ARCH="$(uname -m)"; [[ "$OP_ARCH" == "x86_64" ]] && OP_ARCH="amd64" || OP_ARCH="arm64"
    OP_VERSION="$(curl -sSf 'https://app-updates.agilebits.com/check/1/0/CLI2/en/2.0.0/N' \
      | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])' 2>/dev/null \
      || echo "2.30.3")"
    curl -sSfL "https://cache.agilebits.com/dist/1P/op2/pkg/v${OP_VERSION}/op_linux_${OP_ARCH}_v${OP_VERSION}.zip" \
      -o /tmp/op.zip
    python3 -c "import zipfile, shutil; z=zipfile.ZipFile('/tmp/op.zip'); z.extract('op','/tmp/op_extract'); shutil.move('/tmp/op_extract/op','$HOME/.local/bin/op')"
    chmod +x "$HOME/.local/bin/op"
    rm -rf /tmp/op.zip /tmp/op_extract
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
  elif [[ "$CAN_SUDO" == true ]]; then
    sudo apt-get install -y git
  else
    echo "ERROR: git is not installed and sudo is unavailable. Install git manually and re-run."
    exit 1
  fi
fi

# ── Install ansible ────────────────────────────────────────────────────────
if ! command -v ansible &>/dev/null; then
  echo "==> Installing Ansible..."
  if [[ "$PLATFORM" == "mac" ]]; then
    brew install ansible
  else
    if [[ "$CAN_SUDO" == true ]]; then
      sudo apt-get install -y python3-pip
      python3 -m pip install --user ansible
    else
      # No sudo and no pip — bootstrap pip with --break-system-packages (user-local only, safe)
      if ! python3 -m pip --version &>/dev/null; then
        curl -sSf https://bootstrap.pypa.io/get-pip.py \
          | python3 - --user --break-system-packages --quiet
      fi
      python3 -m pip install --user --break-system-packages ansible
    fi
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

# ── Clone booststap repo ───────────────────────────────────────────────────
if [[ ! -d "$BOOTSTRAP_DIR/.git" ]]; then
  echo "==> Cloning booststap..."
  GIT_SSH_COMMAND="ssh -i $SSH_DIR/id_rsa -o StrictHostKeyChecking=no" \
    git clone "$BOOTSTRAP_REPO" "$BOOTSTRAP_DIR"
else
  echo "==> Updating booststap..."
  GIT_SSH_COMMAND="ssh -i $SSH_DIR/id_rsa -o StrictHostKeyChecking=no" \
    git -C "$BOOTSTRAP_DIR" pull --ff-only
fi

# ── Clone homelab2 repo (private) ─────────────────────────────────────────
if [[ ! -d "$HOMELAB2_DIR/.git" ]]; then
  echo "==> Cloning homelab2..."
  GIT_SSH_COMMAND="ssh -i $SSH_DIR/id_rsa -o StrictHostKeyChecking=no" \
    git clone "$HOMELAB2_REPO" "$HOMELAB2_DIR"
else
  echo "==> Updating homelab2..."
  GIT_SSH_COMMAND="ssh -i $SSH_DIR/id_rsa -o StrictHostKeyChecking=no" \
    git -C "$HOMELAB2_DIR" pull --ff-only
fi

# ── Run the bootstrap playbook ─────────────────────────────────────────────
echo "==> Running bootstrap-workstation playbook..."
cd "$BOOTSTRAP_DIR"
ansible-galaxy collection install -r requirements.yml
ansible-playbook playbooks/bootstrap-workstation.yml \
  --connection=local \
  --inventory localhost, \
  --extra-vars "bootstrap_dir=$BOOTSTRAP_DIR ansible_python_interpreter=auto_silent"

# ── Run the private configure playbook ────────────────────────────────────
echo "==> Running configure-workstation playbook..."
ansible-playbook "$HOMELAB2_DIR/playbooks/configure-workstation.yml" \
  --connection=local \
  --inventory localhost, \
  --extra-vars "ansible_python_interpreter=auto_silent"

echo ""
echo "==> Bootstrap complete."
echo "    Reload your shell: source ~/.bash_aliases"
