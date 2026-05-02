# AllScan for RLNZ2

Non-interactive AllScan installation and integration for the [RLNZ2](https://github.com/G1LRO/rlnz2) AllStarLink node.

[AllScan](https://github.com/davidgsd/AllScan) is a free, open-source PHP web application providing AllStarLink favourites management, node connection control, and network statistics. This repo provides the scripts and integration files needed to ship AllScan pre-configured and ready to use on the RLNZ2.

---

## Existing RLNZ2 Owners

If you already have a working RLNZ2 and want to add AllScan, log in at the ASL3 Control Center login prompt and run these two commands:

```bash
wget https://raw.githubusercontent.com/G1LRO/install-allscan-standalone/refs/heads/main/install-allscan.sh
sudo bash install-allscan.sh
```

Once complete, you **must re-submit your node details via the RLNZ2 web setup** to apply your login password to AllScan.

> **This step is required** — AllScan is installed with a temporary password that must be replaced with your real login password.

The web setup address is shown on the RLNZ2 display:

```
http://<ip-shown-on-display>:8000/
```

Enter your node number, callsign, node password and login password as normal and submit. AllScan will then be ready at:

```
http://<ip-shown-on-display>/allscan/
```

Use username `rln` and your usual RLNZ2 login password.

---

## Files

| File | Purpose |
|------|---------|
| `install-allscan.sh` | Installs AllScan, Apache, PHP, and seeds the database |
| `configure-asl3.sh` | Configures AllStarLink 3 and updates the AllScan password |
| `asl.py` | RLNZ2 config server route — passes login password to `configure-asl3.sh` |
| `configuration.py` | RLNZ2 config server route — orchestrates all configuration steps |
| `deploy-allscan-update.sh` | Helper script to deploy updates to an existing installation |

---

## How It Works

### Installation

`install-allscan.sh` is run once as part of the RLNZ2 image build or initial setup:

```bash
sudo bash install-allscan.sh
```

It performs the following steps:

1. Installs prerequisites — Apache2, PHP, php-sqlite3, php-curl, sqlite3, avahi-daemon
2. Downloads AllScan from GitHub into `/var/www/html/allscan/`
3. Sets correct file and directory permissions for Apache
4. Creates `/etc/allscan/` and configures PHP SQLite3 extensions
5. Enables the ASL3 node database update service
6. Seeds the AllScan SQLite database with the `rln` admin user (dummy password)
7. Creates a blank `/etc/allscan/favorites.ini` if none exists (existing favourites are preserved)
8. Deploys the RLNZ2 integration files (`asl.py`, `configuration.py`, `configure-asl3.sh`) from this repo

### Password Flow

AllScan is seeded with a temporary dummy password (`rlnz2setup`) at install time. When the user runs the RLNZ2 web setup and sets their login password, `configure-asl3.sh` is called with the `-w` flag and the AllScan password is updated automatically:

```
Web setup (login_password)
    └── configure-asl3.sh -w login_password
            └── update_allscan_password()
                    └── /etc/allscan/allscan.db (rln user hash updated)
```

The same `login_password` is also applied to allmon3 and the Linux `rln` system user — so there is a single password for all web interfaces on the RLNZ2.

The AllStarLink node registration password (`node_password`) is separate and is used only for ASL3 network registration.

### Favourites

AllScan reads favourites from `/etc/allscan/favorites.ini`. This file is created blank on first install and is never overwritten by subsequent runs of `install-allscan.sh`. It can be pre-populated as part of the RLNZ2 image build with RLNZ2-specific nodes and repeaters.

The format follows AllScan's standard `favorites.ini` structure:

```ini
[general]
label[] = "Node Name 12345"
cmd[]   = "rpt cmd %node% ilink 3 12345"
```

---

## Deployment

### Fresh RLNZ2 image build

`install-allscan.sh` is called once during image preparation:

```bash
sudo bash install-allscan.sh
```

No arguments required. The web setup applies the real password on first boot.

### Updating an existing installation

Use the deploy script to push updated integration files to a running unit:

```bash
sudo bash deploy-allscan-update.sh
```

This copies `asl.py`, `configuration.py`, and `configure-asl3.sh` to their correct locations and restarts the config server. Run the web setup afterwards to re-apply the password.

### Manual update of individual files

| File | Destination |
|------|-------------|
| `configure-asl3.sh` | `/home/rln/rlnz2/configure-asl3.sh` |
| `asl.py` | `/home/rln/myenv/lib/python3.11/site-packages/server/routes/asl.py` |
| `configuration.py` | `/home/rln/myenv/lib/python3.11/site-packages/server/routes/configuration.py` |

After updating Python files restart the config server:
```bash
sudo systemctl restart rlnz2-config-server
```

---

## AllScan Access

Once installed and configured, AllScan is available at:

```
http://<node-ip>/allscan/
http://<hostname>.local/allscan/
```

Login with:
- **Username:** `rln`
- **Password:** the login password set in the RLNZ2 web setup

---

## Dependencies

- [AllScan v1.0](https://github.com/davidgsd/AllScan) by David Gleason
- Apache2, PHP 8.x, php-sqlite3, php-curl
- [RLNZ2](https://github.com/G1LRO/rlnz2) with `pi-wifi-config` config server
- AllStarLink 3 (ASL3)

---

## Related Repositories

- [RLNZ2](https://github.com/G1LRO/rlnz2) — Main RLNZ2 node software
- [AllScan](https://github.com/davidgsd/AllScan) — AllScan upstream
