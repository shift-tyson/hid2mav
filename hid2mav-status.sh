#!/bin/bash
set -euo pipefail

SERVICE_NAME="hid2mav.service"

echo "===== HID2MAV Service Status ====="
systemctl is-active --quiet $SERVICE_NAME && echo "[RUNNING]" || echo "[NOT RUNNING]"
echo

echo "Configured Exec:"
grep ExecStart /etc/systemd/system/$SERVICE_NAME | sed 's/ExecStart=//'
echo

echo "Last 10 log lines:"
journalctl -u $SERVICE_NAME -n 10 --no-pager
