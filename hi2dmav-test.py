#!/usr/bin/env python3
import os
import sys
import time
import threading

try:
    import tkinter as tk
    GUI_AVAILABLE = True
except ImportError:
    GUI_AVAILABLE = False

from inputs import get_gamepad

REFRESH_INTERVAL = 0.1  # 10 Hz


# === GUI Mode ===
class HID2MAVTestGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("HID2MAV - Joystick Monitor")
        self.labels = {}
        self.lock = threading.Lock()

        tk.Label(root, text="Live Joystick Input", font=("Arial", 14, "bold")).pack(pady=5)

        self.label_frame = tk.Frame(root, padx=10, pady=5)
        self.label_frame.pack(fill="both", expand=True)

        self.running = True
        self.thread = threading.Thread(target=self.read_loop, daemon=True)
        self.thread.start()

    def update_label(self, key, value):
        with self.lock:
            if key not in self.labels:
                label = tk.Label(self.label_frame, text=f"{key}: {value}", font=("Courier", 12), anchor='w')
                label.pack(fill="x", pady=1)
                self.labels[key] = label
            else:
                self.labels[key].config(text=f"{key}: {value}")

    def read_loop(self):
        while self.running:
            try:
                events = get_gamepad()
                for e in events:
                    key = f"{e.ev_type} {e.code}"
                    self.update_label(key, e.state)
            except Exception as e:
                print(f"[ERROR] {e}", file=sys.stderr)
                time.sleep(1)
            time.sleep(REFRESH_INTERVAL)

    def stop(self):
        self.running = False


# === Console Mode ===
def console_loop():
    print("=== HID2MAV Joystick Console Monitor ===")
    print("[INFO] GUI not available. Falling back to terminal mode.")
    print("[INFO] Press Ctrl+C to exit.")
    try:
        while True:
            events = get_gamepad()
            for e in events:
                print(f"{e.ev_type:<8} {e.code:<16} {e.state}")
            time.sleep(REFRESH_INTERVAL)
    except KeyboardInterrupt:
        print("\n[INFO] Exiting console mode.")
    except Exception as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        time.sleep(1)


# === Entry Point ===
def main():
    if GUI_AVAILABLE and os.environ.get("DISPLAY"):
        root = tk.Tk()
        app = HID2MAVTestGUI(root)
        try:
            root.mainloop()
        finally:
            app.stop()
    else:
        console_loop()


if __name__ == "__main__":
    main()
