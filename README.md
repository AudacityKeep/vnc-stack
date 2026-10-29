# vnc-stack

Reach your Windows PC's desktop and a terminal from any browser, through a free Cloudflare quick tunnel.

**Status: early and partly untested.** The Linux side was tested with stand-in services only. The Windows installer (`windows/install.ps1`) has never been run on a clean PC. Read the whole README before using it, and expect to fix things.

## Acceptable use

vnc-stack gives you remote access to a computer through a web browser. You are responsible for using it within the rules that apply to you.

- Only install it on computers you own or have permission to set up this way.
- Many schools, employers and networks ban remote-access tools, tunnels and proxies on their devices or networks, and some ban reaching your own computer from their network. Breaking those rules can lead to suspension, dismissal or worse. Read the acceptable-use policy that applies to you, and if you are unsure, ask the person who runs the network or device first.
- Anyone with your link and logins controls your PC. Keep them private and run `vnc stop` when you are done.
- This software is provided as is, with no warranty (see LICENSE). The author is not responsible for how you use it. This is not legal advice.

## Read this first: what you are opening

This gives anyone who gets your link **and** your logins full control of your PC. Treat it like handing over your keyboard.

- The link is public. Its randomness is not a secret, so your passwords are the only lock.
- Passwords are generated for you during setup. Nothing is shared between machines, and there are no default passwords. Never reuse them anywhere else.
- Run `vnc stop` whenever you are not using it. The tunnel is the only exposure, and stopping it closes the door.
- Lock Windows (Win+L) when you walk away. Someone who gets past the web logins still faces your Windows password.
- Everything listens on loopback only (`127.0.0.1`). Nothing is reachable from your network except through the tunnel.
- Quick tunnels are free and have no uptime guarantee. For anything serious, use a named tunnel with Cloudflare Access, or a private network like Tailscale.
- Don't run this on a PC you can't afford to have compromised, and don't set it up for someone else without telling them what it does.

## What it sets up

| Piece | Where | Role |
|---|---|---|
| TightVNC | Windows | Shares the screen, loopback only |
| noVNC + websockify | WSL | Shows the screen in a browser |
| nginx | WSL | Web login in front of everything, plus a menu page |
| ttyd | WSL | Browser terminal at `/ttyd/` |
| cloudflared | WSL | The tunnel |
| `vnc` command | WSL | Starts and stops it all |

## Requirements

- Windows 11 22H2 or newer (Home is fine), with virtualization enabled in the BIOS
- winget
- An internet connection

### Windows 10

`install.ps1` asks which Windows you have. Windows 10 needs version 2004 (build 19041) or newer.

Windows 10 can't use mirrored networking, so TightVNC listens beyond loopback and a Windows Firewall rule limits it to connections from WSL. **Windows Firewall must stay on.** The installer refuses to run if it's off.

Windows 10 support has ended for most people, so it may not get security updates. Only run this on a PC you can keep patched.

Windows 10 support is experimental. The display driver is off unless you pass `-WithVdd`.

## Install via installer

1. Download attached installer and run
3. If WSL needs installing, the installer stops and asks you to restart. Open Ubuntu once from the Start menu to create your Linux user, then run the script again.
4. The script installs TightVNC, writes `.wslconfig` (mirrored networking/writing settings), sets up a keep-alive, then runs `setup.sh` inside Ubuntu. At the end it prints your logins.
5. Run `wsl --shutdown` once if it asks, so networking changes take effect.

Optional: check the `No Vdd` box to not install the Virtual Display Driver (a fake monitor, useful for headless PCs). It has been unstable on some machines, but is on by default.

## Install via code

1. Clone or download this repo (keep line endings as they are, see `.gitattributes`).
2. Open PowerShell **as administrator** in the repo folder and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\windows\install.ps1
   ```
3. If WSL needs installing, the script stops and asks you to restart. Open Ubuntu once from the Start menu to create your Linux user, then run the script again.
4. The script installs TightVNC, writes `.wslconfig` (mirrored networking), sets up a keep-alive, then runs `setup.sh` inside Ubuntu. At the end it prints your logins.
5. Run `wsl --shutdown` once if it asks, so networking changes take effect.

Optional: add `-NoVdd` to not install the Virtual Display Driver (a fake monitor, useful for headless PCs). It has been unstable on some machines, but is on by default.

Linux side only: inside Ubuntu, `bash setup.sh`.

## Use

In Ubuntu:

```
vnc start     # turn on, prints the link
vnc stop      # turn off
vnc status    # what is running
vnc url       # reprint the link
vnc creds     # show your logins
vnc passwd    # generate a new web password
```

Open the link. You'll get a web login first, then a menu with **Remote Desktop** and **Terminal**. The desktop asks for the VNC password after that.

If the page shows Cloudflare error 1016 right after `vnc start`, wait about 15 seconds and refresh.

## Getting the link while you're away

The link changes every time. To have it sent to you, copy an example from `~/.config/vnc-stack/notify.d.examples/` into `~/.config/vnc-stack/notify.d/`, fill in the values, and `chmod +x` it. Every executable in `notify.d/` runs after `vnc start` with the link as its argument.

- `email.sh.example` sends an email (needs `msmtp` and an app password)
- `gdoc.sh.example` plus `gdoc-apps-script.gs` writes the link into a Google Doc

Your school or work mail may strip trycloudflare.com links.

### Google Doc link (optional)

If you skipped it during setup, run `vnc setup-doc` in Ubuntu. It walks you through creating a Google Doc, pasting a small script into it, deploying it as a web app, and connecting it. After that, `vnc start` writes the new link into your Doc each time, so you can open the Doc on your phone to get the link. Everything runs in your own Google account, and nothing is shared with anyone else.

## Uninstall (manual)

1. `vnc stop`
2. In Ubuntu: `sudo systemctl disable --now nginx ttyd`, `sudo rm /etc/nginx/sites-enabled/vnc /etc/default/ttyd`, `rm -r ~/.config/vnc-stack ~/.cache/vnc-stack ~/.local/bin/vnc`
3. In Windows: uninstall TightVNC (and the Virtual Display Driver if you added it), delete `wsl-keepalive.vbs` from `shell:startup`, and delete the `Restart-VDD` scheduled task if it exists.

## Known problems

- The Virtual Display Driver can crash and freeze the screen for about 20 seconds. If that happens, `schtasks /run /tn Restart-VDD` restarts it.
- Quick tunnels can drop. Run `vnc stop` then `vnc start` for a new link.
- The Windows installer's TightVNC options come from other people's deployment guides and have not been checked on a clean machine. If the VNC password doesn't work, set it by hand in TightVNC Server > Configuration.

## License

MIT. See `LICENSE`.
