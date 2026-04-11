#!/usr/bin/env python3
"""Test to verify GPIO 5 and 6 are outputting voltage"""
import RPi.GPIO as GPIO
import time

GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)

PUL_PIN = 6  # Physical pin 31
DIR_PIN = 5  # Physical pin 29

GPIO.setup(PUL_PIN, GPIO.OUT)
GPIO.setup(DIR_PIN, GPIO.OUT)

print("=" * 50)
print("GPIO VOLTAGE TEST")
print("=" * 50)
print()
print("With a multimeter or LED:")
print("  - Test between Physical pin 31 and GND")
print("  - Test between Physical pin 29 and GND")
print()

print("Setting GPIO 6 (pin 31) HIGH for 5 seconds...")
GPIO.output(PUL_PIN, GPIO.HIGH)
print("  -> Should read ~3.3V")
time.sleep(5)

print("Setting GPIO 6 (pin 31) LOW for 5 seconds...")
GPIO.output(PUL_PIN, GPIO.LOW)
print("  -> Should read ~0V")
time.sleep(5)

print()
print("Setting GPIO 5 (pin 29) HIGH for 5 seconds...")
GPIO.output(DIR_PIN, GPIO.HIGH)
print("  -> Should read ~3.3V")
time.sleep(5)

print("Setting GPIO 5 (pin 29) LOW for 5 seconds...")
GPIO.output(DIR_PIN, GPIO.LOW)
print("  -> Should read ~0V")
time.sleep(5)

print()
print("Now rapid pulsing on pin 31 for 10 seconds...")
print("(Should see voltage fluctuate or LED blink rapidly)")
for i in range(5000):
    GPIO.output(PUL_PIN, GPIO.HIGH)
    time.sleep(0.001)
    GPIO.output(PUL_PIN, GPIO.LOW)
    time.sleep(0.001)

GPIO.cleanup()
print()
print("Test complete!")
print("Did you see voltage changes? If NO, those GPIO pins are broken.")
