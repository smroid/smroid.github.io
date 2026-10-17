#!/usr/bin/env python3
# Copyright (c) 2026 Steven Rosenthal smr@dt3.org
# See LICENSE file in root directory for license terms.

"""
Camera detection script for the Radxa ZERO 3 (Armbian).
Save as /usr/local/bin/detect-camera.py and make executable.

Tries each candidate camera device tree overlay in turn, rebooting to apply
it (U-Boot applies the overlays named in /boot/armbianEnv.txt), until a camera
streams at the frame rate its sensor's timing implies. The state machine is
that of the Raspberry Pi's detect-camera.py.
"""

import os
import re
import subprocess
import sys
import time
import logging
import fcntl
from pathlib import Path

ARMBIAN_ENV = "/boot/armbianEnv.txt"
STATUS_FILE = "/var/lib/camera-detection-status"
# Overlays tried (and failed) in the current detection round.
TRIED_FILE = "/var/lib/camera-detection-tried"
LOG_FILE = "/var/log/camera-detection.log"
LOCK_FILE = "/var/run/camera-detection.lock"

# Our camera overlays (in /boot/overlay-user) are named with this prefix.
OVERLAY_PREFIX = "hopper-camera-"

# Available overlays to try in order, with the sensor name (the first word of
# its V4L2 sub-device name) each provides.
OVERLAYS = [
    ("hopper-camera-imx462-37m", "imx462"),
    ("hopper-camera-imx462-74m", "imx462"),
]

# The camera interface's raw capture node for the sensor.
VIDEO_NODE_NAME = "stream_cif_mipi_id0"

# How long to wait at boot for the sensor's driver (a module) to probe.
SENSOR_WAIT_SECONDS = 40

# Frames to capture, and the allowed deviation of their rate from the rate
# the sensor's timing implies (a wrong oscillator frequency changes it).
TEST_FRAMES = 60
FPS_TOLERANCE = 0.1
# Allowance for starting the capture, on top of the streaming time.
CAPTURE_START_SECONDS = 10

# Setup logging.
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format='%(asctime)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

def log(message):
    """Log a message"""
    logging.info(message)
    print(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {message}")

def find_v4l2_node(predicate):
    """The /dev path of the first V4L2 device whose name satisfies
    `predicate`, with that name; or (None, None)."""
    for entry in sorted(Path("/sys/class/video4linux").glob("*")):
        try:
            name = (entry / "name").read_text().strip()
        except OSError:
            continue
        if predicate(name):
            return f"/dev/{entry.name}", name
    return None, None

def is_candidate_sensor(name):
    return name.split(" ")[0] in {sensor for _, sensor in OVERLAYS}

def v4l2_ctl(args, timeout=10):
    """v4l2-ctl's output; stderr is included, as it reports some results
    (e.g. --verbose streaming's per-frame lines) there."""
    result = subprocess.run(["v4l2-ctl"] + args, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True,
                            timeout=timeout)
    return result.stdout

def reset_blanking(sensor_node):
    """Set the sensor's blanking controls to their defaults (the mode's
    minimum blanking), as they are when its driver loads; a previous session
    may have lengthened the frame, e.g. for a long exposure."""
    defaults = {}
    output = v4l2_ctl(["-d", sensor_node, "--list-ctrls"])
    for match in re.finditer(
            r"^\s*(horizontal_blanking|vertical_blanking)\s.*\bdefault=(-?\d+)",
            output, re.MULTILINE):
        defaults[match.group(1)] = int(match.group(2))
    if defaults:
        v4l2_ctl(["-d", sensor_node, "--set-ctrl",
                  ",".join(f"{name}={value}"
                           for name, value in defaults.items())])

def expected_fps(sensor_node):
    """The frame rate implied by the sensor's current mode and timing
    controls."""
    controls = {}
    output = v4l2_ctl(["-d", sensor_node, "--get-ctrl",
                       "pixel_rate,horizontal_blanking,vertical_blanking"])
    # The output also has lines such as "VIDIOC_SUBDEV_S_CLIENT_CAP: failed:
    # Inappropriate ioctl for device" (from v4l2-ctl's setup).
    for match in re.finditer(r"^(\w+): (-?\d+)$", output, re.MULTILINE):
        controls[match.group(1)] = int(match.group(2))
    match = re.search(r"Width/Height\s*:\s*(\d+)/(\d+)",
                      v4l2_ctl(["-d", sensor_node, "--get-subdev-fmt", "0"]))
    width, height = int(match.group(1)), int(match.group(2))
    frame_pixels = ((width + controls["horizontal_blanking"]) *
                    (height + controls["vertical_blanking"]))
    return controls["pixel_rate"] / frame_pixels

def check_camera():
    """Check if camera can actually capture images at the expected rate"""
    try:
        # The sensor's driver is a module, loaded some time into boot.
        deadline = time.monotonic() + SENSOR_WAIT_SECONDS
        sensor_node, sensor_name = find_v4l2_node(is_candidate_sensor)
        while sensor_node is None and time.monotonic() < deadline:
            time.sleep(1)
            sensor_node, sensor_name = find_v4l2_node(is_candidate_sensor)
        if sensor_node is None:
            log("No camera sensor detected")
            return False
        log(f"Sensor {sensor_name} at {sensor_node}")

        video_node, _ = find_v4l2_node(lambda name: name == VIDEO_NODE_NAME)
        if video_node is None:
            log(f"No {VIDEO_NODE_NAME} capture node")
            return False

        reset_blanking(sensor_node)
        expected = expected_fps(sensor_node)
        log(f"Testing capture from {video_node}, expecting {expected:.2f} fps")
        # Allow twice the expected streaming time, plus time to start.
        timeout = 2 * TEST_FRAMES / expected + CAPTURE_START_SECONDS
        try:
            output = v4l2_ctl(["-d", video_node, "--stream-mmap=4",
                               f"--stream-count={TEST_FRAMES}",
                               "--stream-to=/dev/null", "--verbose"],
                              timeout=timeout)
        except subprocess.TimeoutExpired:
            log("Image capture timed out")
            return False

        frames = output.count("cap dqbuf:")
        rates = re.findall(r"fps: ([\d.]+)", output)
        if frames < TEST_FRAMES or not rates:
            log(f"Captured only {frames} of {TEST_FRAMES} frames")
            return False
        measured = float(rates[-1])
        if abs(measured - expected) > FPS_TOLERANCE * expected:
            log(f"Captured at {measured:.2f} fps instead of {expected:.2f} "
                "(wrong clock frequency?)")
            return False
        log(f"Image capture successful ({frames} frames at {measured:.2f} fps)")
        return True

    except subprocess.TimeoutExpired:
        log("Camera detection timed out")
        return False
    except Exception as e:
        log(f"Camera detection failed: {e}")
        return False

def set_camera_overlay(overlay):
    """Replace our camera overlay in armbianEnv.txt's user_overlays with
    `overlay`, or remove it if None"""
    with open(ARMBIAN_ENV, 'r') as f:
        lines = f.read().splitlines()

    for i, line in enumerate(lines):
        if line.startswith("user_overlays="):
            names = [n for n in line[len("user_overlays="):].split()
                     if not n.startswith(OVERLAY_PREFIX)]
            break
    else:
        i, names = len(lines), []
        lines.append("")
    if overlay is not None:
        names.append(overlay)
    lines[i] = f"user_overlays={' '.join(names)}"

    with open(ARMBIAN_ENV, 'w') as f:
        f.write('\n'.join(lines) + '\n')

def current_camera_overlay():
    """Our camera overlay selected in armbianEnv.txt's user_overlays, or
    None"""
    with open(ARMBIAN_ENV, 'r') as f:
        for line in f:
            if line.startswith("user_overlays="):
                for name in line[len("user_overlays="):].split():
                    if name.startswith(OVERLAY_PREFIX):
                        return name
    return None

def get_tried():
    """Overlays tried (and failed) in the current detection round"""
    try:
        with open(TRIED_FILE, 'r') as f:
            return f.read().split()
    except FileNotFoundError:
        return []

def clear_tried():
    try:
        Path(TRIED_FILE).unlink()
    except FileNotFoundError:
        pass

def mark_success():
    with open(STATUS_FILE, 'w') as f:
        f.write("success\n")
    clear_tried()

def try_next_overlay(failed):
    """Record overlay `failed` (or None) as tried, then select the first
    overlay not yet tried and reboot; if all have been tried, remove our
    overlay and reboot"""
    tried = get_tried()
    if failed is not None and failed not in tried:
        tried.append(failed)
    with open(TRIED_FILE, 'w') as f:
        f.write(' '.join(tried) + '\n')

    for index, (overlay, _) in enumerate(OVERLAYS):
        if overlay not in tried:
            log(f"Trying overlay {overlay} (index {index})")
            add_overlay(index)
            return
    log("All overlays failed")
    remove_overlay()

def remove_all_overlays():
    """Remove our camera overlays from armbianEnv.txt"""
    try:
        set_camera_overlay(None)
    except Exception as e:
        log(f"Error removing overlays: {e}")

def add_overlay(overlay_index):
    """Select overlay in armbianEnv.txt and reboot"""
    overlay = OVERLAYS[overlay_index][0]
    log(f"Selecting {overlay} in {ARMBIAN_ENV}")

    try:
        set_camera_overlay(overlay)

        # Write status.
        with open(STATUS_FILE, 'w') as f:
            f.write(f"added_overlay_{overlay_index}\n")

        log("Overlay selected, rebooting...")
        subprocess.run(["/sbin/reboot"])

    except Exception as e:
        log(f"Error adding overlay: {e}")
        sys.exit(1)

def remove_overlay():
    """Remove overlay and reboot"""
    log(f"Removing all camera overlays from {ARMBIAN_ENV}")
    remove_all_overlays()

    with open(STATUS_FILE, 'w') as f:
        f.write("removed_overlay\n")

    log("Overlay removed, rebooting...")
    subprocess.run(["/sbin/reboot"])

def get_status():
    """Get current status from file"""
    try:
        if Path(STATUS_FILE).exists():
            with open(STATUS_FILE, 'r') as f:
                return f.read().strip()
        return "FILE_NOT_EXISTS"
    except Exception as e:
        log(f"Error reading status file: {e}")
        return "ERROR"

def main():
    log(f"Starting camera detection process (PID: {os.getpid()})")

    # File locking to prevent multiple instances.
    try:
        lock_fd = open(LOCK_FILE, 'w')
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (IOError, OSError):
        log("Another instance is already running, exiting")
        sys.exit(0)

    # Get initial status.
    status = get_status()
    log(f"Current status: {status}")

    if status == "FILE_NOT_EXISTS":
        log("First run - checking for camera with the image's settings")
        clear_tried()
        if check_camera():
            log("Camera detected with the image's settings")
            mark_success()
            sys.exit(0)
        else:
            log("No camera detected with the image's settings")
            try_next_overlay(current_camera_overlay())

    elif status.startswith("added_overlay_"):
        try:
            overlay_index = int(status.split("_")[-1])
            overlay = OVERLAYS[overlay_index][0]
            log(f"Testing overlay: {overlay}")

            if check_camera():
                log(f"Camera working with overlay: {overlay}")
                mark_success()
                sys.exit(0)
            else:
                log(f"Camera not working with overlay: {overlay}")
                try_next_overlay(overlay)

        except (ValueError, IndexError) as e:
            log(f"Invalid overlay index in status: {status}")
            with open(STATUS_FILE, 'w') as f:
                f.write("failed\n")
            sys.exit(1)

    elif status == "removed_overlay":
        log("Final run - camera could not be detected with any configuration")
        with open(STATUS_FILE, 'w') as f:
            f.write("failed\n")
        sys.exit(1)

    elif status == "success":
        log("Previous camera detection succeeded - verifying current camera still works")
        if check_camera():
            log("Camera still working with current configuration")
            sys.exit(0)
        else:
            log("Previously working camera is no longer detected - camera may have been changed")
            log("Starting fresh detection process")
            try:
                Path(STATUS_FILE).unlink()  # Remove the status file.
            except FileNotFoundError:
                pass  # File already doesn't exist.
            clear_tried()

            # Try every overlay, the selected one included: one failed check
            # may be transient, and must not rule out a working overlay.
            try_next_overlay(None)

    else:
        log(f"Unexpected status: {status}")
        sys.exit(1)

if __name__ == "__main__":
    main()
