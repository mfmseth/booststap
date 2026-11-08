# booststap

One-shot bootstrap script for a new WSL, Debian/Ubuntu, or macOS workstation.

All you need is your **1Password Service Account Token** — everything else (SSH keys, SSH config, git config, Ansible, and the homelab repo itself) is pulled from 1Password and set up automatically.

## What it does

1. On Debian/Ubuntu/WSL, installs base packages (`curl`, `gnupg`, `git`, `pipx`, …) — works as root on minimal Debian with no `sudo`
2. Installs the `op` CLI (via apt on Linux/WSL, Homebrew on macOS)
3. Validates your service account token
4. Installs `git` and `ansible` (Ansible via pipx, so it works on Debian 12+ / Ubuntu 23.04+ "externally managed" Python)
5. Fetches your GitHub SSH key from 1Password and writes it to `~/.ssh/id_rsa`
6. Clones [homelab-ansible](https://github.com/mfmseth/homelab-ansible) into `~/homelab-ansible`
7. Runs `playbooks/bootstrap-workstation.yml` from homelab-ansible, which:
   - Writes all homelab SSH key pairs from 1Password
   - Writes `~/.ssh/config` with all host shortcuts
   - Sets global `git` user name and email
   - Creates `.env` with your token pre-filled
   - Installs Ansible collections
   - On Debian/Ubuntu, makes `~/.bashrc` load `~/.bash_aliases` if it doesn't already (e.g. root on minimal Debian)

## Usage

### Recommended — clone, fill in `.env`, run

```bash
git clone https://github.com/mfmseth/booststap.git
cd booststap
cp .env.example .env
# edit .env and paste your token
bash bootstrap.sh
```

### Option B — inline token (non-interactive)

```bash
curl -fsSL https://raw.githubusercontent.com/mfmseth/booststap/main/bootstrap.sh \
  | OP_SERVICE_ACCOUNT_TOKEN=ops_eyJ... bash
```

### Option C — prompted (no .env, no inline token)

```bash
curl -fsSL https://raw.githubusercontent.com/mfmseth/booststap/main/bootstrap.sh | bash
# You will be prompted: Enter 1Password Service Account Token:
```

## After bootstrap

```bash
source ~/homelab-ansible/.env
cd ~/homelab-ansible
ansible-playbook playbooks/<playbook>.yml
```

## Prerequisites

| Requirement | Where to get it |
|-------------|----------------|
| 1Password Service Account Token | 1Password → Settings → Developer → Service Accounts, or backed up under `homelab` → `Service Account Auth Token: ansible` |
| `curl` | Pre-installed on macOS; on Debian/Ubuntu only needed for the `curl \| bash` one-liners (`apt install curl`), the script installs everything else |
| root, `sudo` or Homebrew | Debian/Ubuntu: run as root or a sudo user (password prompt is fine); without either, it falls back to user-local installs. macOS: install [Homebrew](https://brew.sh) first |

## SSH keys managed

| 1Password item | Key file | Used for |
|----------------|----------|----------|
| `Homelab Hosts Key` | `~/.ssh/id_ed25519` | SSH to pve, pi, media, homepage |
| `Home Assistant SSH Key` | `~/.ssh/homelab_ha` | SSH to Home Assistant (10.0.0.7) |
| `Homelab GitHub Key` | `~/.ssh/id_rsa` | GitHub |
