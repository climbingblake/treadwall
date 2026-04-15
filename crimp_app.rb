#!/usr/bin/env ruby
require 'sinatra'
require 'sinatra/json'
require 'json'

puts "✓ Stepper: Python script (precise timing)"

# Load configuration from config.json
config_file = File.join(File.dirname(__FILE__), 'config.json')
CONFIG = JSON.parse(File.read(config_file))

# Configuration
set :port, 4567
set :bind, '0.0.0.0'  # Allow network access on Raspberry Pi
set :public_folder, File.dirname(__FILE__) + '/public'

# GPIO Configuration - BCM mode (from config.json)
STEPPER_DIR_PIN = CONFIG['gpio']['stepper_dir_pin']
STEPPER_PUL_PIN = CONFIG['gpio']['stepper_pul_pin']

# Stepper motor constants (for lead screw - from config.json)
MIN_POSITION = CONFIG['stepper']['min_position']
MAX_POSITION = CONFIG['stepper']['max_position']

# State file for persistence
STATE_FILE = File.join(File.dirname(__FILE__), 'motor_state.json')

# Global state - Stepper
$stepper_position = 0
$stepper_increment = CONFIG['stepper']['step_increment']

# ========== PERSISTENCE FUNCTIONS ==========

# Save current motor position to file
def save_position
  begin
    state = {
      position: $stepper_position,
      timestamp: Time.now.to_i
    }
    File.write(STATE_FILE, JSON.pretty_generate(state))
    puts "✓ Position saved: #{$stepper_position}"
  rescue => e
    puts "⚠ Warning: Failed to save position: #{e.message}"
  end
end

# Load motor position from file
def load_position
  if File.exist?(STATE_FILE)
    begin
      state = JSON.parse(File.read(STATE_FILE))
      saved_position = state['position'].to_i

      # Clamp to valid range in case config changed
      saved_position = [[saved_position, MIN_POSITION].max, MAX_POSITION].min

      puts "✓ Restored position: #{saved_position}"
      return saved_position
    rescue => e
      puts "⚠ Warning: Failed to load position: #{e.message}"
      return 0
    end
  else
    puts "ℹ No saved position found, starting at 0"
    return 0
  end
end

# Initialize position from saved state
$stepper_position = load_position

# Stepper mutex to prevent concurrent motor commands
$stepper_mutex = Mutex.new

# Global state - Routines
$routine_thread = nil
$routine_mutex = Mutex.new
$routine_state = {
  running: false,
  paused: false,
  routine_id: nil,
  routine_name: nil,
  current_step: 0,
  total_steps: 0,
  step_start_time: nil,
  step_label: nil,
  step_duration: 0,
  step_position: 0,
  repeat_mode: false,
  repeat_count: 0,
  pause_start_time: nil
}

# Load routines from routines.json
def load_routines
  routines_file = File.join(File.dirname(__FILE__), 'routines.json')
  if File.exist?(routines_file)
    data = JSON.parse(File.read(routines_file))
    data['routines'] || []
  else
    puts "⚠ Warning: routines.json not found"
    []
  end
end

$routines = load_routines
puts "✓ Loaded #{$routines.length} training routines"

# ========== NETWORK INTERFACE DETECTION ==========

# Detect current network mode (WiFi client or USB fallback)
def detect_network_mode
  # Check if wlan0 has an IP (connected to WiFi)
  wlan0_ip = `ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}'`.strip
  wlan0_connected = !wlan0_ip.empty?

  # Check if usb0 interface exists and has IP
  usb0_exists = system('ip link show usb0 >/dev/null 2>&1')
  usb0_ip = `ip -4 addr show usb0 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}'`.strip if usb0_exists
  usb0_connected = usb0_exists && !usb0_ip.to_s.empty?

  if wlan0_connected
    {
      mode: 'wifi_client',
      interface: 'wlan0',
      ip: wlan0_ip,
      description: 'WiFi Client Mode'
    }
  elsif usb0_connected
    {
      mode: 'usb_fallback',
      interface: 'usb0',
      ip: usb0_ip,
      description: 'USB Tethering Mode (fallback)'
    }
  else
    {
      mode: 'disconnected',
      interface: nil,
      ip: nil,
      description: 'Not connected (waiting for WiFi or USB)'
    }
  end
end

# Detect configuration at startup
$network_mode = detect_network_mode
puts "✓ Network Mode: #{$network_mode[:description]}"
puts "  - Interface: #{$network_mode[:interface] || 'None'}"
puts "  - IP: #{$network_mode[:ip] || 'None'}"

# ========== STEPPER FUNCTIONS ==========

def set_stepper_position(target_position, bypass_limits: false)
  # Prevent concurrent motor commands (Pi Zero can't handle multiple at once)
  $stepper_mutex.synchronize do
    # Call Python script for precise timing
    script_path = File.join(File.dirname(__FILE__), 'stepper_control.py')

    begin
      # Call Python script with target and current position
      # Optional bypass_limits flag for calibration (DANGER!)
      bypass_arg = bypass_limits ? ' true' : ''
      result = `sudo python3 #{script_path} #{target_position} #{$stepper_position}#{bypass_arg} 2>&1`
      exit_status = $?.exitstatus

      if exit_status == 0
        # Python script returns the new position
        $stepper_position = result.strip.to_i
        save_position  # Persist position after successful movement
        true
      else
        puts "Stepper control error: #{result}"
        false
      end
    rescue => e
      puts "Error calling stepper script: #{e.message}"
      false
    end
  end
end

# ========== ROUTINE FUNCTIONS ==========

# Stop current routine and optionally return to MIN_POSITION
def stop_routine(return_to_safe_position = true)
  $routine_mutex.synchronize do
    $routine_state[:running] = false
    $routine_state[:paused] = false
  end

  # Wait for thread to finish
  if $routine_thread && $routine_thread.alive?
    $routine_thread.join(2) # Wait up to 2 seconds
    $routine_thread.kill if $routine_thread.alive? # Force kill if needed
  end

  # Return to MIN_POSITION for safety
  if return_to_safe_position
    puts "Safety: Returning to MIN_POSITION (#{MIN_POSITION})"
    set_stepper_position(MIN_POSITION)
  end

  # Reset state
  $routine_mutex.synchronize do
    $routine_state[:routine_id] = nil
    $routine_state[:routine_name] = nil
    $routine_state[:current_step] = 0
    $routine_state[:total_steps] = 0
    $routine_state[:step_start_time] = nil
    $routine_state[:pause_start_time] = nil
    $routine_state[:repeat_count] = 0
  end
end

# Execute routine in background thread
def execute_routine(routine)
  $routine_thread = Thread.new do
    begin
      loop_count = 0

      loop do
        # Check if stopped before starting new loop
        break unless $routine_state[:running]

        routine['steps'].each_with_index do |step, index|
          # Check if stopped
          break unless $routine_state[:running]

          # Wait while paused
          sleep 0.1 while $routine_state[:paused] && $routine_state[:running]

          # Check if stopped after pause
          break unless $routine_state[:running]

          # Clamp position to valid range
          target_position = [[step['position'], MIN_POSITION].max, MAX_POSITION].min

          puts "Routine: Step #{index + 1}/#{routine['steps'].length} - #{step['label']} (Position: #{target_position})"

          # Start timer BEFORE movement begins
          $routine_mutex.synchronize do
            $routine_state[:current_step] = index
            $routine_state[:step_start_time] = Time.now  # Timer starts NOW (before movement)
            $routine_state[:step_label] = step['label']
            $routine_state[:step_position] = target_position
            $routine_state[:step_duration] = step['duration']  # Initial duration (will be updated)
          end

          # Measure actual movement time
          move_start_time = Time.now
          success = set_stepper_position(target_position)
          move_duration = (Time.now - move_start_time).to_i

          # Update duration to include actual move time
          $routine_mutex.synchronize do
            $routine_state[:step_duration] = step['duration'] + move_duration  # Add move time
          end

          unless success
            puts "Error: Failed to move to position #{target_position}"
            $routine_mutex.synchronize do
              $routine_state[:running] = false
            end
            break
          end

          # Hold for duration (check every 0.1s for stop/pause)
          duration_elapsed = 0
          while duration_elapsed < step['duration']
            break unless $routine_state[:running]
            sleep 0.1 while $routine_state[:paused] && $routine_state[:running]
            break unless $routine_state[:running]

            sleep 0.1
            duration_elapsed += 0.1
          end
        end

        # Check if should repeat
        if routine['options']['repeat'] && $routine_state[:running]
          $routine_mutex.synchronize do
            $routine_state[:repeat_count] += 1
          end
          loop_count += 1
          puts "Routine: Starting loop #{loop_count + 1}"
        else
          break
        end
      end

      # Return to zero if configured and not manually stopped
      if routine['options']['return_to_zero'] && $routine_state[:running]
        puts "Routine: Returning to zero position"
        set_stepper_position(MIN_POSITION)
      end

    rescue => e
      puts "Routine error: #{e.message}"
      puts e.backtrace
    ensure
      # Clean up state
      $routine_mutex.synchronize do
        $routine_state[:running] = false
        $routine_state[:paused] = false
      end
      puts "Routine: Finished"
    end
  end
end

# ========== ROUTES ==========

# Home page
get '/' do
  erb :index
end

# Configuration page
get '/config' do
  erb :config
end

# API Status endpoint
get '/api/status' do
  json({
    message: 'CRIMP API - Climbing Routine Interactive Motor Platform',
    stepper: {
      current_position: $stepper_position,
      increment: $stepper_increment,
      min_position: MIN_POSITION,
      max_position: MAX_POSITION
    },
    endpoints: {
      stepper: {
        set_position: '/api/stepper/<position>',
        increment: '/api/stepper/increment',
        decrement: '/api/stepper/decrement',
        set_increment: '/api/stepper/settings/increment/<value>',
        set_min_position: 'POST /api/stepper/settings/min-position (body: {value: int})',
        set_max_position: 'POST /api/stepper/settings/max-position (body: {value: int})',
        reset: 'POST /api/stepper/reset',
        calibrate_increment: 'POST /api/stepper/calibrate/increment',
        calibrate_decrement: 'POST /api/stepper/calibrate/decrement',
        status: '/api/stepper/status'
      },
      routines: {
        list: '/api/routines',
        get: '/api/routines/<id>',
        start: '/api/routines/<id>/start',
        stop: '/api/routines/stop',
        pause: '/api/routines/pause',
        resume: '/api/routines/resume',
        status: '/api/routines/status'
      },
      system: {
        info: '/api/system/info',
        update: 'POST /api/system/update',
        update_log: '/api/system/update-log'
      },
      network: {
        status: '/api/network/status',
        configure: 'POST /api/network/configure'
      }
    }
  })
end

# ========== STEPPER ENDPOINTS ==========

get '/api/stepper/status' do
  json({
    current_position: $stepper_position,
    increment: $stepper_increment,
    min_position: MIN_POSITION,
    max_position: MAX_POSITION,
    dir_pin: STEPPER_DIR_PIN,
    pul_pin: STEPPER_PUL_PIN,
    gpio_mode: 'BCM'
  })
end

get '/api/stepper/increment' do
  new_position = [$stepper_position + $stepper_increment, MAX_POSITION].min
  redirect "/api/stepper/#{new_position}"
end

get '/api/stepper/decrement' do
  new_position = [$stepper_position - $stepper_increment, MIN_POSITION].max
  redirect "/api/stepper/#{new_position}"
end

get '/api/stepper/settings/increment/:value' do
  value = params[:value].to_i
  $stepper_increment = [[value, 1].max, MAX_POSITION].min

  json({
    success: true,
    increment: $stepper_increment
  })
end

# Update min position setting
post '/api/stepper/settings/min-position' do
  begin
    # Parse JSON request body
    request.body.rewind
    body = request.body.read
    data = JSON.parse(body)
    value = data['value'].to_i

    # Validate: min must be less than max
    if value >= MAX_POSITION
      status 400
      return json({
        success: false,
        message: "Min position must be less than max position (#{MAX_POSITION})"
      })
    end

    # Update config file
    config_path = File.join(File.dirname(__FILE__), 'config.json')
    config = JSON.parse(File.read(config_path))
    config['stepper']['min_position'] = value
    File.write(config_path, JSON.pretty_generate(config))

    # Update constant (requires restart to fully apply)
    Object.send(:remove_const, :MIN_POSITION)
    Object.const_set(:MIN_POSITION, value)

    json({
      success: true,
      min_position: value,
      message: 'Min position updated. Service restart recommended for full effect.'
    })
  rescue => e
    status 500
    json({
      success: false,
      message: "Failed to update min position: #{e.message}"
    })
  end
end

# Update max position setting
post '/api/stepper/settings/max-position' do
  begin
    # Parse JSON request body
    request.body.rewind
    body = request.body.read
    data = JSON.parse(body)
    value = data['value'].to_i

    # Validate: max must be greater than min
    if value <= MIN_POSITION
      status 400
      return json({
        success: false,
        message: "Max position must be greater than min position (#{MIN_POSITION})"
      })
    end

    # Update config file
    config_path = File.join(File.dirname(__FILE__), 'config.json')
    config = JSON.parse(File.read(config_path))
    config['stepper']['max_position'] = value
    File.write(config_path, JSON.pretty_generate(config))

    # Update constant (requires restart to fully apply)
    Object.send(:remove_const, :MAX_POSITION)
    Object.const_set(:MAX_POSITION, value)

    json({
      success: true,
      max_position: value,
      message: 'Max position updated. Service restart recommended for full effect.'
    })
  rescue => e
    status 500
    json({
      success: false,
      message: "Failed to update max position: #{e.message}"
    })
  end
end

post '/api/stepper/reset' do
  # Reset the saved position to 0 without moving the motor
  # This allows users to calibrate where "zero" is
  $stepper_position = 0
  save_position

  json({
    success: true,
    position: $stepper_position,
    message: 'Position reset to 0 (calibrated)'
  })
end

# DANGER: Unconstrained increment for calibration (bypasses min/max)
post '/api/stepper/calibrate/increment' do
  new_position = $stepper_position + 1000
  success = set_stepper_position(new_position, bypass_limits: true)

  if success
    json({
      success: true,
      position: $stepper_position,
      message: "Calibration: Moved to position #{$stepper_position}"
    })
  else
    status 500
    json({
      success: false,
      position: $stepper_position,
      message: 'Failed to move stepper'
    })
  end
end

# DANGER: Unconstrained decrement for calibration (bypasses min/max)
post '/api/stepper/calibrate/decrement' do
  new_position = $stepper_position - 1000
  success = set_stepper_position(new_position, bypass_limits: true)

  if success
    json({
      success: true,
      position: $stepper_position,
      message: "Calibration: Moved to position #{$stepper_position}"
    })
  else
    status 500
    json({
      success: false,
      position: $stepper_position,
      message: 'Failed to move stepper'
    })
  end
end

# Generic position route - MUST be last to avoid matching specific routes
get '/api/stepper/:position' do
  position = params[:position].to_i

  # Clamp position to configured limits
  position = [[position, MIN_POSITION].max, MAX_POSITION].min

  success = set_stepper_position(position)

  if success
    json({
      success: true,
      position: position,
      message: "Stepper moved to position #{position}"
    })
  else
    status 500
    json({
      success: false,
      position: $stepper_position,
      message: 'Failed to move stepper'
    })
  end
end

# ========== ROUTINE ENDPOINTS ==========

# List all available routines
get '/api/routines' do
  json({
    routines: $routines.map { |r|
      {
        id: r['id'],
        name: r['name'],
        description: r['description'],
        step_count: r['steps'].length,
        total_duration: r['steps'].sum { |s| s['duration'] },
        repeat: r['options']['repeat'],
        return_to_zero: r['options']['return_to_zero']
      }
    }
  })
end

# Get current routine status (MUST be before /:id route)
get '/api/routines/status' do
  state = $routine_mutex.synchronize { $routine_state.dup }

  # Calculate elapsed time for current step
  step_elapsed = 0
  if state[:step_start_time] && state[:running]
    if state[:paused] && state[:pause_start_time]
      # If paused, freeze time at the moment of pause
      step_elapsed = (state[:pause_start_time] - state[:step_start_time]).to_i
    else
      # Normal running - calculate current elapsed time
      step_elapsed = (Time.now - state[:step_start_time]).to_i
    end
  end

  # Calculate progress percentage
  step_progress = 0
  if state[:step_duration] > 0
    step_progress = ((step_elapsed.to_f / state[:step_duration]) * 100).to_i
    step_progress = [step_progress, 100].min
  end

  json({
    running: state[:running],
    paused: state[:paused],
    routine_id: state[:routine_id],
    routine_name: state[:routine_name],
    current_step: state[:current_step],
    total_steps: state[:total_steps],
    step_label: state[:step_label],
    step_elapsed: step_elapsed,
    step_duration: state[:step_duration],
    step_progress: step_progress,
    current_position: state[:step_position],
    repeat_mode: state[:repeat_mode],
    repeat_count: state[:repeat_count]
  })
end

# Get specific routine details
get '/api/routines/:id' do
  routine = $routines.find { |r| r['id'] == params[:id] }

  if routine
    json({
      success: true,
      routine: routine
    })
  else
    status 404
    json({
      success: false,
      message: "Routine not found: #{params[:id]}"
    })
  end
end

# Start a routine
post '/api/routines/:id/start' do
  routine = $routines.find { |r| r['id'] == params[:id] }

  unless routine
    status 404
    return json({
      success: false,
      message: "Routine not found: #{params[:id]}"
    })
  end

  # Check if routine already running
  if $routine_state[:running]
    status 400
    return json({
      success: false,
      message: 'A routine is already running'
    })
  end

  # Initialize routine state
  $routine_mutex.synchronize do
    $routine_state[:running] = true
    $routine_state[:paused] = false
    $routine_state[:routine_id] = routine['id']
    $routine_state[:routine_name] = routine['name']
    $routine_state[:total_steps] = routine['steps'].length
    $routine_state[:current_step] = 0
    $routine_state[:repeat_mode] = routine['options']['repeat']
    $routine_state[:repeat_count] = 0
  end

  # Start execution in background
  execute_routine(routine)

  json({
    success: true,
    message: "Started routine: #{routine['name']}"
  })
end

# Stop current routine (emergency stop - always returns to MIN_POSITION)
post '/api/routines/stop' do
  was_running = $routine_state[:running]

  # Stop routine if running
  if was_running
    stop_routine(true) # true = return to MIN_POSITION for safety
    message = 'Routine stopped, returned to safe position'
  else
    # Even if no routine running, return to MIN_POSITION for safety
    puts "Emergency stop: Returning to MIN_POSITION (#{MIN_POSITION})"
    set_stepper_position(MIN_POSITION)
    message = 'Emergency stop: Returned to safe position'
  end

  json({
    success: true,
    message: message
  })
end

# Pause current routine
post '/api/routines/pause' do
  unless $routine_state[:running]
    status 400
    return json({
      success: false,
      message: 'No routine is running'
    })
  end

  if $routine_state[:paused]
    status 400
    return json({
      success: false,
      message: 'Routine is already paused'
    })
  end

  $routine_mutex.synchronize do
    $routine_state[:paused] = true
    $routine_state[:pause_start_time] = Time.now  # Track when pause started
  end

  json({
    success: true,
    message: 'Routine paused'
  })
end

# Resume paused routine
post '/api/routines/resume' do
  unless $routine_state[:running]
    status 400
    return json({
      success: false,
      message: 'No routine is running'
    })
  end

  unless $routine_state[:paused]
    status 400
    return json({
      success: false,
      message: 'Routine is not paused'
    })
  end

  $routine_mutex.synchronize do
    # Calculate how long we were paused
    if $routine_state[:pause_start_time]
      pause_duration = Time.now - $routine_state[:pause_start_time]

      # Adjust step start time to exclude pause duration (freeze the timer)
      $routine_state[:step_start_time] += pause_duration if $routine_state[:step_start_time]

      $routine_state[:pause_start_time] = nil
    end

    $routine_state[:paused] = false
  end

  json({
    success: true,
    message: 'Routine resumed'
  })
end

# ========== SYSTEM ENDPOINTS ==========

# Get system information
get '/api/system/info' do
  app_dir = File.dirname(__FILE__)

  # Get git version info
  version = `cd #{app_dir} && git rev-parse --short HEAD 2>/dev/null`.strip
  version = 'unknown' if version.empty?

  branch = `cd #{app_dir} && git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
  branch = 'unknown' if branch.empty?

  last_commit = `cd #{app_dir} && git log -1 --format="%ai" 2>/dev/null`.strip
  last_commit = 'unknown' if last_commit.empty?

  # Get system info
  uptime = `uptime -p 2>/dev/null`.strip
  uptime = 'unknown' if uptime.empty?

  # Check if updates are available
  updates_available = false
  begin
    `cd #{app_dir} && git fetch origin 2>/dev/null`
    local = `cd #{app_dir} && git rev-parse HEAD 2>/dev/null`.strip
    remote = `cd #{app_dir} && git rev-parse origin/main 2>/dev/null`.strip
    updates_available = (local != remote && !local.empty? && !remote.empty?)
  rescue
    # Ignore errors
  end

  json({
    device_id: CONFIG['device_id'] || 'unknown',
    version: version,
    branch: branch,
    last_commit: last_commit,
    uptime: uptime,
    updates_available: updates_available,
    stepper_position: $stepper_position
  })
end

# Trigger system update
post '/api/system/update' do
  app_dir = File.dirname(__FILE__)
  update_script = File.join(app_dir, 'scripts', 'update.sh')

  unless File.exist?(update_script)
    status 500
    return json({
      success: false,
      message: 'Update script not found'
    })
  end

  # Run update in background thread
  Thread.new do
    begin
      puts "=== Starting system update ==="
      system("#{update_script} 2>&1")
      puts "=== Update completed ==="
    rescue => e
      puts "Update error: #{e.message}"
    end
  end

  json({
    success: true,
    message: 'Update started in background. The system will restart automatically.',
    note: 'Check /home/pi/treadwall-update.log for progress'
  })
end

# Get update log (last 50 lines)
get '/api/system/update-log' do
  log_file = '/home/pi/treadwall-update.log'

  if File.exist?(log_file)
    log_lines = `tail -n 50 #{log_file}`.split("\n")
    json({
      success: true,
      log: log_lines
    })
  else
    json({
      success: true,
      log: ['No update log available']
    })
  end
end

# Get system diagnostics (CPU, memory, processes)
get '/api/system/diagnostics' do
  begin
    # Get CPU and memory info
    uptime_output = `uptime`.strip
    load_avg = uptime_output.match(/load average: ([\d.]+), ([\d.]+), ([\d.]+)/)

    # Get memory info
    mem_info = `free -m`.split("\n")[1].split
    mem_total = mem_info[1].to_i
    mem_used = mem_info[2].to_i
    mem_free = mem_info[3].to_i
    mem_percent = (mem_used.to_f / mem_total * 100).round(1)

    # Get process count
    process_count = `ps aux | wc -l`.strip.to_i - 1  # Subtract header

    # Get top CPU processes
    top_cpu = `ps aux --sort=-%cpu | head -n 6 | tail -n 5`.split("\n").map do |line|
      parts = line.split
      {
        user: parts[0],
        pid: parts[1],
        cpu: parts[2],
        mem: parts[3],
        command: parts[10..-1].join(' ')
      }
    end

    # Get top memory processes
    top_mem = `ps aux --sort=-%mem | head -n 6 | tail -n 5`.split("\n").map do |line|
      parts = line.split
      {
        user: parts[0],
        pid: parts[1],
        cpu: parts[2],
        mem: parts[3],
        command: parts[10..-1].join(' ')
      }
    end

    # Check for zombie/defunct processes
    zombie_count = `ps aux | grep defunct | grep -v grep | wc -l`.strip.to_i

    # Check SSH daemon status
    ssh_status = `systemctl is-active ssh 2>/dev/null`.strip
    ssh_enabled = `systemctl is-enabled ssh 2>/dev/null`.strip

    json({
      success: true,
      load_average: {
        one_min: load_avg ? load_avg[1].to_f : nil,
        five_min: load_avg ? load_avg[2].to_f : nil,
        fifteen_min: load_avg ? load_avg[3].to_f : nil
      },
      memory: {
        total_mb: mem_total,
        used_mb: mem_used,
        free_mb: mem_free,
        used_percent: mem_percent
      },
      processes: {
        total: process_count,
        zombie: zombie_count,
        top_cpu: top_cpu,
        top_memory: top_mem
      },
      ssh: {
        status: ssh_status,
        enabled: ssh_enabled
      }
    })
  rescue => e
    status 500
    json({
      success: false,
      message: "Failed to get diagnostics: #{e.message}"
    })
  end
end

# Restart SSH service (emergency recovery)
post '/api/system/restart-ssh' do
  begin
    result = `sudo systemctl restart ssh 2>&1`
    exit_status = $?.exitstatus

    if exit_status == 0
      json({
        success: true,
        message: 'SSH service restarted successfully'
      })
    else
      status 500
      json({
        success: false,
        message: "Failed to restart SSH: #{result}"
      })
    end
  rescue => e
    status 500
    json({
      success: false,
      message: "Error restarting SSH: #{e.message}"
    })
  end
end

# Clean up zombie processes and free resources
post '/api/system/cleanup' do
  begin
    cleanup_log = []

    # Kill zombie python processes (if any)
    python_zombies = `ps aux | grep 'python.*defunct' | grep -v grep | awk '{print $2}'`.split("\n")
    if python_zombies.any?
      python_zombies.each do |pid|
        `sudo kill -9 #{pid} 2>/dev/null`
        cleanup_log << "Killed zombie process #{pid}"
      end
    end

    # Clear system caches (safe operation)
    `sudo sync`
    cleanup_log << "Synced filesystem"

    # Get memory stats before and after
    mem_before = `free -m | grep Mem | awk '{print $3}'`.strip.to_i
    `sudo sh -c 'echo 1 > /proc/sys/vm/drop_caches' 2>/dev/null`
    sleep 1
    mem_after = `free -m | grep Mem | awk '{print $3}'`.strip.to_i
    freed = mem_before - mem_after
    cleanup_log << "Cleared caches, freed #{freed}MB" if freed > 0

    json({
      success: true,
      message: 'System cleanup completed',
      actions: cleanup_log,
      recommendation: 'SSH should be more responsive now. Try restarting SSH if still having issues.'
    })
  rescue => e
    status 500
    json({
      success: false,
      message: "Cleanup failed: #{e.message}"
    })
  end
end

# ========== NETWORK ENDPOINTS ==========

# Get network status
get '/api/network/status' do
  begin
    # Re-detect current mode (dynamic)
    current_mode = detect_network_mode

    # Get WiFi details if connected
    wifi_ssid = nil
    wifi_signal = nil
    if current_mode[:mode] == 'wifi_client'
      wifi_ssid = `iwgetid wlan0 -r 2>/dev/null`.strip
      wifi_signal = `iw wlan0 link 2>/dev/null | grep signal | awk '{print $2}'`.strip
    end

    # Load configured WiFi credentials from config.json
    config_file = File.join(File.dirname(__FILE__), 'config.json')
    config = File.exist?(config_file) ? JSON.parse(File.read(config_file)) : {}
    configured_ssid = config['wifi_ssid'] || 'Not configured'

    # Check internet connectivity (try to ping DNS)
    has_internet = system('ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1')

    json({
      success: true,
      mode: current_mode[:mode],
      mode_description: current_mode[:description],
      interface: current_mode[:interface],
      ip_address: current_mode[:ip] || 'Not assigned',
      wifi: {
        connected: current_mode[:mode] == 'wifi_client',
        ssid: wifi_ssid || 'Not connected',
        signal: wifi_signal || 'N/A',
        configured_ssid: configured_ssid
      },
      usb: {
        connected: current_mode[:mode] == 'usb_fallback',
        ip: current_mode[:mode] == 'usb_fallback' ? current_mode[:ip] : 'Not connected'
      },
      internet: has_internet,
      access_url: current_mode[:ip] ? "http://#{current_mode[:ip]}:4567" : 'http://treadwall.local:4567'
    })
  rescue => e
    status 500
    json({
      success: false,
      message: "Failed to get network status: #{e.message}"
    })
  end
end

# Configure WiFi credentials
post '/api/network/configure' do
  begin
    # Parse request body
    request.body.rewind
    body = request.body.read
    data = JSON.parse(body)

    ssid = data['ssid']
    password = data['password']

    unless ssid && !ssid.empty?
      status 400
      return json({
        success: false,
        message: 'SSID is required'
      })
    end

    unless password && !password.empty?
      status 400
      return json({
        success: false,
        message: 'Password is required'
      })
    end

    # Generate PSK hash using wpa_passphrase
    psk_result = `wpa_passphrase "#{ssid}" "#{password}" 2>/dev/null | grep 'psk=' | grep -v '#' | cut -d'=' -f2`.strip

    if psk_result.empty?
      status 500
      return json({
        success: false,
        message: 'Failed to generate WiFi credentials'
      })
    end

    # Update wpa_supplicant.conf
    wpa_conf = <<~WPA
      ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
      update_config=1
      country=US

      network={
          ssid="#{ssid}"
          psk=#{psk_result}
      }
    WPA

    File.write('/tmp/wpa_supplicant.conf', wpa_conf)
    `sudo mv /tmp/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf`
    `sudo chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf`

    # Save to config.json
    app_dir = File.dirname(__FILE__)
    config_file = File.join(app_dir, 'config.json')
    config = File.exist?(config_file) ? JSON.parse(File.read(config_file)) : {}
    config['wifi_ssid'] = ssid
    config['wifi_password'] = password
    File.write(config_file, JSON.pretty_generate(config))

    # Restart wpa_supplicant to apply changes (in background)
    Thread.new do
      sleep 1
      system('sudo systemctl restart wpa_supplicant 2>/dev/null')
      system('sudo systemctl restart dhcpcd 2>/dev/null')
    end

    json({
      success: true,
      message: 'WiFi credentials updated. Connecting to network...',
      ssid: ssid,
      note: 'Device will attempt to connect. If connection fails, USB access will remain available.'
    })

  rescue JSON::ParserError => e
    status 400
    json({
      success: false,
      message: 'Invalid JSON in request body'
    })
  rescue => e
    status 500
    json({
      success: false,
      message: "Configuration error: #{e.message}"
    })
  end
end


# Cleanup on exit
at_exit do
  begin
    # Stop any running routine
    if $routine_state[:running]
      puts "Stopping routine before exit..."
      stop_routine(false) # Don't return to MIN_POSITION on exit
    end

    # Save final position before exit
    save_position

    puts "Cleanup completed"
  rescue => e
    puts "Error during cleanup: #{e.message}"
  end
end

# Start message
puts "Starting CRIMP (Climbing Routine Interactive Motor Platform)..."
puts "Access the app at http://localhost:4567"
puts "API documentation at http://localhost:4567/api/status"
