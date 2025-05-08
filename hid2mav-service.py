#!/usr/bin/env python3
import logging
import time
import argparse
import os
import stat
import platform
import getpass
from pymavlink import mavutil
from inputs import get_gamepad

# === LOGGING ===
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
parser = argparse.ArgumentParser(description="Convert joystick input to MAVLink RC overrides")
parser.add_argument("--serial", required=True, help="Serial device (e.g., /dev/ttyS0 or tcp:host:port)")
parser.add_argument("--hid", required=True, help="HID joystick device (e.g., /dev/input/js0)")
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

# === MAVLINK CONNECT ===
log.info(f"Connecting to MAVLink on {args.serial} @ {args.baud} baud...")
try:
    master = mavutil.mavlink_connection(args.serial, baud=args.baud)
    master.wait_heartbeat(timeout=10)
    log.info(f"Connected. Heartbeat from sys {master.target_system}, comp {master.target_component}")
except Exception as e:
    log.exception("MAVLink connection failed.")
    exit(1)

# === RC OVERRIDE ===
def send_throttle(value):
    pwm = max(1000, min(2000, 1500 + int((value - 128) * 4)))
    try:
        master.mav.rc_channels_override_send(
            master.target_system, master.target_component,
            pwm, 0, 0, 0, 0, 0, 0, 0
        )
        log.debug(f"Sent RC override: PWM={pwm}")
    except Exception:
        log.exception("Failed to send RC override")

# === LOOP ===
log.info("Reading joystick input...")
while True:
    try:
        events = get_gamepad()
        for event in events:
            if event.ev_type == "Absolute" and event.code == "ABS_Y":
                send_throttle(event.state)
        time.sleep(0.05)
    except Exception:
        log.exception("Error in HID loop")
        time.sleep(1)
