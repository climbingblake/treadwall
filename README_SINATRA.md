# Motor Control - Sinatra + ERB

A Raspberry Pi motor control application using Sinatra (Ruby) and ERB templates to control both servo and stepper motors.

## Features

- **Servo Motor Control**: PWM-based angle control (0-180°)
- **Stepper Motor Control**: Position-based control (0-6400 steps)
- Side-by-side A/B testing interface
- Real-time status updates
- Vanilla JavaScript (no npm/build process required)

## Requirements

- Ruby 2.7 or higher
- Raspberry Pi with GPIO access
- Bundler gem

## GPIO Connections

### Servo Motor
- GPIO 4 (BCM mode, physical pin 7)

### Stepper Motor
- DIR Pin: GPIO 5 (BCM mode)
- PUL Pin: GPIO 6 (BCM mode)

## Installation

1. Install dependencies:
```bash
bundle install
```

## Running the Application

### Option 1: Using Ruby directly
```bash
ruby motor_control_app.rb
```

### Option 2: Using Rackup (recommended)
```bash
rackup config.ru -p 4567 -o 0.0.0.0
```

### Option 3: Using Puma directly
```bash
bundle exec puma -p 4567
```

The application will be available at:
- **Local**: http://localhost:4567
- **Network**: http://<raspberry-pi-ip>:4567

## API Endpoints

### Servo Endpoints
- `GET /api/servo/status` - Get current servo status
- `GET /api/servo/:angle` - Set servo to angle (0-180)
- `GET /api/servo/increment` - Increment servo angle
- `GET /api/servo/decrement` - Decrement servo angle
- `GET /api/servo/settings/increment/:value` - Set increment value

### Stepper Endpoints
- `GET /api/stepper/status` - Get current stepper status
- `GET /api/stepper/:position` - Set stepper to position (0-6400)
- `GET /api/stepper/increment` - Increment stepper position
- `GET /api/stepper/decrement` - Decrement stepper position
- `GET /api/stepper/settings/increment/:value` - Set increment value

## Testing API Endpoints

```bash
# Servo
curl http://localhost:4567/api/servo/status
curl http://localhost:4567/api/servo/90

# Stepper
curl http://localhost:4567/api/stepper/status
curl http://localhost:4567/api/stepper/3200
```

## File Structure

```
.
├── motor_control_app.rb    # Main Sinatra application
├── config.ru               # Rack configuration
├── Gemfile                 # Ruby dependencies
├── views/
│   └── index.erb          # Main HTML template
└── public/
    └── app.js             # Vanilla JavaScript
```

## Development Notes

- **No npm/build process**: Just edit ERB and JS files and refresh
- **No React**: Simple vanilla JavaScript with fetch API
- **Auto-reload**: Use `rerun` gem for auto-reload during development:
  ```bash
  gem install rerun
  rerun 'ruby motor_control_app.rb'
  ```

## Differences from Flask Version

1. **Backend**: Flask (Python) → Sinatra (Ruby)
2. **Frontend**: React + TypeScript + Vite → ERB + Vanilla JS
3. **GPIO Library**: RPi.GPIO (Python) → pi_piper (Ruby)
4. **Port**: 5000 → 4567
5. **No build step**: Direct file editing, no compilation needed

## Troubleshooting

### GPIO Permission Issues
Run with sudo if you get GPIO permission errors:
```bash
sudo ruby motor_control_app.rb
```

### Port Already in Use
Change the port in motor_control_app.rb:
```ruby
set :port, 4568  # Use a different port
```
