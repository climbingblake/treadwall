# Stepper Motor Configuration

## Setting Min/Max Positions for Your Lead Screw

The stepper motor is configured for linear motion (lead screw) with adjustable position limits.

### Configuration File

All GPIO pins and motor settings are now centralized in **`config.json`**:

```json
{
  "gpio": {
    "servo_pin": 4,
    "stepper_dir_pin": 5,
    "stepper_pul_pin": 6
  },
  "stepper": {
    "min_position": 0,
    "max_position": 60000,
    "step_delay": 0.0002,
    "step_increment": 2500
  }
}
```

Both `motor_control_app.rb` and `stepper_control.py` read from this shared configuration file.

**Configuration Parameters:**
- `min_position`: Minimum allowed stepper position
- `max_position`: Maximum allowed stepper position
- `step_delay`: Delay between pulses in seconds (0.0002 = 200 microseconds)
- `step_increment`: Default increment value shown in the web interface

### How to Calculate Your Max Position

1. **Measure your lead screw travel distance** (in mm or inches)
2. **Know your stepper specs:**
   - Steps per revolution: 200 (standard 1.8° motor)
   - Microstepping: 4x (from your driver settings)
   - Total steps per revolution: 200 × 4 = 800 steps

3. **Know your lead screw pitch** (e.g., 8mm per revolution)

4. **Calculate steps per mm:**
   ```
   steps_per_mm = 800 / 8 = 100 steps/mm
   ```

5. **Calculate max position:**
   ```
   MAX_POSITION = travel_distance_mm × steps_per_mm

   Example: 100mm travel
   MAX_POSITION = 100 × 100 = 10,000 steps
   ```

### Default Value

Currently set to **60000 steps**, which equals:
- 75 full motor revolutions (at 4x microstepping, 800 steps/rev)
- ~600mm of travel (assuming 8mm pitch lead screw)

### After Changing Values

1. **Edit `config.json`** with your desired values
2. **Restart the service:**
   ```bash
   sudo systemctl restart motor-control
   ```
3. **Test the new limits** in the web interface

The slider, input limits, and preset buttons will automatically update to match your configured values.

### Setting a Non-Zero Minimum

If you need to set a minimum position (e.g., safety limit):

```json
{
  "stepper": {
    "min_position": 500,
    "max_position": 10000,
    "step_delay": 0.0002
  }
}
```

This creates a usable range of 9,500 steps (from position 500 to 10,000).

### Dynamic Preset Buttons

The web interface automatically generates preset buttons from `min_position` to `max_position` based on your increment step. For example:
- **Increment = 2500** (default), Min = 0, Max = 60000 → Generates 25 buttons (0, 2500, 5000, ... 60000)
- **Increment = 1000**, Min = 0, Max = 60000 → Generates 61 buttons (0, 1000, 2000, ... 60000)
- **Increment = 5000**, Min = 0, Max = 60000 → Generates 13 buttons (0, 5000, 10000, ... 60000)

You can change the increment in the web interface and click "Update" to regenerate the preset buttons dynamically.
