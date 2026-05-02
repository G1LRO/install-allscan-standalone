#!/bin/bash

##############################################################################
# AllStarLink 3 Configuration Script
# This script updates AllStarLink 3 configuration files with user-specific
# information and applies standardized settings.
##############################################################################

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration variables
ASTERISK_DIR="/etc/asterisk"
ALLMON3_DIR="/etc/allmon3"
BACKUP_DIR="$HOME/asl3-backup-$(date +%Y%m%d-%H%M%S)"
FACTORY_BACKUP_DIR="$HOME/asl3-backup-FACTORY"
WEB_ROOT="/var/www/html"

# User-specific variables (to be filled in)
NODE_NUMBER=""
CALLSIGN=""
NODE_PASSWORD=""

##############################################################################
# Functions
##############################################################################

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 -n NODE_NUMBER -c CALLSIGN -p PASSWORD [-b]

Options:
    -n NODE_NUMBER    Your AllStarLink node number (e.g., 58175)
    -c CALLSIGN       Your callsign (e.g., GU1LRO)
    -p PASSWORD       Your node password from AllStarLink portal
    -b                Skip backup creation
    -h                Show this help message

Example:
    sudo $0 -n 58175 -c GU1LRO -p cefa7d18034b

Note: This script must be run with sudo/root privileges.

EOF
    exit 1
}

create_backup() {
    print_info "Creating backup at: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/etc"
    
    if [ -d "$ASTERISK_DIR" ]; then
        cp -r "$ASTERISK_DIR" "$BACKUP_DIR/etc/" 2>/dev/null || true
    fi
    
    if [ -d "$ALLMON3_DIR" ]; then
        cp -r "$ALLMON3_DIR" "$BACKUP_DIR/etc/" 2>/dev/null || true
    fi
    
    # Get the original user (not root) for ownership
    if [ -n "$SUDO_USER" ]; then
        chown -R $SUDO_USER:$SUDO_USER "$BACKUP_DIR" 2>/dev/null || true
    fi
    
    print_info "Backup created successfully"
}

create_factory_backup() {
    if [ -d "$FACTORY_BACKUP_DIR" ]; then
        print_info "Factory backup already exists at: $FACTORY_BACKUP_DIR"
        return
    fi
    
    print_info "Creating factory backup at: $FACTORY_BACKUP_DIR"
    print_info "This will be used as the restore point for future configurations"
    
    mkdir -p "$FACTORY_BACKUP_DIR/etc"
    
    if [ -d "$ASTERISK_DIR" ]; then
        cp -r "$ASTERISK_DIR" "$FACTORY_BACKUP_DIR/etc/" 2>/dev/null || true
    fi
    
    if [ -d "$ALLMON3_DIR" ]; then
        cp -r "$ALLMON3_DIR" "$FACTORY_BACKUP_DIR/etc/" 2>/dev/null || true
    fi
    
    if [ -d "$WEB_ROOT" ]; then
        cp -r "$WEB_ROOT" "$FACTORY_BACKUP_DIR/" 2>/dev/null || true
    fi
    
    # Get the original user (not root) for ownership
    if [ -n "$SUDO_USER" ]; then
        chown -R $SUDO_USER:$SUDO_USER "$FACTORY_BACKUP_DIR" 2>/dev/null || true
    fi
    
    print_info "Factory backup created successfully"
}

restore_factory_backup() {
    if [ ! -d "$FACTORY_BACKUP_DIR" ]; then
        print_warn "No factory backup found - skipping restore"
        return
    fi
    
    print_info "Restoring from factory backup: $FACTORY_BACKUP_DIR"
    
    if [ -d "$FACTORY_BACKUP_DIR/etc/asterisk" ]; then
        cp -r "$FACTORY_BACKUP_DIR/etc/asterisk" /etc/ 2>/dev/null || true
        print_info "Restored Asterisk configs"
    fi
    
    if [ -d "$FACTORY_BACKUP_DIR/etc/allmon3" ]; then
        cp -r "$FACTORY_BACKUP_DIR/etc/allmon3" /etc/ 2>/dev/null || true
        print_info "Restored Allmon3 configs"
    fi
    
    if [ -d "$FACTORY_BACKUP_DIR/var/www/html" ]; then
        cp -r "$FACTORY_BACKUP_DIR/var/www/html"/* /var/www/html/ 2>/dev/null || true
        print_info "Restored web files"
    fi
    
    print_info "Factory restore completed"
}

update_allmon3_ini() {
    # Allmon3 is optional on RLNZ2 — skip entirely if not installed
    if [ ! -d "$ALLMON3_DIR" ]; then
        print_warn "Allmon3 not found at $ALLMON3_DIR — skipping"
        return 0
    fi

    local file="$ALLMON3_DIR/allmon3.ini"
    if [ ! -f "$file" ]; then
        print_warn "File not found: $file (skipping)"
        return 0
    fi

    print_info "Updating $file"

    # Update the node stanza - find [XXXXX] pattern and replace with new node number
    sed -i "s/^\[[0-9]\{1,\}\]$/[$NODE_NUMBER]/" "$file" || {
        print_warn "Failed to update $file — check file permissions"
        return 0
    }
}

update_extensions_conf() {
    local file="$ASTERISK_DIR/extensions.conf"
    if [ ! -f "$file" ]; then
        print_warn "File not found: $file (skipping)"
        return 0
    fi

    print_info "Updating $file"

    # Show what the file actually has so we can diagnose any future mismatches
    local existing
    existing=$(grep -iE "^NODE" "$file" 2>/dev/null || true)
    if [ -n "$existing" ]; then
        print_info "extensions.conf NODE line found: '$existing'"
    else
        print_warn "No NODE line found in extensions.conf [globals] — will attempt to add it"
    fi

    # Match NODE with any content after = (handles numeric, placeholder text, empty, any spacing)
    if grep -qiE "^NODE[[:space:]]*=" "$file"; then
        sed -i -E "s/^NODE[[:space:]]*=.*/NODE = $NODE_NUMBER/" "$file"
    else
        # NODE line is missing entirely — add it into the [globals] section
        if grep -q "^\[globals\]" "$file"; then
            sed -i "/^\[globals\]/a NODE = $NODE_NUMBER" "$file"
            print_info "NODE line added to [globals] section"
        else
            print_warn "No [globals] section found in extensions.conf — NODE not set"
        fi
    fi
}

update_rpt_conf() {
    local file="$ASTERISK_DIR/rpt.conf"
    if [ ! -f "$file" ]; then
        print_warn "File not found: $file (skipping)"
        return
    fi
    
    print_info "Updating $file"
    
    # Update node line in [nodes] section: 1999 = radio@127.0.0.1/1999,NONE
    sed -i "s/^[0-9]\{1,\} = radio@127\.0\.0\.1\/[0-9]\{1,\},NONE$/$NODE_NUMBER = radio@127.0.0.1\/$NODE_NUMBER,NONE/" "$file"
    
    # Update node stanza: [1999](node-main)
    sed -i "s/^\[[0-9]\{1,\}\](node-main)$/[$NODE_NUMBER](node-main)/" "$file"
    
    # Update rxchannel line
    sed -i "s/^rxchannel = SimpleUSB\/[0-9]\{1,\}/rxchannel = SimpleUSB\/$NODE_NUMBER/" "$file"
    
    # Add/update settings after the node stanza
    # First, check if statpost_url exists, if not add it after the node stanza line
    if ! grep -q "^statpost_url" "$file"; then
        sed -i "/^\[$NODE_NUMBER\](node-main)/a statpost_url = http://stats.allstarlink.org/uhandler" "$file"
    fi
    
    # Add/update idrecording with callsign
    if grep -q "^idrecording" "$file"; then
        sed -i "s/^idrecording = .*$/idrecording = |i$CALLSIGN/" "$file"
    else
        sed -i "/^statpost_url/a idrecording = |i$CALLSIGN" "$file"
    fi
    
    # Add/update duplex
    if ! grep -q "^duplex" "$file"; then
        sed -i "/^idrecording/a duplex = 1" "$file"
    fi
    
    # Add/update hangtime
    if ! grep -q "^hangtime" "$file"; then
        sed -i "/^duplex/a hangtime = 400" "$file"
    fi
}

update_rpt_http_registrations() {
    local file="$ASTERISK_DIR/rpt_http_registrations.conf"
    if [ ! -f "$file" ]; then
        print_warn "File not found: $file (skipping)"
        return
    fi
    
    print_info "Updating $file"
    
    # Update registration line: register => 99999:abcdefgh1234@register.allstarlink.org
    sed -i "s/^register => [0-9]\{1,\}:.*@register\.allstarlink\.org$/register => $NODE_NUMBER:$NODE_PASSWORD@register.allstarlink.org/" "$file"
}

update_savenode_conf() {
    local file="$ASTERISK_DIR/savenode.conf"
    if [ ! -f "$file" ]; then
        print_warn "File not found: $file (skipping)"
        return
    fi
    
    print_info "Updating $file"
    
    sed -i "s/^NODE=.*$/NODE=$NODE_NUMBER/" "$file"
    sed -i "s/^PASSWORD=.*$/PASSWORD=$NODE_PASSWORD/" "$file"
    sed -i "s/^ENABLE=.*$/ENABLE=1/" "$file"
}

update_simpleusb_conf() {
    local file="$ASTERISK_DIR/simpleusb.conf"
    if [ ! -f "$file" ]; then
        print_warn "File not found: $file (skipping)"
        return
    fi
    
    print_info "Updating $file"
    
    # Update node stanza
    sed -i "s/^\[[0-9]\{1,\}\](node-main)$/[$NODE_NUMBER](node-main)/" "$file"
    
    # Apply standardized settings
    sed -i "s/^devstr.*=.*$/devstr = 1-1:1.0/" "$file"
    sed -i "s/^rxmixerset.*=.*$/rxmixerset = 600/" "$file"
    sed -i "s/^txmixaset.*=.*$/txmixaset = 999/" "$file"
    sed -i "s/^txmixbset.*=.*$/txmixbset = 500/" "$file"
    
    # Add ctcssfrom if not present in this specific node stanza
    # Check only within the node stanza boundaries, not the entire file
    if ! sed -n "/^\[$NODE_NUMBER\](node-main)/,/^\[/p" "$file" | grep -q "^ctcssfrom"; then
        sed -i "/^\[$NODE_NUMBER\](node-main)/a ctcssfrom = no" "$file"
    fi
}

update_usbradio_conf() {
    local file="$ASTERISK_DIR/usbradio.conf"
    if [ ! -f "$file" ]; then
        print_warn "File not found: $file (skipping)"
        return
    fi
    
    print_info "Updating $file"
    
    # Update node stanza
    sed -i "s/^\[[0-9]\{1,\}\](node-main)$/[$NODE_NUMBER](node-main)/" "$file"
}

update_voter_conf() {
    local file="$ASTERISK_DIR/voter.conf"
    if [ ! -f "$file" ]; then
        print_warn "File not found: $file (skipping)"
        return
    fi
    
    print_info "Updating $file"
    
    # Update node stanza - just the number in brackets
    sed -i "s/^\[[0-9]\{1,\}\].*$/[$NODE_NUMBER]                          ; define the $NODE_NUMBER instance stanza/" "$file"
}

update_landing_page() {
    local index_file="$WEB_ROOT/index.html"
    local source_index="$HOME/index.html"
    
    # Check if the source index.html exists
    if [ ! -f "$source_index" ]; then
        print_warn "Source index.html not found: $source_index (skipping)"
        print_info "Note: Place index.html in $HOME for landing page updates"
        return
    fi
    
    # Check if web root exists
    if [ ! -d "$WEB_ROOT" ]; then
        print_warn "Web root not found: $WEB_ROOT (skipping)"
        print_info "Note: Landing page is only present on ASL3 Pi Appliance installations"
        return
    fi
    
    print_info "Updating landing page $index_file"
    
    # Backup the existing index.html if it exists
    if [ -f "$index_file" ]; then
        cp "$index_file" "$index_file.backup-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    fi
    
    # Copy the new index.html from home directory to web root
    cp "$source_index" "$index_file"
    
    # Update node number references in the HTML if they exist
    sed -i "s/node[0-9]\{1,\}/node$NODE_NUMBER/gi" "$index_file"
    sed -i "s/Node [0-9]\{1,\}/Node $NODE_NUMBER/g" "$index_file"
    sed -i "s/NODE [0-9]\{1,\}/NODE $NODE_NUMBER/g" "$index_file"
    
    print_info "Landing page updated successfully"
}

update_allscan_password() {
    local dbfile="/etc/allscan/allscan.db"
    local dbdir="/etc/allscan"
    local allscan_webdir="/var/www/html/allscan"

    # Check if AllScan web files are present at all
    if [ ! -d "$allscan_webdir" ]; then
        print_warn "AllScan not installed ($allscan_webdir not found) — skipping password update"
        return 0
    fi

    # Ensure /etc/allscan directory exists with correct permissions
    if [ ! -d "$dbdir" ]; then
        print_info "Creating $dbdir..."
        mkdir -p "$dbdir"
        chmod 775 "$dbdir"
        chgrp www-data "$dbdir" 2>/dev/null || true
    fi

    print_info "Updating AllScan admin password..."

    # AllScan requires 6-16 chars from: a-zA-Z0-9 ~ ! @ # $ ^ & * , . _ -
    if ! echo "$NODE_PASSWORD" | grep -qP '^[a-zA-Z0-9~!@#$^&*,._-]{6,16}$'; then
        print_warn "Password does not meet AllScan requirements (6-16 chars, alphanumeric + ~!@#\$^&*,._-)"
        print_warn "AllScan password not updated — set it manually via the AllScan web interface"
        return 0
    fi

    # Write PHP to a temp file and pass all values via env vars.
    # This avoids bash expanding '$2y$10$...' bcrypt hash characters inside
    # double-quoted strings, which silently corrupts the hash.
    local tmpphp
    tmpphp=$(mktemp /tmp/allscan-pw-XXXXXX.php) || return 0
    chmod 600 "$tmpphp"

    cat > "$tmpphp" << 'PHPEOF'
<?php
$dbfile   = getenv('AS_DBFILE');
$password = getenv('AS_PASS');
$username = 'rln';

if (!$dbfile || !$password) {
    fwrite(STDERR, "ERROR: AS_DBFILE and AS_PASS env vars must be set\n");
    exit(1);
}

$hash = password_hash($password, PASSWORD_BCRYPT);
if (!$hash) {
    fwrite(STDERR, "ERROR: password_hash() failed\n");
    exit(1);
}

$db = new SQLite3($dbfile);
if (!$db) {
    fwrite(STDERR, "ERROR: Could not open $dbfile\n");
    exit(1);
}

$db->exec('PRAGMA journal_mode=WAL;');

// Create tables if they don't exist (safe no-op if already present)
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

$db->exec('CREATE TABLE IF NOT EXISTS cfg (
    cfg_id  INTEGER PRIMARY KEY,
    val     TEXT NOT NULL,
    updated INTEGER NOT NULL);');

// Check if rln user already exists
$existing = $db->querySingle("SELECT user_id FROM user WHERE name = '$username'");

if ($existing) {
    // UPDATE existing user's hash
    $stmt = $db->prepare('UPDATE user SET hash = :hash WHERE name = :name');
    $stmt->bindValue(':hash', $hash, SQLITE3_TEXT);
    $stmt->bindValue(':name', $username, SQLITE3_TEXT);
    $stmt->execute();
    echo "updated:" . $db->changes() . "\n";
} else {
    // INSERT new user — permission 14 = PERMISSION_SUPERUSER
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
    $stmt->execute();
    echo "inserted:" . $db->changes() . "\n";

    // Set favsIniLoc (cfg_id=2) — use /etc/allscan/favorites.ini as primary
    $now = time();
    $favLoc = '/etc/allscan/favorites.ini,favorites.ini';
    $ex = $db->querySingle('SELECT cfg_id FROM cfg WHERE cfg_id=2');
    if (!$ex) {
        $s = $db->prepare('INSERT INTO cfg (cfg_id, val, updated) VALUES (2, :val, :ts)');
        $s->bindValue(':val', $favLoc, SQLITE3_TEXT);
        $s->bindValue(':ts',  $now,    SQLITE3_INTEGER);
        $s->execute();
    }
    // Set publicPermission (cfg_id=1) — 2 = PERMISSION_READ_ONLY
    $ex = $db->querySingle('SELECT cfg_id FROM cfg WHERE cfg_id=1');
    if (!$ex) {
        $s = $db->prepare('INSERT INTO cfg (cfg_id, val, updated) VALUES (1, :val, :ts)');
        $s->bindValue(':val', '2', SQLITE3_TEXT);
        $s->bindValue(':ts',  $now, SQLITE3_INTEGER);
        $s->execute();
    }
}

$db->close();
PHPEOF

    local result
    result=$(AS_DBFILE="$dbfile" AS_PASS="$LOGIN_PASSWORD" \
        php "$tmpphp" 2>/tmp/allscan-pw-err.txt) || true
    rm -f "$tmpphp"

    # Parse result
    if echo "$result" | grep -q '^updated:'; then
        local rows
        rows=$(echo "$result" | grep '^updated:' | cut -d: -f2)
        if [ "${rows:-0}" -gt 0 ]; then
            print_info "AllScan admin password updated (user: rln)"
        else
            print_warn "AllScan UPDATE ran but 0 rows affected — unexpected DB state"
        fi
    elif echo "$result" | grep -q '^inserted:'; then
        print_info "AllScan admin user 'rln' created and password set"
        # Set correct permissions on the new DB file
        chmod 664 "$dbfile" 2>/dev/null || true
        chgrp www-data "$dbfile" 2>/dev/null || true
    else
        local errmsg
        errmsg=$(cat /tmp/allscan-pw-err.txt 2>/dev/null || true)
        print_warn "AllScan password update failed — ${errmsg:-unknown error}"
        print_info "Check PHP is installed and $dbfile is writable by root"
    fi
    rm -f /tmp/allscan-pw-err.txt
    return 0
}

verify_changes() {
    print_info "Verifying changes..."
    local errors=0
    
    # Check savenode.conf
    if [ -f "$ASTERISK_DIR/savenode.conf" ]; then
        if ! grep -q "^NODE=$NODE_NUMBER" "$ASTERISK_DIR/savenode.conf"; then
            print_error "NODE setting incorrect in savenode.conf"
            ((errors++))
        fi
        if ! grep -q "^ENABLE=1" "$ASTERISK_DIR/savenode.conf"; then
            print_error "ENABLE not set to 1 in savenode.conf"
            ((errors++))
        fi
    fi
    
    # Check extensions.conf
    if [ -f "$ASTERISK_DIR/extensions.conf" ]; then
        if ! grep -qE "^NODE[[:space:]]*=[[:space:]]*$NODE_NUMBER" "$ASTERISK_DIR/extensions.conf"; then
            print_error "NODE setting incorrect in extensions.conf"
            ((errors++))
        fi
    fi
    
    # Check rpt.conf
    if [ -f "$ASTERISK_DIR/rpt.conf" ]; then
        if ! grep -q "^\[$NODE_NUMBER\](node-main)" "$ASTERISK_DIR/rpt.conf"; then
            print_error "Node stanza not found in rpt.conf"
            ((errors++))
        fi
        if ! grep -q "idrecording = |i$CALLSIGN" "$ASTERISK_DIR/rpt.conf"; then
            print_error "Callsign not found in rpt.conf"
            ((errors++))
        fi
    fi
    
    # Check simpleusb.conf
    if [ -f "$ASTERISK_DIR/simpleusb.conf" ]; then
        if ! grep -q "^\[$NODE_NUMBER\](node-main)" "$ASTERISK_DIR/simpleusb.conf"; then
            print_error "Node stanza not found in simpleusb.conf"
            ((errors++))
        fi
        if ! grep -q "^txmixaset = 999" "$ASTERISK_DIR/simpleusb.conf"; then
            print_error "Audio settings not updated in simpleusb.conf"
            ((errors++))
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        print_info "All verifications passed!"
        return 0
    else
        print_error "$errors verification(s) failed"
        return 1
    fi
}

##############################################################################
# Main Script
##############################################################################

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "This script must be run with sudo or as root"
    exit 1
fi

# Parse command line arguments
SKIP_BACKUP=false
LOGIN_PASSWORD=""

while getopts "n:c:p:w:bh" opt; do
    case $opt in
        n) NODE_NUMBER="$OPTARG" ;;
        c) CALLSIGN="$OPTARG" ;;
        p) NODE_PASSWORD="$OPTARG" ;;
        w) LOGIN_PASSWORD="$OPTARG" ;;
        b) SKIP_BACKUP=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

# If no login password supplied, fall back to node password
if [ -z "$LOGIN_PASSWORD" ]; then
    LOGIN_PASSWORD="$NODE_PASSWORD"
fi

# Validate required arguments
if [ -z "$NODE_NUMBER" ] || [ -z "$CALLSIGN" ] || [ -z "$NODE_PASSWORD" ]; then
    print_error "Missing required arguments"
    usage
fi

# Validate node number is numeric
if ! [[ "$NODE_NUMBER" =~ ^[0-9]+$ ]]; then
    print_error "Node number must be numeric"
    exit 1
fi

# Convert callsign to uppercase
CALLSIGN=$(echo "$CALLSIGN" | tr '[:lower:]' '[:upper:]')

# Display configuration
echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║   AllStarLink 3 Configuration Script           ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "  Node Number:    $NODE_NUMBER"
echo "  Callsign:       $CALLSIGN"
echo "  Password:       ${NODE_PASSWORD:0:4}****"
echo "  Asterisk Dir:   $ASTERISK_DIR"
echo "  Allmon3 Dir:    $ALLMON3_DIR"
echo ""

# Confirm with user
#read -p "Proceed with configuration? (y/N): " confirm
#if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
#    print_warn "Configuration cancelled"
#    exit 0
#fi

echo ""

# Handle factory backup and restore
if [ -d "$FACTORY_BACKUP_DIR" ]; then
    # Factory backup exists - restore from it automatically
    print_info "Factory backup detected - restoring to clean state..."
    restore_factory_backup
    echo ""
else
    # No factory backup - create one before configuring (first run)
    print_info "First run detected - creating factory backup..."
    create_factory_backup
    echo ""
fi

# Create timestamped backup unless skipped
if [ "$SKIP_BACKUP" = false ]; then
    create_backup
fi

# Update configuration files
print_info "Updating configuration files..."
echo ""

update_allmon3_ini || true
update_extensions_conf
update_rpt_conf
update_rpt_http_registrations
update_savenode_conf
update_simpleusb_conf
update_usbradio_conf
update_voter_conf
# update_landing_page
update_allscan_password || true

echo ""

# Verify changes
if verify_changes; then
    echo ""
    print_info "╔════════════════════════════════════════════════╗"
    print_info "║  Configuration completed successfully!         ║"
    print_info "╚════════════════════════════════════════════════╝"
    echo ""
    print_info "Next steps:"
    echo "  1. Review changes:"
    echo "     sudo diff -ru $BACKUP_DIR/etc /etc | less"
    echo ""
    echo "  2. Restart Asterisk:"
    echo "     sudo systemctl restart asterisk"
    echo ""
    echo "  3. Check Asterisk status:"
    echo "     sudo systemctl status asterisk"
    echo ""
    echo "  4. Connect to Asterisk CLI:"
    echo "     sudo asterisk -rvvv"
    echo ""
    echo "  5. Verify node registration:"
    echo "     sudo asterisk -rx 'rpt nodes $NODE_NUMBER'"
    echo ""
else
    echo ""
    print_error "Configuration completed with errors"
    print_warn "Please review the errors above and check your configuration manually"
    print_info "Backup location: $BACKUP_DIR"
    exit 1
fi
