#!/usr/bin/env python3
import RPi.GPIO as GPIO
import time

GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)

PUL_PIN = 6
DIR_PIN = 5

# Try GPIO 4 as enable pin (common alternative)
ENA_PIN = 4

GPIO.setup(PUL_PIN, GPIO.OUT)
GPIO.setup(DIR_PIN, GPIO.OUT)
GPIO.setup(ENA_PIN, GPIO.OUT)

# Enable the driver (active LOW)
GPIO.output(ENA_PIN, GPIO.LOW)

print('Driver enabled, testing pulses...')

# Pulse 200 times
for i in range(200):
    GPIO.output(PUL_PIN, GPIO.LOW)
    time.sleep(0.001)
    GPIO.output(PUL_PIN, GPIO.HIGH)
    time.sleep(0.001)

GPIO.cleanup()
print('Test complete')
