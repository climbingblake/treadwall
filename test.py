import RPi.GPIO as GPIO; 
import time; 
GPIO.setmode(GPIO.BCM); 
GPIO.setup(17, GPIO.OUT);
GPIO.output(17, GPIO.HIGH); 
time.sleep(1); 
GPIO.output(17, GPIO.LOW); 
GPIO.cleanup(); 
print('GPIO test complete');