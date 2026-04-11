#!/usr/bin/env python3
import RPi.GPIO as GPIO
import time

GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)

PUL_PIN = 6
DIR_PIN = 5
ENA_PIN = 4

GPIO.setup(PUL_PIN, GPIO.OUT, initial=GPIO.HIGH)
GPIO.setup(DIR_PIN, GPIO.OUT, initial=GPIO.HIGH)
GPIO.setup(ENA_PIN, GPIO.OUT)

# Try ENABLE = HIGH instead of LOW
GPIO.output(ENA_PIN, GPIO.HIGH)

print("Testing with ENA pin HIGH...")
for i in range(100):
    GPIO.output(PUL_PIN, GPIO.LOW)
    time.sleep(0.001)
    GPIO.output(PUL_PIN, GPIO.HIGH)
    time.sleep(0.001)

GPIO.cleanup()
print("Did it flicker?")
