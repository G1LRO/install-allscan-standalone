#!/bin/bash
# =============================================================================
# deploy-allscan-update.sh
# Deploys AllScan integration files to correct locations on the RLNZ2
# Run from the directory containing the update files:
#   sudo bash deploy-allscan-update.sh
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: Run as root (sudo)${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_ROUTES="/home/rln/myenv/lib/python3.11/site-packages/server/routes"

echo "=============================================="
echo "  RLNZ2 AllScan Integration Deploy"
echo "=============================================="

# Verify all source files are present
for f in configure-asl3.sh asl.py configuration.py; do
    if [[ ! -f "$SCRIPT_DIR/$f" ]]; then
        echo -e "${RED}ERROR: $f not found in $SCRIPT_DIR${NC}"
        exit 1
    fi
done

# 1. configure-asl3.sh
echo "[1/4] Deploying configure-asl3.sh..."
cp "$SCRIPT_DIR/configure-asl3.sh" /home/rln/configure-asl3.sh
chmod +x /home/rln/configure-asl3.sh
echo -e "${GREEN}  ✓ /home/rln/configure-asl3.sh${NC}"

# 2. asl.py
echo "[2/4] Deploying asl.py..."
cp "$SCRIPT_DIR/asl.py" "$VENV_ROUTES/asl.py"
echo -e "${GREEN}  ✓ $VENV_ROUTES/asl.py${NC}"

# 3. configuration.py
echo "[3/4] Deploying configuration.py..."
cp "$SCRIPT_DIR/configuration.py" "$VENV_ROUTES/configuration.py"
echo -e "${GREEN}  ✓ $VENV_ROUTES/configuration.py${NC}"

# 4. Restart config server
echo "[4/4] Restarting config server..."
systemctl restart rlnz2-config-server
sleep 2
if systemctl is-active --quiet rlnz2-config-server; then
    echo -e "${GREEN}  ✓ rlnz2-config-server running${NC}"
else
    echo -e "${RED}  ✗ rlnz2-config-server failed to start${NC}"
    journalctl -u rlnz2-config-server -n 20 --no-pager
    exit 1
fi

echo ""
echo "=============================================="
echo -e "${GREEN}  Deploy complete!${NC}"
echo "=============================================="
echo ""
echo "  Next steps:"
echo "  1. Run the web setup to apply your login password to AllScan"
echo "  2. Test AllScan at http://$(hostname -I | awk '{print $1}')/allscan"
echo "     Username: rln"
echo "     Password: your login password from web setup"
echo "=============================================="
