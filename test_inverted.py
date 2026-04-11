#!/usr/bin/env python3
import RPi.GPIO as GPIO
import time

GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)

PUL_PIN = 6
DIR_PIN = 5

# Try starting LOW instead of HIGH
GPIO.setup(PUL_PIN, GPIO.OUT, initial=GPIO.LOW)
GPIO.setup(DIR_PIN, GPIO.OUT, initial=GPIO.LOW)

print("Pulsing with inverted logic (starting LOW)...")
for i in range(100):
    GPIO.output(PUL_PIN, GPIO.HIGH)
    time.sleep(0.001)
    GPIO.output(PUL_PIN, GPIO.LOW)
    time.sleep(0.001)
    if i % 10 == 0:
        print("Pulse {}".format(i+1))

GPIO.cleanup()
print("Test complete - did LEDs flicker?")
