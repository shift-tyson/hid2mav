#!/bin/bash
set -euo pipefail

# === CONFIG ===
INSTALL_DIR="/opt/hid2mav"
VENV_DIR="$INSTALL_DIR/venv"
SERVICE_NAME="hid2mav.service"
PY_SCRIPT_NAME="hid2mav-service.py"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/hid2mav.log"

# === COLORS ===
GREEN="\033[1;32m"; RED="\033[1;31m"; YELLOW="\033[1;33m"; NC="\033[0m"

echo -e "${GREEN}[INFO] Installing HID2MAV...${NC}"

# === Check for Python script ===
if [[ ! -f "$SCRIPT_DIR/$PY_SCRIPT_NAME" ]]; then
  echo -e "${RED}[ERR] Cannot find $PY_SCRIPT_NAME in $SCRIPT_DIR${NC}"
  exit 1
fi

# === Install system dependencies ===
echo -e "${GREEN}[INFO] Installing system packages...${NC}"
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip joystick

# === Copy files ===
echo -e "${GREEN}[INFO] Copying files to $INSTALL_DIR...${NC}"
sudo mkdir -p "$INSTALL_DIR"
sudo cp "$SCRIPT_DIR/$PY_SCRIPT_NAME" "$INSTALL_DIR"
sudo chown -R "$USER:$USER" "$INSTALL_DIR"

# === Setup log file ===
echo -e "${GREEN}[INFO] Creating log file...${NC}"
sudo touch "$LOG_FILE"
sudo chown "$USER:$USER" "$LOG_FILE"

# === Setup virtual environment ===
echo -e "${GREEN}[INFO] Setting up Python virtual environment...${NC}"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip || { echo -e "${RED}[ERR] pip upgrade failed${NC}"; exit 1; }
"$VENV_DIR/bin/pip" install pymavlink inputs || { echo -e "${RED}[ERR] pip install failed${NC}"; exit 1; }

# === Serial selection ===
echo -e "${GREEN}[INFO] Detecting serial devices...${NC}"
SERIAL_DEVS=($(ls /dev/ttyS* /dev/ttyAMA* /dev/serial/by-id/* /dev/ttyUSB* 2>/dev/null || true))
if [[ ${#SERIAL_DEVS[@]} -eq 0 ]]; then
  read -rp "Enter serial device manually (e.g., /dev/ttyS0): " SERIAL_PATH
else
  i=1; for dev in "${SERIAL_DEVS[@]}"; do echo "  [$i] $dev"; ((i++)); done
  read -rp "Select serial device by number: " SEL
  if ! [[ "$SEL" =~ ^[0-9]+$ ]] || (( SEL < 1 || SEL > ${#SERIAL_DEVS[@]} )); then
    echo -e "${RED}[ERR] Invalid selection.${NC}"
    exit 1
  fi
  SERIAL_PATH="${SERIAL_DEVS[$((SEL-1))]}"
fi

# === HID selection ===
echo -e "${GREEN}[INFO] Detecting joystick devices...${NC}"
HID_DEVS=($(ls /dev/input/js* 2>/dev/null || true))
if [[ ${#HID_DEVS[@]} -eq 0 ]]; then
  read -rp "Enter HID device manually (e.g., /dev/input/js0): " HID_PATH
else
  i=1; for dev in "${HID_DEVS[@]}"; do
    NAME=$(cat /sys/class/input/"$(basename "$dev")"/device/name 2>/dev/null || echo "Unknown")
    echo "  [$i] $dev — $NAME"
    ((i++))
  done
  read -rp "Select HID device by number: " SEL
  if ! [[ "$SEL" =~ ^[0-9]+$ ]] || (( SEL < 1 || SEL > ${#HID_DEVS[@]} )); then
    echo -e "${RED}[ERR] Invalid selection.${NC}"
    exit 1
  fi
  HID_PATH="${HID_DEVS[$((SEL-1))]}"
fi

# === Confirm overwrite if service exists ===
if [[ -f "/etc/systemd/system/$SERVICE_NAME" ]]; then
  read -rp "Service already exists. Overwrite and restart? (y/n): " CONFIRM
  [[ "$CONFIRM" != "y" ]] && { echo -e "${YELLOW}[INFO] Aborting.${NC}"; exit 0; }
fi

# === Write systemd service ===
echo -e "${GREEN}[INFO] Writing systemd service to /etc/systemd/system/$SERVICE_NAME...${NC}"
cat <<EOF | sudo tee /etc/systemd/system/$SERVICE_NAME > /dev/null
[Unit]
Description=HID to MAVLink bridge
After=network.target

[Service]
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/$PY_SCRIPT_NAME --serial $SERIAL_PATH --hid $HID_PATH
WorkingDirectory=$INSTALL_DIR
Restart=on-failure
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# === Enable + start service ===
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

echo -e "${GREEN}[OK] HID2MAV installed and running as systemd service: $SERVICE_NAME${NC}"
