#!/bin/bash
set -euo pipefail

INSTALL_DIR="/opt/hid2mav"
VENV_DIR="$INSTALL_DIR/venv"
SERVICE_NAME="hid2mav.service"
PY_SCRIPT_NAME="hid2mav-service.py"

echo "[INFO] Installing HID2MAV"

# === Check script ===
[[ -f "$PY_SCRIPT_NAME" ]] || { echo "[ERR] $PY_SCRIPT_NAME not found."; exit 1; }

# === Install deps ===
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip joystick

# === Copy app ===
sudo mkdir -p "$INSTALL_DIR"
sudo cp "$PY_SCRIPT_NAME" "$INSTALL_DIR"
sudo chown -R "$USER:$USER" "$INSTALL_DIR"

# === Setup venv ===
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install pymavlink inputs

# === Prompt serial ===
echo "[INFO] Detecting serial devices..."
SERIAL_DEVS=($(ls /dev/ttyS* /dev/ttyAMA* /dev/serial/by-id/* /dev/ttyUSB* 2>/dev/null || true))
if [[ ${#SERIAL_DEVS[@]} -eq 0 ]]; then
    read -rp "Enter serial device path manually (e.g., /dev/ttyS0): " SERIAL_PATH
else
    i=1; for dev in "${SERIAL_DEVS[@]}"; do echo "  [$i] $dev"; ((i++)); done
    read -rp "Select serial device: " SEL
    SERIAL_PATH="${SERIAL_DEVS[$((SEL-1))]}"
fi

# === Prompt HID ===
echo "[INFO] Detecting HID devices..."
HID_DEVS=($(ls /dev/input/js* 2>/dev/null || true))
if [[ ${#HID_DEVS[@]} -eq 0 ]]; then
    read -rp "Enter HID device manually (e.g., /dev/input/js0): " HID_PATH
else
    i=1; for dev in "${HID_DEVS[@]}"; do
        NAME=$(cat /sys/class/input/"$(basename "$dev")"/device/name 2>/dev/null || echo "Unknown")
        echo "  [$i] $dev — $NAME"
        ((i++))
    done
    read -rp "Select HID device: " SEL
    HID_PATH="${HID_DEVS[$((SEL-1))]}"
fi

# === Service ===
echo "[INFO] Writing systemd service..."
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

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

echo "[OK] Installed and running as systemd service: $SERVICE_NAME"
