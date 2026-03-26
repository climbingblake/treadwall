# CRIMP - Climbing Routine Interactive Motor Platform

A Ruby-based web application for controlling stepper motors on Raspberry Pi, designed for automated climbing wall systems.

## Features

- **Manual Control**: Precise stepper motor positioning with real-time feedback
- **Training Routines**: Automated interval training programs
- **Position Persistence**: Saves motor position across crashes/reboots
- **Dual-Mode WiFi**: Acts as both an access point and connects to home network
- **Remote Updates**: Web-based system updates with automatic rollback
- **Calibration Tools**: Bypass safety limits for initial setup

## Hardware Requirements

- Raspberry Pi Zero 2 W (or any Raspberry Pi with GPIO)
- Stepper motor driver (compatible with DIR/PUL interface)
- Stepper motor
- Power supply for motor driver

## Software Requirements

- Raspberry Pi OS Lite (64-bit) - Recommended
- Ruby 2.7+
- Python 3.7+
- RPi.GPIO library

## Quick Start

### 1. Initial Setup on Raspberry Pi

```bash
# Install dependencies
sudo apt update
sudo apt install ruby python3 python3-pip git

# Install RPi.GPIO
# try this first
sudo pip3 install RPi.GPIO
# or this if above fails
sudo apt install python3-rpi.gpio

# Install Bundler (required for managing Ruby gems)
sudo gem install bundler --no-doc

# Clone repository
cd /home/pi
git clone https://github.com/climbingblake/treadwall
cd treadwall

# Install Ruby gems from vendored bundle
bundle install --local

# Create device-specific config
cp config/config.example.json config.json
nano config.json  # Edit device_id and other settings
```

### 2. Set Up Systemd Service

# copy `/etc/systemd/system/crimp-app.service`:

```bash
sudo cp config/crimp-app.service.example /etc/systemd/system/crimp-app.service
sudo systemctl enable crimp-app.service
sudo systemctl start crimp-app.service
sudo journalctl -u crimp-app.service -n 50
```

### 3. Access the Interface

**Via Access Point:**
- Connect to WiFi: `TreadWall-Control` (or configured SSID)
- Open browser: `http://192.168.50.1:4567`

**Via Home Network:**
- Open browser: `http://treadwall-001.local:4567` (or device hostname)

## Configuration

Edit `config.json` to customize:

- `device_id`: Unique identifier for this device
- `gpio`: GPIO pin assignments (BCM mode)
- `stepper`: Motor parameters (min/max position, speed, increment)
- `network`: WiFi AP settings

**Important:** Never commit `config.json` to git - it's device-specific and gitignored.

## Updating the System

### Via Web Interface (Recommended)

1. Navigate to the stepper control view
2. Scroll to "System" section
3. Click "Check for Updates"
4. If updates available, click "Update Available - Click to Install"
5. Confirm and wait for automatic restart

### Via SSH

```bash
ssh pi@treadwall-001.local
cd /home/pi/treadwall
./scripts/update.sh
```

### Update Process

The update script:
1. Creates automatic backup
2. Pulls latest code from `main` branch
3. Restarts the service
4. Performs health check
5. Rolls back automatically if update fails

## Multi-Device Deployment

See [DEVICES.md](DEVICES.md) for:
- Device inventory tracking
- Setup checklist
- Maintenance procedures
- Bulk deployment strategies

## API Documentation

Access API documentation: `http://<device-ip>:4567/api/status`

### Key Endpoints

**Stepper Control:**
- `GET /api/stepper/status` - Current position and settings
- `GET /api/stepper/<position>` - Move to position
- `GET /api/stepper/increment` - Increment position
- `GET /api/stepper/decrement` - Decrement position
- `POST /api/stepper/reset` - Reset position to zero (calibration)
- `POST /api/stepper/calibrate/increment` - Move +1000 (bypasses limits)
- `POST /api/stepper/calibrate/decrement` - Move -1000 (bypasses limits)

**Routines:**
- `GET /api/routines` - List all routines
- `POST /api/routines/<id>/start` - Start routine
- `POST /api/routines/stop` - Emergency stop
- `POST /api/routines/pause` - Pause routine
- `POST /api/routines/resume` - Resume routine

**System:**
- `GET /api/system/info` - Version and device info
- `POST /api/system/update` - Trigger system update
- `GET /api/system/update-log` - View update log

## Development Workflow

```
1. Develop locally or on test device
2. Commit to dev branch
3. Test on staging device
4. Merge to main branch
5. Deploy to production devices
```

## Troubleshooting

### Service won't start
```bash
sudo systemctl status crimp-app.service
sudo journalctl -u crimp-app.service -n 50
```

### Motor not moving
- Check GPIO connections (BCM pins 5 and 6 by default)
- Verify motor driver is powered
- Check permissions: `sudo usermod -a -G gpio pi`

### Update failed
```bash
# View update log
cat /home/pi/treadwall-update.log

# Manual rollback
cd /home/pi
sudo systemctl stop crimp-app.service
rm -rf treadwall
mv treadwall-backup-YYYYMMDD-HHMMSS treadwall
sudo systemctl start crimp-app.service
```

### Can't connect to AP
- Check WiFi configuration in `/etc/hostapd/hostapd.conf`
- Verify services: `sudo systemctl status hostapd dnsmasq`
- Check virtual interface: `ip addr show wlan0_ap`

## Safety Notes

⚠️ **Calibration buttons bypass safety limits** - Use only during initial setup
⚠️ **Emergency stop** always returns to MIN_POSITION
⚠️ **Position persistence** saves state every movement to prevent loss

## License

[Your License Here]

## Contributing

[Your Contributing Guidelines Here]
