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

# ========== STEPPER FUNCTIONS ==========

def set_stepper_position(target_position, bypass_limits: false)
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

# API Status endpoint
get '/api/status' do
  json({
    message: 'Motor Control API - Stepper and Routines',
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
puts "Starting Motor Control Server..."
puts "Access the app at http://localhost:4567"
puts "API documentation at http://localhost:4567/api/status"
