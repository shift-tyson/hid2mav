#!/bin/bash
set -euo pipefail

SERVICE_NAME="hid2mav.service"
PY_SCRIPT_PATH=$(awk -F' ' '/ExecStart/ { print $2 }' /etc/systemd/system/$SERVICE_NAME)
INSTALL_DIR=$(dirname "$PY_SCRIPT_PATH")
VENV_DIR="$INSTALL_DIR/venv"
PY_SCRIPT_NAME=$(basename "$PY_SCRIPT_PATH")

echo "[INFO] Configuring HID2MAV service..."

# === Prompt serial ===
echo "[INFO] Detecting serial devices..."
SERIAL_DEVS=($(ls /dev/ttyS* /dev/ttyAMA* /dev/serial/by-id/* /dev/ttyUSB* 2>/dev/null || true))
if [[ ${#SERIAL_DEVS[@]} -eq 0 ]]; then
    read -rp "Enter serial device manually (e.g., /dev/ttyS0): " SERIAL_PATH
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

# === Update systemd unit ===
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
sudo systemctl restart "$SERVICE_NAME"

echo "[OK] HID2MAV service reconfigured and restarted."
