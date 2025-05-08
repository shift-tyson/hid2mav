#!/usr/bin/env python3
import logging
import time
import argparse
import os
import stat
import platform
import getpass
import signal
from pymavlink import mavutil
from inputs import get_gamepad

# === LOGGING SETUP ===
log = logging.getLogger("HID2MAV")
log.setLevel(logging.DEBUG)
formatter = logging.Formatter('[%(asctime)s] [%(levelname)s] %(message)s', "%Y-%m-%d %H:%M:%S")
stream_handler = logging.StreamHandler()
stream_handler.setFormatter(formatter)
file_handler = logging.FileHandler("/var/log/hid2mav.log")
file_handler.setFormatter(formatter)
log.addHandler(stream_handler)
log.addHandler(file_handler)

log.info(f"Starting HID2MAV as user {getpass.getuser()} on {platform.system()} {platform.release()} ({platform.machine()})")

# === ARGS ===
parser = argparse.ArgumentParser(description="Convert joystick input to MAVLink MANUAL_CONTROL messages")
parser.add_argument("--serial", required=True, help="Serial device (e.g., /dev/ttyS0 or tcp:host:port)")
parser.add_argument("--hid", required=True, help="Joystick device path (e.g., /dev/input/js0)")
parser.add_argument("--baud", type=int, default=57600, help="Baud rate (default: 57600)")
args = parser.parse_args()

# === VALIDATE SERIAL ===
if args.serial.startswith("/dev/"):
    if not os.path.exists(args.serial):
        log.error(f"Serial port '{args.serial}' not found.")
        exit(1)
    try:
        with open(args.serial, 'rb'):
            pass
    except Exception as e:
        log.exception(f"Failed to access serial device '{args.serial}'")
        exit(1)
else:
    log.info(f"Using network serial endpoint: {args.serial}")

# === VALIDATE HID ===
if not os.path.exists(args.hid):
    log.error(f"HID device '{args.hid}' not found.")
    exit(1)

if not stat.S_ISCHR(os.stat(args.hid).st_mode):
    log.error(f"HID device '{args.hid}' is not a character device.")
    exit(1)

try:
    with open(args.hid, 'rb'):
        pass
except Exception as e:
    log.exception(f"Failed to access HID device '{args.hid}'")
    exit(1)

# === MAVLINK CONNECTION ===
log.info(f"Connecting to MAVLink on {args.serial} @ {args.baud} baud...")
try:
    master = mavutil.mavlink_connection(args.serial, baud=args.baud)
    master.wait_heartbeat(timeout=10)
    log.info(f"Connected. Heartbeat from sys {master.target_system}, comp {master.target_component}")
except Exception as e:
    log.exception("MAVLink connection failed.")
    exit(1)

# === HANDLE SHUTDOWN ===
def handle_shutdown(signum, frame):
    log.info("Received shutdown signal. Exiting.")
    exit(0)

signal.signal(signal.SIGINT, handle_shutdown)
signal.signal(signal.SIGTERM, handle_shutdown)

# === AXIS STATE ===
axis_state = {
    'ABS_X': 0,   # Roll
    'ABS_Y': 0,   # Pitch
    'ABS_Z': 0,   # Yaw
    'ABS_RZ': 255 # Throttle (inverted)
}
buttons_state = 0  # Bitfield

# === SCALE INPUTS ===
def scale_axis(value, invert=False):
    norm = max(0, min(255, value))
    scaled = int((norm - 128) * 7.8125)  # maps to approx -1000 to 1000
    return -scaled if invert else scaled

def scale_throttle(value):
    norm = max(0, min(255, value))
    return int((norm / 255) * 1000)

# === MAIN LOOP ===
log.info("Transmitting MANUAL_CONTROL messages...")
while True:
    try:
        events = get_gamepad()
        for e in events:
            if e.ev_type == "Absolute":
                axis_state[e.code] = e.state
            elif e.ev_type == "Key":
                bit = 1 << (e.code[-1] if e.code[-1].isdigit() else 0)
                if e.state:
                    buttons_state |= bit
                else:
                    buttons_state &= ~bit

        x = scale_axis(axis_state.get('ABS_Y', 128), invert=True)   # pitch
        y = scale_axis(axis_state.get('ABS_X', 128))                # roll
        r = scale_axis(axis_state.get('ABS_Z', 128))                # yaw
        z = scale_throttle(axis_state.get('ABS_RZ', 255))           # throttle

        master.mav.manual_control_send(
            master.target_system,
            x, y, z, r,
            buttons_state
        )

        log.debug(f"manual_control: pitch={x}, roll={y}, yaw={r}, throttle={z}, buttons={buttons_state:#04x}")
        time.sleep(0.1)

    except Exception:
        log.exception("Error in joystick or MAVLink loop")
        time.sleep(1)
