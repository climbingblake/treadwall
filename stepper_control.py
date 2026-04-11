#!/usr/bin/env python3
"""
Stepper motor control script - called from Sinatra
Usage: stepper_control.py <target_position> <current_position> [bypass_limits]
Optional bypass_limits: set to 'true' to disable min/max clamping (DANGER!)
"""

import sys
import json
import os
import RPi.GPIO as GPIO
import time

# Load configuration from config.json
config_path = os.path.join(os.path.dirname(__file__), 'config.json')
with open(config_path, 'r') as f:
    CONFIG = json.load(f)

# GPIO pins from config
DIR_PIN = CONFIG['gpio']['stepper_dir_pin']
PUL_PIN = CONFIG['gpio']['stepper_pul_pin']

# Stepper settings from config
STEP_DELAY = CONFIG['stepper']['step_delay']
MIN_POSITION = CONFIG['stepper']['min_position']
MAX_POSITION = CONFIG['stepper']['max_position']
REVERSE_DIRECTION = CONFIG['stepper'].get('reverse_direction', False)

def step(steps, direction=True, delay=STEP_DELAY):
    """Execute steps in given direction"""
    # Apply direction reversal if configured (for upside-down motor installation)
    if REVERSE_DIRECTION:
        direction = not direction

    # Direction: HIGH for forward, LOW for backward
    GPIO.output(DIR_PIN, GPIO.HIGH if direction else GPIO.LOW)
    time.sleep(0.005)  # 5ms for direction change

    for _ in range(abs(steps)):
        GPIO.output(PUL_PIN, GPIO.LOW)   # active low
        time.sleep(delay)
        GPIO.output(PUL_PIN, GPIO.HIGH)
        time.sleep(delay)

def move_to_position(target, current):
    """Move from current position to target position"""
    steps_to_move = target - current

    if steps_to_move == 0:
        return

    direction = steps_to_move > 0
    steps = abs(steps_to_move)

    step(steps, direction)

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: stepper_control.py <target_position> <current_position> [bypass_limits]")
        sys.exit(1)

    try:
        target_position = int(sys.argv[1])
        current_position = int(sys.argv[2])
        bypass_limits = len(sys.argv) > 3 and sys.argv[3].lower() == 'true'

        # Clamp positions to configured limits (unless bypassing for calibration)
        if not bypass_limits:
            target_position = max(MIN_POSITION, min(MAX_POSITION, target_position))
            current_position = max(MIN_POSITION, min(MAX_POSITION, current_position))

        # Setup GPIO
        GPIO.setwarnings(False)
        GPIO.setmode(GPIO.BCM)
        GPIO.setup(DIR_PIN, GPIO.OUT)
        GPIO.setup(PUL_PIN, GPIO.OUT)
        GPIO.setup(PUL_PIN, GPIO.OUT, initial=GPIO.HIGH)
        GPIO.setup(DIR_PIN, GPIO.OUT, initial=GPIO.HIGH)

        # Move to position
        move_to_position(target_position, current_position)

        # Output new position for Sinatra to read
        print(target_position)

        GPIO.cleanup()
        sys.exit(0)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        GPIO.cleanup()
        sys.exit(1)
