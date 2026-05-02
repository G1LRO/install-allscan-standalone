#!/bin/bash
# =============================================================================
# install-allscan.sh
# Non-interactive AllScan installer for RLNZ2
#
# Usage:
#   sudo bash install-allscan.sh
#
# No arguments required. The admin user (rln) is created with a dummy password
# that is replaced by the real login password when the user runs the RLNZ2
# web setup (configure-asl3.sh -w <login_password>).
# =============================================================================

set -e

# Fixed values — username is always rln, dummy password is replaced by web setup
ALLSCAN_USER="rln"
ALLSCAN_PASS="rlnz2setup"   # Dummy — overwritten by configure-asl3.sh -w on first web setup

# Must be run as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (sudo)."
    exit 1
fi

echo "=============================================="
echo "  AllScan Non-Interactive Installer (RLNZ2)"
echo "=============================================="
echo "  Admin user : $ALLSCAN_USER"
echo "  Web root   : /var/www/html"
echo "  AllScan dir: /var/www/html/allscan"
echo "  DB dir     : /etc/allscan"
echo "  Note       : Dummy password set — web setup will update it"
echo "=============================================="

# -----------------------------------------------------------------------------
# Step 1: Install prerequisites
# -----------------------------------------------------------------------------
echo ""
echo "[1/8] Installing prerequisites..."
apt-get update -qq
apt-get install -y -qq \
    php \
    php-sqlite3 \
    php-curl \
    unzip \
    sqlite3 \
    avahi-daemon \
    apache2 2>/dev/null || true

# Install ASL3-specific packages if available (non-fatal if absent)
apt-get install -y -qq asl3-tts        2>/dev/null || true
apt-get install -y -qq asl3-update-nodelist 2>/dev/null || true

echo "  Prerequisites installed."

# -----------------------------------------------------------------------------
# Step 2: Confirm web server and group
# -----------------------------------------------------------------------------
echo ""
echo "[2/8] Checking web server..."

WEBDIR="/var/www/html"
WEBGROUP="www-data"

if [[ ! -d "$WEBDIR" ]]; then
    echo "ERROR: Web root $WEBDIR not found. Is Apache installed?"
    exit 1
fi
echo "  Web root   : $WEBDIR"
echo "  Web group  : $WEBGROUP"

ASDIR="$WEBDIR/allscan"

# -----------------------------------------------------------------------------
# Step 3: Download and install AllScan from GitHub
# -----------------------------------------------------------------------------
echo ""
echo "[3/8] Downloading AllScan from GitHub..."

cd "$WEBDIR"

ZIPFILE="main.zip"
ZIPURL="https://github.com/davidgsd/AllScan/archive/refs/heads/main.zip"
UNZIPDIR="AllScan-main"

# Remove any previous download artifacts
rm -f "$ZIPFILE"
rm -rf "$UNZIPDIR"

# Backup existing install if present
if [[ -d "$ASDIR" ]]; then
    VER=$(grep -oP '(?<=\$AllScanVersion = "v)[0-9.]+' "$ASDIR/include/common.php" 2>/dev/null || echo "unknown")
    BAK="${ASDIR}.bak.${VER}"
    echo "  Existing AllScan v$VER found, backing up to ${BAK}..."
    rm -rf "$BAK"
    mv "$ASDIR" "$BAK"
    echo "  Backup complete."
fi

echo "  Downloading $ZIPURL ..."
wget -q "$ZIPURL" -O "$ZIPFILE"
if [[ ! -f "$ZIPFILE" ]]; then
    echo "ERROR: Download failed. Check network connectivity."
    exit 1
fi

echo "  Extracting..."
unzip -q "$ZIPFILE"
rm -f "$ZIPFILE"

if [[ ! -d "$UNZIPDIR" ]]; then
    echo "ERROR: Unzip failed — $UNZIPDIR not found."
    exit 1
fi

mv "$UNZIPDIR" "$ASDIR"
echo "  AllScan installed to $ASDIR"

# Restore .ini files from backup if available
if [[ -n "${BAK:-}" && -d "$BAK" ]]; then
    echo "  Restoring .ini files from backup..."
    cp -n "$BAK"/*.ini "$ASDIR/" 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# Step 4: Set directory and file permissions
# -----------------------------------------------------------------------------
echo ""
echo "[4/8] Setting permissions..."

chmod 775 "$ASDIR"
chgrp "$WEBGROUP" "$ASDIR"

# Set group-writable on .ini files if any exist
find "$ASDIR" -maxdepth 1 -name "*.ini" | while read -r f; do
    chmod 664 "$f"
    chgrp "$WEBGROUP" "$f"
done

echo "  Permissions set."

# -----------------------------------------------------------------------------
# Step 5: Set up /etc/allscan directory
# -----------------------------------------------------------------------------
echo ""
echo "[5/8] Setting up /etc/allscan directory..."

ASDBDIR="/etc/allscan"
mkdir -p "$ASDBDIR"
chmod 775 "$ASDBDIR"
chgrp "$WEBGROUP" "$ASDBDIR"
echo "  $ASDBDIR ready."

# -----------------------------------------------------------------------------
# Step 6: Check and fix php.ini for SQLite3 extensions
# -----------------------------------------------------------------------------
echo ""
echo "[6/8] Checking PHP SQLite3 configuration..."

PHP_INI=$(find /etc/php -name "php.ini" 2>/dev/null | grep apache2 | head -1)

if [[ -z "$PHP_INI" ]]; then
    echo "  WARNING: Apache php.ini not found — SQLite3 may need manual enabling."
else
    echo "  Found php.ini: $PHP_INI"
    # Check if extensions are already enabled
    PDO_OK=$(grep -c '^extension=pdo_sqlite' "$PHP_INI" || true)
    SQ3_OK=$(grep -c '^extension=sqlite3'    "$PHP_INI" || true)

    if [[ "$PDO_OK" -eq 0 || "$SQ3_OK" -eq 0 ]]; then
        cp "$PHP_INI" "${PHP_INI}.bak"
        sed -i 's/^;extension=pdo_sqlite/extension=pdo_sqlite/' "$PHP_INI"
        sed -i 's/^;extension=sqlite3/extension=sqlite3/'       "$PHP_INI"
        echo "  SQLite3 extensions enabled in php.ini."
    else
        echo "  SQLite3 extensions already enabled."
    fi
fi

# -----------------------------------------------------------------------------
# Step 7: Enable ASL3 astdb update service (non-fatal if not ASL3)
# -----------------------------------------------------------------------------
echo ""
echo "[7/8] Configuring ASL3 services..."

if [[ -f /etc/systemd/system/asl3-update-astdb.service ]]; then
    systemctl enable asl3-update-astdb.service 2>/dev/null || true
    systemctl enable asl3-update-astdb.timer   2>/dev/null || true
    systemctl start  asl3-update-astdb.timer   2>/dev/null || true
    echo "  asl3-update-astdb service enabled."
else
    echo "  asl3-update-astdb not found — skipping (OK if not ASL3)."
fi

# Copy DTMF AGI files if present
AGI_SRC="$ASDIR/_tools/agi-bin"
AGI_DST="/usr/share/asterisk/agi-bin"
if [[ -d "$AGI_SRC" && -d "$AGI_DST" ]]; then
    cp -n "$AGI_SRC"/* "$AGI_DST"/ 2>/dev/null || true
    echo "  DTMF AGI files copied."
fi

# Restart Apache to pick up PHP config changes
echo "  Restarting Apache..."
if command -v apachectl &>/dev/null; then
    apachectl restart 2>/dev/null || systemctl restart apache2 2>/dev/null || true
else
    systemctl restart apache2 2>/dev/null || true
fi
echo "  Apache restarted."

# -----------------------------------------------------------------------------
# Step 8: Pre-seed AllScan SQLite database with admin user
# -----------------------------------------------------------------------------
echo ""
echo "[8/8] Pre-seeding AllScan database..."

DBFILE="$ASDBDIR/allscan.db"

# Write the PHP seeder to a temp file.
# Using a temp file + env vars avoids ALL bash string expansion issues —
# bcrypt hashes contain '$' characters that bash mangles inside double-quoted
# strings, silently breaking the hash before PHP ever sees it.
SEEDER_PHP=$(mktemp /tmp/allscan-seed-XXXXXX.php)
chmod 600 "$SEEDER_PHP"

cat > "$SEEDER_PHP" << 'PHPEOF'
<?php
// AllScan DB seeder — called by install-allscan.sh
// All dynamic values arrive via environment variables so bash never touches them.

$dbfile   = getenv('AS_DBFILE');
$username = getenv('AS_USER');
$password = getenv('AS_PASS');
$now      = (int)getenv('AS_NOW');

if (!$dbfile || !$username || !$password) {
    fwrite(STDERR, "ERROR: AS_DBFILE, AS_USER and AS_PASS env vars must be set\n");
    exit(1);
}

// Generate bcrypt hash — identical to AllScan's own password_hash() call
$hash = password_hash($password, PASSWORD_BCRYPT);
if (!$hash) {
    fwrite(STDERR, "ERROR: password_hash() failed\n");
    exit(1);
}

// Open / create the DB
$db = new SQLite3($dbfile);
if (!$db) {
    fwrite(STDERR, "ERROR: Could not open/create $dbfile\n");
    exit(1);
}

// Enable WAL mode for better concurrent access by Apache
$db->exec('PRAGMA journal_mode=WAL;');

// Create user table (matches AllScan's createUserSql in dbUtils.php exactly)
$db->exec('CREATE TABLE IF NOT EXISTS user (
    user_id      INTEGER PRIMARY KEY,
    name         TEXT NOT NULL,
    hash         TEXT NOT NULL,
    email        TEXT,
    location     TEXT,
    nodenums     TEXT,
    permission   INTEGER NOT NULL DEFAULT 1,
    timezone_id  INTEGER NOT NULL DEFAULT 0,
    last_login   INTEGER,
    last_ip_addr TEXT);');

// Create cfg table (matches AllScan's createCfgSql in dbUtils.php exactly)
$db->exec('CREATE TABLE IF NOT EXISTS cfg (
    cfg_id  INTEGER PRIMARY KEY,
    val     TEXT NOT NULL,
    updated INTEGER NOT NULL);');

// Insert admin user — permission 14 = PERMISSION_SUPERUSER (UserModel.php)
$cnt = $db->querySingle('SELECT COUNT(*) FROM user');
if ($cnt == 0) {
    $stmt = $db->prepare(
        'INSERT INTO user
            (name, hash, email, location, nodenums, permission, timezone_id, last_login, last_ip_addr)
         VALUES
            (:name, :hash, :email, :location, :nodenums, :permission, :timezone_id, :last_login, :last_ip_addr)'
    );
    $stmt->bindValue(':name',         $username, SQLITE3_TEXT);
    $stmt->bindValue(':hash',         $hash,     SQLITE3_TEXT);
    $stmt->bindValue(':email',        '',        SQLITE3_TEXT);
    $stmt->bindValue(':location',     '',        SQLITE3_TEXT);
    $stmt->bindValue(':nodenums',     '',        SQLITE3_TEXT);
    $stmt->bindValue(':permission',   14,        SQLITE3_INTEGER);
    $stmt->bindValue(':timezone_id',  0,         SQLITE3_INTEGER);
    $stmt->bindValue(':last_login',   0,         SQLITE3_INTEGER);
    $stmt->bindValue(':last_ip_addr', '',        SQLITE3_TEXT);
    $result = $stmt->execute();
    if (!$result) {
        fwrite(STDERR, "ERROR: INSERT user failed: " . $db->lastErrorMsg() . "\n");
        exit(1);
    }
    echo "Admin user '$username' inserted.\n";
} else {
    echo "User table already has $cnt user(s) — skipping insert.\n";
}

// cfg_id 2 = favsIniLoc — use /etc/allscan/favorites.ini as primary location
// (RLNZ2 has no Supermon, so no need to check ../supermon/favorites.ini first)
$favLoc = '/etc/allscan/favorites.ini,favorites.ini';
$existing = $db->querySingle('SELECT cfg_id FROM cfg WHERE cfg_id=2');
if (!$existing) {
    $stmt = $db->prepare('INSERT INTO cfg (cfg_id, val, updated) VALUES (2, :val, :ts)');
    $stmt->bindValue(':val', $favLoc, SQLITE3_TEXT);
    $stmt->bindValue(':ts',  $now,    SQLITE3_INTEGER);
    $stmt->execute();
    echo "favsIniLoc config set.\n";
}

// cfg_id 1 = publicPermission — 2 = PERMISSION_READ_ONLY (AllScan default)
$existing = $db->querySingle('SELECT cfg_id FROM cfg WHERE cfg_id=1');
if (!$existing) {
    $stmt = $db->prepare('INSERT INTO cfg (cfg_id, val, updated) VALUES (1, :val, :ts)');
    $stmt->bindValue(':val', '2', SQLITE3_TEXT);
    $stmt->bindValue(':ts',  $now, SQLITE3_INTEGER);
    $stmt->execute();
    echo "publicPermission config set.\n";
}

// Verify — confirm user made it in
$userCnt = $db->querySingle('SELECT COUNT(*) FROM user');
echo "DB verification: $userCnt user(s) in database.\n";

$db->close();
exit(0);
PHPEOF

# Run the seeder, passing all dynamic values via environment variables
# so bash never has a chance to mangle them
AS_DBFILE="$DBFILE" \
AS_USER="$ALLSCAN_USER" \
AS_PASS="$ALLSCAN_PASS" \
AS_NOW="$(date +%s)" \
php "$SEEDER_PHP"

SEEDER_EXIT=$?
rm -f "$SEEDER_PHP"

if [[ $SEEDER_EXIT -ne 0 ]]; then
    echo "ERROR: Database seeding failed (exit $SEEDER_EXIT). Check PHP errors above."
    exit 1
fi

# Set DB file permissions so Apache/www-data can read and write it
chmod 664 "$DBFILE"
chgrp "$WEBGROUP" "$DBFILE"
echo "  Database ready: $DBFILE"

# Create a blank favorites.ini in /etc/allscan/ if not already present
# (will be populated by RLNZ2 setup with the preconfigured favourites list)
FAVSFILE="$ASDBDIR/favorites.ini"
if [[ ! -f "$FAVSFILE" ]]; then
    cat > "$FAVSFILE" << 'FAVSEOF'
; AllScan favorites file - managed by RLNZ2
; Format:
;   label[] = "Name NodeNumber"
;   cmd[]   = "rpt cmd %node% ilink 3 NodeNumber"
;
[general]

FAVSEOF
    chmod 664 "$FAVSFILE"
    chgrp "$WEBGROUP" "$FAVSFILE"
    echo "  Blank favorites.ini created at $FAVSFILE"
fi

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  AllScan Installation Complete"
echo "=============================================="

# Report the local IP and hostname for access URLs
HOSTNAME=$(hostname)
LANIP=$(hostname -I | awk '{print $1}')

echo ""
echo "  AllScan is accessible at:"
echo "    http://$HOSTNAME.local/allscan/"
[[ -n "$LANIP" ]] && echo "    http://$LANIP/allscan/"
echo ""
echo "  Admin login:"
echo "    Username : $ALLSCAN_USER"
echo "    Password : (as supplied to this script)"
echo ""
echo "  Favourites file:"
echo "    $FAVSFILE"
echo ""
echo "  To check Apache status : sudo systemctl status apache2"
echo "  To check AllScan logs  : sudo journalctl -u apache2 -f"
echo "=============================================="
