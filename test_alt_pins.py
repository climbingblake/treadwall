#!/usr/bin/env python3
import RPi.GPIO as GPIO
import time

GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)

# Try GPIO 23 and 24 instead
PUL_PIN = 23  # Physical pin 16
DIR_PIN = 24  # Physical pin 18

GPIO.setup(PUL_PIN, GPIO.OUT, initial=GPIO.HIGH)
GPIO.setup(DIR_PIN, GPIO.OUT, initial=GPIO.HIGH)

print("Testing with GPIO 23 (pin 16) and GPIO 24 (pin 18)")
print("TEMPORARILY move your wires:")
print("  PUL+ to Physical pin 16")
print("  DIR+ to Physical pin 18")
print()
input("Press Enter when wires are moved...")

print("Pulsing...")
for i in range(100):
    GPIO.output(PUL_PIN, GPIO.LOW)
    time.sleep(0.001)
    GPIO.output(PUL_PIN, GPIO.HIGH)
    time.sleep(0.001)

GPIO.cleanup()
print("Did it flicker?")
