# HID2MAV

A lightweight Linux-based system for converting HID joystick input into MAVLink RC overrides over a Microhard telemetry link (UART).

## Components

-  `hid2mav-service.py` — main Python service (runs as a systemd unit)
-  `hid2mav-install.sh` — installs Python dependencies, sets up the systemd service
-  `hid2mav-configure.sh` — reconfigures serial/HID device selection and updates the service
-  `hid2mav-status.sh` — prints service status and last logs
-  `hid2mav-test.py` — live joystick monitor (GUI by default, falls back to console)

## Requirements

-  Python 3
-  Linux (Debian-based recommended)
-  Joystick or gamepad connected via `/dev/input/js*`
-  Telemetry radio connected via UART (`/dev/ttyS*`, `/dev/ttyAMA*`, etc.)

Install dependencies:

```bash
sudo apt-get install python3 python3-venv python3-pip joystick
pip install inputs pymavlink
```
