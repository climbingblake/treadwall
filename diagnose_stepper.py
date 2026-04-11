#!/usr/bin/env python3
"""Comprehensive stepper driver diagnostic"""
import RPi.GPIO as GPIO
import time

GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)

# From config.json
PUL_PIN = 6  # BCM 6 = Physical pin 31
DIR_PIN = 5  # BCM 5 = Physical pin 29

print("=" * 50)
print("STEPPER DRIVER DIAGNOSTIC")
print("=" * 50)
print("PUL_PIN: GPIO {} (Physical pin 31)".format(PUL_PIN))
print("DIR_PIN: GPIO {} (Physical pin 29)".format(DIR_PIN))
print()
print("Make sure your wiring is:")
print("  - PUL signal to Physical pin 31")
print("  - DIR signal to Physical pin 29")
print("  - Pi GND to Driver GND (CRITICAL!)")
print()

# Setup pins
GPIO.setup(PUL_PIN, GPIO.OUT, initial=GPIO.HIGH)
GPIO.setup(DIR_PIN, GPIO.OUT, initial=GPIO.HIGH)

print("Test 1: Setting DIR pin HIGH...")
GPIO.output(DIR_PIN, GPIO.HIGH)
time.sleep(1)
print("  Check if DIR LED changed state")
time.sleep(2)

print("\nTest 2: Setting DIR pin LOW...")
GPIO.output(DIR_PIN, GPIO.LOW)
time.sleep(1)
print("  Check if DIR LED changed state")
time.sleep(2)

print("\nTest 3: Pulsing PUL pin slowly (10 pulses, visible)...")
for i in range(10):
    GPIO.output(PUL_PIN, GPIO.LOW)
    time.sleep(0.1)
    GPIO.output(PUL_PIN, GPIO.HIGH)
    time.sleep(0.1)
    print("  Pulse {}/10 - watch for LED flicker".format(i+1))

time.sleep(1)

print("\nTest 4: Fast pulses (200 pulses - should see rapid flicker)...")
for i in range(200):
    GPIO.output(PUL_PIN, GPIO.LOW)
    time.sleep(0.001)
    GPIO.output(PUL_PIN, GPIO.HIGH)
    time.sleep(0.001)

print("\nTest 5: Trying with Enable pin on GPIO 4...")
ENA_PIN = 4
GPIO.setup(ENA_PIN, GPIO.OUT)
GPIO.output(ENA_PIN, GPIO.LOW)  # Enable active LOW
print("  Enable pin set LOW")
time.sleep(0.5)

print("  Pulsing with enable active...")
for i in range(100):
    GPIO.output(PUL_PIN, GPIO.LOW)
    time.sleep(0.001)
    GPIO.output(PUL_PIN, GPIO.HIGH)
    time.sleep(0.001)

GPIO.cleanup()

print("\n" + "=" * 50)
print("DIAGNOSTIC COMPLETE")
print("=" * 50)
print("\nDid you see:")
print("  1. DIR LED change in Tests 1-2? (YES/NO)")
print("  2. PUL LED flicker in Tests 3-4? (YES/NO)")
print("  3. Any change in Test 5 with enable? (YES/NO)")
print("\nIf all NO:")
print("  - Check physical pin connections")
print("  - VERIFY common ground wire from Pi to Driver")
print("  - Check driver power supply is ON")
