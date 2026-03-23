# Installation Guide for Raspberry Pi

Complete setup guide for the Motor Control web application on Raspberry Pi.

---

## Step 1: Install Ruby and Build Tools

```bash
# Update package lists
sudo apt-get update

# Install Ruby, Bundler, and build essentials
sudo apt-get install -y ruby-full build-essential libssl-dev

# Install Bundler gem manager
sudo gem install bundler

# Verify installations
ruby -v
bundle -v
```

---

## Step 2: Install Python GPIO Library

The stepper motor uses Python for precise timing:

```bash
# Install Python GPIO library
sudo apt-get install -y python3-rpi.gpio

# Verify Python is available
python3 --version
```

---

## Step 3: Install Pigpio for Servo Control

Pigpio provides hardware-accelerated PWM for the servo motor:

```bash
# Install pigpio daemon
sudo apt-get install -y pigpio

# Enable pigpiod to start on boot
sudo systemctl enable pigpiod

# Start pigpiod now
sudo systemctl start pigpiod

# Verify it's running (should show "active (running)")
sudo systemctl status pigpiod
```

Expected output:
```
● pigpiod.service - Pigpio daemon
     Loaded: loaded
     Active: active (running)
```

Press `q` to exit the status view.

---

## Step 4: Transfer Files to Raspberry Pi

Copy these files from your Mac to `~/Desktop/treadwall/` on your Pi:

**Core application files:**
- `motor_control_app.rb` - Main Sinatra app
- `stepper_control.py` - Python stepper motor driver
- `servo_control.rb` - Servo control class
- `config.ru` - Rack configuration
- `Gemfile` - Ruby dependencies
- `config.json` - Shared configuration (GPIO pins, position limits)

**Frontend files:**
- `views/index.erb` - HTML template
- `public/app.js` - JavaScript

**Optional documentation:**
- `README_SINATRA.md`
- `STEPPER_CONFIG.md`
- `INSTALL_PI.md` (this file)

---

## Step 5: Install Ruby Gems

Navigate to your project directory and install dependencies:

```bash
# Navigate to project
cd ~/Desktop/treadwall

# Install gems to vendor/bundle (no sudo needed)
bundle install --path vendor/bundle

# Verify gems were installed
ls -la vendor/bundle/ruby/
```

---

## Step 6: Make Python Script Executable

```bash
# Make the stepper control script executable
chmod +x stepper_control.py

# Test the Python script (move to position 1000 from 0)
sudo python3 stepper_control.py 1000 0
```

The stepper motor should move if wired correctly.

---

## Step 7: Test the Application

Run the app manually first to verify everything works:

```bash
# Run the app (Ctrl+C to stop)
sudo bundle exec ruby motor_control_app.rb
```

You should see:
```
✓ Servo: Ruby/pigpio
✓ Stepper: Python script (precise timing)
✓ Servo on GPIO 4 using pigpio PWM
Starting Motor Control Server...
Access the app at http://localhost:4567
```

**Test in your browser:**
- From the Pi: http://localhost:4567
- From another device: http://[your-pi-ip]:4567

Find your Pi's IP:
```bash
hostname -I
```

If everything works, press **Ctrl+C** to stop the server.

---

## Step 8: Set Up Auto-Start with Systemd

Create a systemd service to auto-start the app on boot:

```bash
# Create service file
sudo nano /etc/systemd/system/motor-control.service
```

**Paste this content:**

```ini
[Unit]
Description=Motor Control Web App
After=network.target pigpiod.service

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/Desktop/treadwall
ExecStart=/usr/bin/ruby motor_control_app.rb
Environment="GEM_HOME=/home/pi/Desktop/treadwall/vendor/bundle/ruby/3.1.0"
Environment="GEM_PATH=/home/pi/Desktop/treadwall/vendor/bundle/ruby/3.1.0"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**Save and exit:** Press `Ctrl+X`, then `Y`, then `Enter`

**Enable and start the service:**

```bash
# Reload systemd to recognize new service
sudo systemctl daemon-reload

# Enable auto-start on boot
sudo systemctl enable motor-control

# Start the service now
sudo systemctl start motor-control

# Check status (should show "active (running)")
sudo systemctl status motor-control
```

**View live logs:**
```bash
sudo journalctl -u motor-control -f
```

Press `Ctrl+C` to exit log view.

---

## Step 9: Verify Auto-Start

Reboot your Pi to test auto-start:

```bash
sudo reboot
```

After reboot, check if the service started automatically:

```bash
# Check service status
sudo systemctl status motor-control

# View logs
sudo journalctl -u motor-control -n 50
```

The web interface should be accessible immediately after boot!

---

## Useful Commands

### Service Management
```bash
# Start the service
sudo systemctl start motor-control

# Stop the service
sudo systemctl stop motor-control

# Restart the service
sudo systemctl restart motor-control

# View status
sudo systemctl status motor-control

# View logs (live)
sudo journalctl -u motor-control -f

# View last 50 log lines
sudo journalctl -u motor-control -n 50

# Disable auto-start
sudo systemctl disable motor-control
```

### Manual Testing
```bash
# Run manually (for debugging)
cd ~/Desktop/treadwall
sudo bundle exec ruby motor_control_app.rb

# Test Python stepper script directly
sudo python3 stepper_control.py 3200 0

# Check pigpio status
sudo systemctl status pigpiod
```

---

## GPIO Pin Configuration

**Servo Motor:**
- Pin: GPIO 4 (BCM mode)
- PWM: 50Hz via pigpio
- Range: 0-180°

**Stepper Motor:**
- DIR Pin: GPIO 5 (BCM mode)
- PUL Pin: GPIO 6 (BCM mode)
- Python script for precise timing

---

## Configuring Stepper Motor Range

To adjust the stepper motor position limits for your lead screw:

1. **Edit `config.json`:**
   ```json
   {
     "stepper": {
       "min_position": 0,
       "max_position": 60000,
       "step_delay": 0.0002
     }
   }
   ```

2. **Restart the service:**
   ```bash
   sudo systemctl restart motor-control
   ```

The web interface will automatically generate preset buttons from MIN to MAX based on your increment step.

See `STEPPER_CONFIG.md` for detailed calculation examples.

---

## Troubleshooting

### Service Won't Start
```bash
# Check detailed error logs
sudo journalctl -u motor-control -n 100 --no-pager

# Verify bundle path
ls -la ~/Desktop/treadwall/vendor/bundle/ruby/3.1.0

# Test manually
cd ~/Desktop/treadwall
sudo bundle exec ruby motor_control_app.rb
```

### Servo Not Working
```bash
# Check if pigpiod is running
sudo systemctl status pigpiod

# Restart pigpiod
sudo systemctl restart pigpiod

# Test pigpio
pigs t
```

### Stepper Not Working
```bash
# Test Python script directly
sudo python3 stepper_control.py 1000 0

# Check Python GPIO library
python3 -c "import RPi.GPIO as GPIO; print('GPIO OK')"
```

### Can't Access Web Interface
```bash
# Check if service is running
sudo systemctl status motor-control

# Check what's listening on port 4567
sudo netstat -tlnp | grep 4567

# Check firewall (if enabled)
sudo ufw status
sudo ufw allow 4567
```

### GPIO Permission Errors
The app must run with `sudo` for GPIO access. The systemd service handles this automatically.

---

## File Structure

```
~/Desktop/treadwall/
├── motor_control_app.rb      # Main Sinatra app
├── stepper_control.py         # Python stepper driver
├── servo_control.rb           # Servo control class
├── config.ru                  # Rack configuration
├── config.json                # Shared configuration (GPIO, limits)
├── Gemfile                    # Ruby dependencies
├── Gemfile.lock              # Locked gem versions
├── views/
│   └── index.erb             # HTML template
├── public/
│   └── app.js                # Frontend JavaScript
└── vendor/
    └── bundle/               # Ruby gems (installed locally)
```

---

## Success Checklist

✅ Ruby and Bundler installed
✅ Python GPIO library installed
✅ Pigpio installed and running
✅ Gems installed to vendor/bundle
✅ Python script executable
✅ App runs manually with `sudo bundle exec ruby motor_control_app.rb`
✅ Web interface accessible in browser
✅ Servo motor responds to commands
✅ Stepper motor responds to commands
✅ Systemd service created and enabled
✅ Service starts automatically after reboot

---

## Need Help?

Check the logs for detailed error messages:
```bash
sudo journalctl -u motor-control -n 100 --no-pager
```

Verify all dependencies are installed:
```bash
ruby -v
bundle -v
python3 -c "import RPi.GPIO"
pigs t
```
