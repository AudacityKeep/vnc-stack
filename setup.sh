#!/usr/bin/env bash
# vnc-stack: Linux (WSL) side installer.
# Run as your normal user, inside Ubuntu on WSL:   bash setup.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HOME/.config/vnc-stack"

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not root and not with sudo."
grep -qi microsoft /proc/version || die "This must be run inside WSL."
[ -r /etc/os-release ] && . /etc/os-release
[ "${ID:-}" = ubuntu ] || die "Ubuntu is required (found: ${ID:-unknown})."
[ -d /run/systemd/system ] || die "systemd is not running in this WSL distro. Add 'systemd=true' under [boot] in /etc/wsl.conf, run 'wsl --shutdown' in Windows, then retry."
sudo -v || die "sudo access is required."

say "Installing packages"
sudo apt-get update
sudo apt-get install -y nginx apache2-utils python3-websockify novnc ttyd curl ca-certificates gnupg openssl
[ -f /usr/share/novnc/vnc.html ] || die "noVNC's vnc.html was not found in /usr/share/novnc."

if ! command -v cloudflared >/dev/null 2>&1; then
    say "Installing cloudflared (Cloudflare's apt repository)"
    sudo install -d -m 755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
        | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y cloudflared
fi

say "Creating logins"
umask 077
mkdir -p "$CONF/notify.d" "$CONF/notify.d.examples"
if [ ! -f "$CONF/credentials" ]; then
    printf 'WEB_USER=%s\nWEB_PASS=%s\n' "$USER" "$(openssl rand -hex 16)" > "$CONF/credentials"
fi
# shellcheck disable=SC1091
. "$CONF/credentials"
umask 022

say "Configuring nginx"
printf '%s\n' "$WEB_PASS" | sudo htpasswd -ic /etc/nginx/.htpasswd "$WEB_USER" >/dev/null
sudo chown root:www-data /etc/nginx/.htpasswd
sudo chmod 640 /etc/nginx/.htpasswd
sudo mkdir -p /var/www/landing
sed "s/{{HOSTNAME}}/$(hostname)/g" "$REPO_DIR/templates/landing.html" | sudo tee /var/www/landing/index.html >/dev/null
sudo install -m 644 "$REPO_DIR/templates/nginx-vnc.conf" /etc/nginx/sites-available/vnc
sudo ln -sf /etc/nginx/sites-available/vnc /etc/nginx/sites-enabled/vnc
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx

say "Configuring ttyd (browser terminal)"
sudo systemctl stop ttyd 2>/dev/null || true
sudo install -d -m 755 /etc/systemd/system/ttyd.service.d
sudo tee /etc/systemd/system/ttyd.service.d/override.conf >/dev/null <<UNIT
[Service]
Restart=on-failure
RestartSec=3
User=$USER
Group=$(id -gn)
WorkingDirectory=$HOME
UNIT
printf 'TTYD_OPTIONS="-i 127.0.0.1 -b /ttyd -p 7681 -c %s:%s -W bash -l"\n' "$WEB_USER" "$WEB_PASS" \
    | sudo tee /etc/default/ttyd >/dev/null
sudo chmod 600 /etc/default/ttyd
sudo systemctl daemon-reload
sudo systemctl enable ttyd
sudo systemctl restart ttyd

say "Installing the vnc command"
mkdir -p "$HOME/.local/bin"
install -m 755 "$REPO_DIR/bin/vnc" "$HOME/.local/bin/vnc"
cp -f "$REPO_DIR"/notify.d.examples/* "$CONF/notify.d.examples/"

say "Checking"
sleep 2
code() { curl -s -o /dev/null -m 5 -w '%{http_code}' "$@" || true; }
ok=1
chk() {
    if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1 (got $2, expected $3)"; ok=0; fi
}
chk "web login is required"  "$(code http://127.0.0.1:8080/)" 401
chk "landing page loads"     "$(code -u "$WEB_USER:$WEB_PASS" http://127.0.0.1:8080/)" 200
chk "terminal (ttyd) loads"  "$(code -u "$WEB_USER:$WEB_PASS" http://127.0.0.1:8080/ttyd/)" 200
if (exec 3<>/dev/tcp/127.0.0.1/5900) 2>/dev/null; then
    echo "  ok    TightVNC is reachable on 127.0.0.1:5900"
else
    echo "  note  TightVNC is not reachable on 127.0.0.1:5900 yet."
    echo "        Install the Windows side, then run 'wsl --shutdown' in Windows once."
fi

echo
if [ "$ok" = 1 ]; then
    echo "Linux side is ready. Open a NEW terminal (so 'vnc' is on your PATH), then:"
    echo "    vnc start     # turns remote access on and prints the link"
    echo "    vnc creds     # shows your logins"
else
    echo "Some checks failed. Re-run this script after fixing the errors above."
    exit 1
fi
