#!/bin/bash
set -euo pipefail

SERVICE_NAME="hid2mav.service"
INSTALL_DIR="/opt/hid2mav"
LOG_FILE="/var/log/hid2mav.log"

GREEN="\033[1;32m"; RED="\033[1;31m"; YELLOW="\033[1;33m"; NC="\033[0m"

echo -e "${YELLOW}[WARN] This will uninstall HID2MAV.${NC}"
read -rp "Are you sure you want to proceed? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && { echo -e "${YELLOW}[INFO] Uninstall cancelled.${NC}"; exit 0; }

# === Stop and disable systemd service ===
if systemctl list-units --full -all | grep -q "$SERVICE_NAME"; then
    echo -e "${GREEN}[INFO] Stopping and disabling service...${NC}"
    sudo systemctl stop "$SERVICE_NAME" || true
    sudo systemctl disable "$SERVICE_NAME" || true
    sudo rm -f "/etc/systemd/system/$SERVICE_NAME"
    sudo systemctl daemon-reload
    echo -e "${GREEN}[OK] Service removed.${NC}"
else
    echo -e "${YELLOW}[INFO] No systemd service found.${NC}"
fi

# === Remove installed files ===
if [[ -d "$INSTALL_DIR" ]]; then
    echo -e "${GREEN}[INFO] Removing $INSTALL_DIR...${NC}"
    sudo rm -rf "$INSTALL_DIR"
else
    echo -e "${YELLOW}[INFO] Install directory not found.${NC}"
fi

# === Remove log file ===
if [[ -f "$LOG_FILE" ]]; then
    read -rp "Remove log file at $LOG_FILE? (y/n): " LOG_CONFIRM
    if [[ "$LOG_CONFIRM" == "y" ]]; then
        sudo rm -f "$LOG_FILE"
        echo -e "${GREEN}[OK] Log file deleted.${NC}"
    else
        echo -e "${YELLOW}[INFO] Log file kept.${NC}"
    fi
fi

echo -e "${GREEN}[DONE] HID2MAV uninstalled.${NC}"
