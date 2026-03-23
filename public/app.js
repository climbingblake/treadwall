// API base URL
var API_BASE = '/api';

// ========== STEPPER FUNCTIONS ==========

// Sync slider and input
document.getElementById('stepper-slider').addEventListener('input', function(e) {
  document.getElementById('stepper-input').value = e.target.value;
});

document.getElementById('stepper-input').addEventListener('input', function(e) {
  document.getElementById('stepper-slider').value = e.target.value;
});

// Fetch and update stepper status
async function fetchStepperStatus() {
  try {
    const response = await fetch(`${API_BASE}/stepper/status`);
    const data = await response.json();

    document.getElementById('stepper-current-position').textContent = data.current_position;
    document.getElementById('stepper-increment-display').textContent = data.increment;
    document.getElementById('stepper-max-position').textContent = data.max_position;

    // Update slider min/max dynamically
    document.getElementById('stepper-slider').min = data.min_position;
    document.getElementById('stepper-slider').max = data.max_position;
    document.getElementById('stepper-input').min = data.min_position;
    document.getElementById('stepper-input').max = data.max_position;

    const range = data.max_position - data.min_position;
    const progress = range > 0 ? Math.round(((data.current_position - data.min_position) / range) * 100) : 0;
    document.getElementById('stepper-progress').textContent = progress;

    // Store min/max for preset generation
    window.stepperMinPosition = data.min_position;
    window.stepperMaxPosition = data.max_position;

    hideError('stepper-error');
  } catch (error) {
    showError('stepper-error', 'Failed to fetch stepper status');
  }
}

// Set stepper position
async function setStepperPosition() {
  const position = document.getElementById('stepper-input').value;

  try {
    const response = await fetch(`${API_BASE}/stepper/${position}`);
    const data = await response.json();

    if (data.success) {
      await fetchStepperStatus();
    } else {
      showError('stepper-error', data.message);
    }
  } catch (error) {
    showError('stepper-error', 'Failed to set stepper position');
  }
}

// Increment stepper
async function stepperIncrement() {
  try {
    const response = await fetch(`${API_BASE}/stepper/increment`);
    await fetchStepperStatus();
  } catch (error) {
    showError('stepper-error', 'Failed to increment stepper');
  }
}

// Decrement stepper
async function stepperDecrement() {
  try {
    const response = await fetch(`${API_BASE}/stepper/decrement`);
    await fetchStepperStatus();
  } catch (error) {
    showError('stepper-error', 'Failed to decrement stepper');
  }
}

// Set stepper increment
async function setStepperIncrement() {
  const increment = document.getElementById('stepper-increment-input').value;

  try {
    const response = await fetch(`${API_BASE}/stepper/settings/increment/${increment}`);
    const data = await response.json();

    if (data.success) {
      await fetchStepperStatus();
      generateStepperPresets(); // Update presets when increment changes
    }
  } catch (error) {
    showError('stepper-error', 'Failed to set stepper increment');
  }
}

// Set stepper position directly (for presets)
function setStepperPositionValue(position) {
  document.getElementById('stepper-slider').value = position;
  document.getElementById('stepper-input').value = position;
  setStepperPosition();
}

// Reset position to 0 (calibration)
async function resetPosition() {
  try {
    const response = await fetch(`${API_BASE}/stepper/reset`, {
      method: 'POST'
    });
    const data = await response.json();

    if (data.success) {
      await fetchStepperStatus();
      // Update slider and input to reflect new position
      document.getElementById('stepper-slider').value = 0;
      document.getElementById('stepper-input').value = 0;
    } else {
      showError('stepper-error', data.message);
    }
  } catch (error) {
    showError('stepper-error', 'Failed to reset position');
  }
}

// DANGER: Calibration increment (bypasses min/max)
async function calibrateIncrement() {
  try {
    const response = await fetch(`${API_BASE}/stepper/calibrate/increment`, {
      method: 'POST'
    });
    const data = await response.json();

    if (data.success) {
      await fetchStepperStatus();
    } else {
      showError('stepper-error', data.message);
    }
  } catch (error) {
    showError('stepper-error', 'Failed to calibrate increment');
  }
}

// DANGER: Calibration decrement (bypasses min/max)
async function calibrateDecrement() {
  try {
    const response = await fetch(`${API_BASE}/stepper/calibrate/decrement`, {
      method: 'POST'
    });
    const data = await response.json();

    if (data.success) {
      await fetchStepperStatus();
    } else {
      showError('stepper-error', data.message);
    }
  } catch (error) {
    showError('stepper-error', 'Failed to calibrate decrement');
  }
}

// Generate preset buttons dynamically from MIN to MAX based on increment
function generateStepperPresets() {
  var incrementInput = document.getElementById('stepper-increment-input');
  if (!incrementInput) {
    console.log('Increment input not found');
    return;
  }

  var increment = parseInt(incrementInput.value);
  if (!increment || increment <= 0) {
    console.log('Invalid increment value: ' + increment);
    return;
  }

  var minPosition = window.stepperMinPosition;
  var maxPosition = window.stepperMaxPosition;

  // Use fallback values if not set
  if (typeof minPosition === 'undefined') minPosition = 0;
  if (typeof maxPosition === 'undefined') maxPosition = 60000;

  var presetsContainer = document.getElementById('stepper-presets');
  if (!presetsContainer) {
    console.log('Presets container not found');
    return;
  }

  console.log('Generating presets: min=' + minPosition + ' max=' + maxPosition + ' increment=' + increment);

  // Clear existing presets
  presetsContainer.innerHTML = '';

  // Generate buttons from MIN to MAX in increment steps
  var buttonCount = 0;
  for (var position = minPosition; position <= maxPosition; position += increment) {
    var button = document.createElement('button');
    button.className = 'btn-secondary';
    button.textContent = position.toString();
    button.setAttribute('data-position', position);
    button.onclick = function() {
      setStepperPositionValue(parseInt(this.getAttribute('data-position')));
    };
    presetsContainer.appendChild(button);
    buttonCount++;
  }

  console.log('Generated ' + buttonCount + ' preset buttons');
}

// ========== ROUTINE FUNCTIONS ==========

var routines = [];
var selectedRoutineId = null;
var routinePollingInterval = null;

// Fetch all available routines
async function fetchRoutines() {
  try {
    var response = await fetch(API_BASE + '/routines');
    var data = await response.json();
    routines = data.routines;
    populateRoutineSelector();
    console.log('Loaded ' + routines.length + ' routines');
  } catch (error) {
    console.error('Failed to fetch routines:', error);
    showError('routine-error', 'Failed to load routines');
  }
}

// Populate the routine selector dropdown
function populateRoutineSelector() {
  var selector = document.getElementById('routine-selector');
  if (!selector) return;

  selector.innerHTML = '<option value="">Select a routine...</option>';

  routines.forEach(function(routine) {
    var option = document.createElement('option');
    option.value = routine.id;
    option.textContent = routine.name + ' (' + formatDuration(routine.total_duration) + ')';
    selector.appendChild(option);
  });

  selector.addEventListener('change', function() {
    selectedRoutineId = this.value;
    if (selectedRoutineId) {
      showRoutinePreview(selectedRoutineId);
    } else {
      hideRoutinePreview();
    }
  });
}

// Show routine preview
async function showRoutinePreview(routineId) {
  try {
    var response = await fetch(API_BASE + '/routines/' + routineId);
    var data = await response.json();

    if (data.success) {
      var routine = data.routine;
      var detailsEl = document.getElementById('routine-details');
      if (!detailsEl) return;

      var html = '<div class="routine-preview">';
      html += '<h3>' + routine.name + '</h3>';
      html += '<p class="routine-description">' + routine.description + '</p>';
      html += '<div class="routine-stats">';
      html += '<span><strong>Steps:</strong> ' + routine.steps.length + '</span>';

      var totalDuration = routine.steps.reduce(function(sum, step) {
        return sum + step.duration;
      }, 0);
      html += '<span><strong>Duration:</strong> ' + formatDuration(totalDuration) + '</span>';
      html += '<span><strong>Repeat:</strong> ' + (routine.options.repeat ? 'Yes' : 'No') + '</span>';
      html += '</div>';

      html += '<div class="routine-steps-preview">';
      routine.steps.forEach(function(step, index) {
        html += '<div class="step-preview">';
        html += '<div class="step-number">' + (index + 1) + '</div>';
        html += '<div class="step-info">';
        html += '<div class="step-label">' + step.label + '</div>';
        html += '<div class="step-detail">Position: ' + step.position + ' | Duration: ' + step.duration + 's</div>';
        html += '</div>';
        html += '</div>';
      });
      html += '</div>';
      html += '</div>';

      detailsEl.innerHTML = html;
      detailsEl.style.display = 'block';
    }
  } catch (error) {
    console.error('Failed to fetch routine details:', error);
  }
}

// Hide routine preview
function hideRoutinePreview() {
  var detailsEl = document.getElementById('routine-details');
  if (detailsEl) {
    detailsEl.style.display = 'none';
  }
}

// Start selected routine
async function startRoutine() {
  console.log('=== START ROUTINE CALLED ===');

  // Check if routine view is visible
  var routineDiv = document.getElementById('routine-div');
  if (routineDiv) {
    console.log('Routine div display:', routineDiv.style.display);
  }

  if (!selectedRoutineId) {
    showError('routine-error', 'Please select a routine first');
    return;
  }

  hideError('routine-error');

  try {
    var response = await fetch(API_BASE + '/routines/' + selectedRoutineId + '/start', {
      method: 'POST'
    });
    var data = await response.json();

    if (data.success) {
      console.log('Routine started successfully');

      // Update UI
      console.log('Calling updateRoutineControlButtons(true, false)...');
      updateRoutineControlButtons(true, false);

      // Show status display
      var statusDiv = document.getElementById('routine-status');
      console.log('routine-status element:', statusDiv);
      if (statusDiv) {
        console.log('Current display style:', statusDiv.style.display);
        statusDiv.style.display = 'grid';
        console.log('Set display to grid. New value:', statusDiv.style.display);
      } else {
        console.error('routine-status element not found!');
      }

      // Show timeline
      var timelineContainer = document.getElementById('routine-timeline-container');
      console.log('routine-timeline-container element:', timelineContainer);
      if (timelineContainer) {
        console.log('Current display style:', timelineContainer.style.display);
        timelineContainer.style.display = 'block';
        console.log('Set display to block. New value:', timelineContainer.style.display);
      } else {
        console.error('routine-timeline-container element not found!');
      }

      // Start polling routine status
      console.log('Starting status polling...');
      startRoutineStatusPolling();
    } else {
      showError('routine-error', data.message);
    }
  } catch (error) {
    showError('routine-error', 'Failed to start routine');
    console.error(error);
  }
}

// Stop current routine (emergency stop - always safe)
async function stopRoutine() {
  hideError('routine-error');

  try {
    var response = await fetch(API_BASE + '/routines/stop', {
      method: 'POST'
    });
    var data = await response.json();

    // Always update UI after stop
    updateRoutineControlButtons(false, false);

    var statusDiv = document.getElementById('routine-status');
    if (statusDiv) {
      statusDiv.style.display = 'none';
    }

    // Hide timeline
    var timelineContainer = document.getElementById('routine-timeline-container');
    if (timelineContainer) {
      timelineContainer.style.display = 'none';
    }

    // Stop polling
    stopRoutineStatusPolling();

    // Show success message briefly
    console.log(data.message);
  } catch (error) {
    showError('routine-error', 'Failed to execute emergency stop');
    console.error(error);
  }
}

// Pause current routine
async function pauseRoutine() {
  try {
    var response = await fetch(API_BASE + '/routines/pause', {
      method: 'POST'
    });
    var data = await response.json();

    if (data.success) {
      updateRoutineControlButtons(true, true);
    } else {
      showError('routine-error', data.message);
    }
  } catch (error) {
    showError('routine-error', 'Failed to pause routine');
    console.error(error);
  }
}

// Resume paused routine
async function resumeRoutine() {
  try {
    var response = await fetch(API_BASE + '/routines/resume', {
      method: 'POST'
    });
    var data = await response.json();

    if (data.success) {
      updateRoutineControlButtons(true, false);
    } else {
      showError('routine-error', data.message);
    }
  } catch (error) {
    showError('routine-error', 'Failed to resume routine');
    console.error(error);
  }
}

// Fetch and update routine status
async function fetchRoutineStatus() {
  try {
    var response = await fetch(API_BASE + '/routines/status');
    var data = await response.json();

    console.log('Routine status:', data);

    if (data.running) {
      updateRoutineStatusUI(data);
      updateRoutineControlButtons(true, data.paused);
    } else if (routinePollingInterval) {
      // Routine stopped, clean up UI
      console.log('Routine finished, cleaning up UI');
      stopRoutineStatusPolling();
      updateRoutineControlButtons(false, false);

      var statusDiv = document.getElementById('routine-status');
      if (statusDiv) {
        statusDiv.style.display = 'none';
      }

      var timelineContainer = document.getElementById('routine-timeline-container');
      if (timelineContainer) {
        timelineContainer.style.display = 'none';
      }
    }
  } catch (error) {
    console.error('Failed to fetch routine status:', error);
  }
}

// Update routine status UI
function updateRoutineStatusUI(data) {
  console.log('Updating routine status UI:', data);

  var stepEl = document.getElementById('routine-current-step');
  if (stepEl) stepEl.textContent = (data.current_step + 1);

  var totalEl = document.getElementById('routine-total-steps');
  if (totalEl) totalEl.textContent = data.total_steps;

  var labelEl = document.getElementById('routine-step-label');
  if (labelEl) labelEl.textContent = data.step_label || '-';

  var progressEl = document.getElementById('routine-step-progress');
  if (progressEl) progressEl.textContent = data.step_progress;

  var elapsedEl = document.getElementById('routine-step-elapsed');
  if (elapsedEl) elapsedEl.textContent = data.step_elapsed;

  var durationEl = document.getElementById('routine-step-duration');
  if (durationEl) durationEl.textContent = data.step_duration;

  // Update progress bar if it exists
  var progressBar = document.getElementById('routine-progress-bar');
  if (progressBar) {
    progressBar.style.width = data.step_progress + '%';
    console.log('Progress bar updated to ' + data.step_progress + '%');
  }

  // Update timeline if it exists
  updateRoutineTimeline(data);
}

// Update routine timeline visual
function updateRoutineTimeline(data) {
  var timeline = document.getElementById('routine-timeline');
  if (!timeline) {
    console.log('Timeline element not found');
    return;
  }

  // Find routine to get step count
  var routine = routines.find(function(r) { return r.id === data.routine_id; });
  if (!routine) {
    console.log('Routine not found for timeline:', data.routine_id);
    return;
  }

  console.log('Updating timeline: step ' + (data.current_step + 1) + ' of ' + data.total_steps);

  // Clear timeline
  timeline.innerHTML = '';

  // Create step indicators
  for (var i = 0; i < data.total_steps; i++) {
    var stepEl = document.createElement('div');
    stepEl.className = 'timeline-step';

    if (i < data.current_step) {
      stepEl.classList.add('completed');
    } else if (i === data.current_step) {
      stepEl.classList.add('active');
    }

    timeline.appendChild(stepEl);
  }
}

// Start polling routine status
function startRoutineStatusPolling() {
  if (routinePollingInterval) return;

  fetchRoutineStatus(); // Immediate fetch
  routinePollingInterval = setInterval(fetchRoutineStatus, 500); // Poll every 500ms
}

// Stop polling routine status
function stopRoutineStatusPolling() {
  if (routinePollingInterval) {
    clearInterval(routinePollingInterval);
    routinePollingInterval = null;
  }
}

// Update button states
function updateRoutineControlButtons(running, paused) {
  console.log('updateRoutineControlButtons called: running=' + running + ', paused=' + paused);

  var startBtn = document.getElementById('routine-start');
  var pauseBtn = document.getElementById('routine-pause');
  var resumeBtn = document.getElementById('routine-resume');
  var stopBtn = document.getElementById('routine-stop');

  console.log('Button elements found:', {
    start: !!startBtn,
    pause: !!pauseBtn,
    resume: !!resumeBtn,
    stop: !!stopBtn
  });

  if (!startBtn) {
    console.error('Start button not found!');
    return;
  }

  // STOP button is ALWAYS enabled for emergency safety
  stopBtn.disabled = false;

  if (running) {
    startBtn.disabled = true;

    if (paused) {
      pauseBtn.disabled = true;
      pauseBtn.style.display = 'none';
      resumeBtn.disabled = false;
      resumeBtn.style.display = 'inline-block';
      console.log('Routine PAUSED: pause hidden, resume enabled');
    } else {
      pauseBtn.disabled = false;
      pauseBtn.style.display = 'inline-block';
      resumeBtn.disabled = true;
      resumeBtn.style.display = 'none';
      console.log('Routine RUNNING: pause enabled, resume hidden');
    }
  } else {
    startBtn.disabled = false;
    pauseBtn.disabled = true;
    pauseBtn.style.display = 'inline-block';
    resumeBtn.disabled = true;
    resumeBtn.style.display = 'none';
    console.log('Routine STOPPED: start enabled, pause/resume disabled');
  }

  console.log('Button states after update:', {
    start: startBtn.disabled,
    pause: pauseBtn.disabled,
    resume: resumeBtn.disabled,
    stop: stopBtn.disabled
  });
}

// Format duration in seconds to readable format
function formatDuration(seconds) {
  var mins = Math.floor(seconds / 60);
  var secs = seconds % 60;
  if (mins > 0) {
    return mins + 'm ' + secs + 's';
  }
  return secs + 's';
}

// ========== UTILITY FUNCTIONS ==========

function showError(elementId, message) {
  var errorEl = document.getElementById(elementId);
  if (errorEl) {
    errorEl.textContent = message;
    errorEl.classList.add('show');
  }
}

function hideError(elementId) {
  var errorEl = document.getElementById(elementId);
  if (errorEl) {
    errorEl.classList.remove('show');
  }
}

// ========== INITIALIZATION ==========

// Initial status fetch and preset generation
function initialize() {
  console.log('Initializing motor control interface...');
  fetchStepperStatus().then(function() {
    console.log('Stepper status loaded, generating presets...');
    // Generate presets after stepper status is loaded
    setTimeout(generateStepperPresets, 100);
  }).catch(function(error) {
    console.log('Error loading stepper status:', error);
    // Try to generate presets anyway with fallback values
    setTimeout(generateStepperPresets, 100);
  });

  // Load routines
  fetchRoutines();

  // Initialize button states
  console.log('Initializing routine control buttons...');
  updateRoutineControlButtons(false, false);

  console.log('=== INITIALIZATION COMPLETE ===');
  console.log('To use routines: Click "Switch to Routines" button, select a routine, then click Start');
}

initialize();

// Poll status every 2 seconds
setInterval(function() {
  fetchStepperStatus();
}, 2000);

// Expose preset generation function globally for debugging
window.generateStepperPresets = generateStepperPresets;
console.log('Motor control app loaded. Call generateStepperPresets() to manually regenerate presets.');
