#!/usr/bin/env bash
# vnc-stack: Linux (WSL) side uninstaller. Undoes what setup.sh did.
# Run as your normal user, inside Ubuntu on WSL:   bash uninstall.sh
# (windows/uninstall.ps1 runs this for you.)
set -uo pipefail

CONF="$HOME/.config/vnc-stack"

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not root and not with sudo."
grep -qi microsoft /proc/version || die "This must be run inside WSL."
sudo -v || die "sudo access is required."

say "Stopping remote access"
if [ -x "$HOME/.local/bin/vnc" ]; then
    "$HOME/.local/bin/vnc" stop || true
fi

say "Removing the browser terminal (ttyd) setup"
sudo systemctl disable --now ttyd 2>/dev/null || true
sudo rm -f /etc/systemd/system/ttyd.service.d/override.conf /etc/default/ttyd
sudo rmdir /etc/systemd/system/ttyd.service.d 2>/dev/null || true
sudo systemctl daemon-reload

say "Removing the nginx setup"
sudo rm -f /etc/nginx/sites-enabled/vnc /etc/nginx/sites-available/vnc /etc/nginx/.htpasswd
sudo rm -rf /var/www/landing
# setup.sh removed nginx's default site, so put its link back if the file is still there.
if [ -f /etc/nginx/sites-available/default ] && [ ! -e /etc/nginx/sites-enabled/default ]; then
    sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
fi
if command -v nginx >/dev/null 2>&1 && sudo nginx -t >/dev/null 2>&1; then
    sudo systemctl reload nginx 2>/dev/null || true
fi

say "Removing the vnc command and its settings"
rm -f "$HOME/.local/bin/vnc"
# ~/.msmtprc is only removed if vnc-stack set up email (it created notify.d/email.sh).
if [ -f "$CONF/notify.d/email.sh" ]; then
    rm -f "$HOME/.msmtprc"
fi
rm -rf "$CONF"

say "Optional: remove the packages setup.sh installed"
PKGS="nginx apache2-utils python3-websockify novnc ttyd msmtp cloudflared"
echo "setup.sh installed: $PKGS"
echo "Other things on this machine may use them, so they are kept unless you say yes."
yn=""
if [ -t 0 ]; then
    read -rp "Remove these packages too? (y/N) " yn || yn=""
fi
case "$yn" in
    [Yy]*)
        # shellcheck disable=SC2086
        sudo apt-get remove -y $PKGS
        sudo rm -f /etc/apt/sources.list.d/cloudflared.list /usr/share/keyrings/cloudflare-main.gpg
        ;;
esac

say "Done"
echo "Left in place on purpose: curl, ca-certificates, gnupg and openssl."
