#!/bin/bash
################################################################################
# TreadWall Auto-Update Script
#
# This script safely updates the TreadWall application from the git repository.
# It includes automatic backup and rollback on failure.
#
# Usage: ./scripts/update.sh
################################################################################

set -e  # Exit on error

# Configuration
APP_DIR="/home/pi/treadwall"
BACKUP_DIR="/home/pi/treadwall-backup-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/home/pi/treadwall-update.log"
SERVICE_NAME="motor-control.service"
MAX_BACKUPS=3

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# Logging function
log() {
    echo -e "${2:-}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    log "✓ $1" "$GREEN"
}

log_error() {
    log "✗ $1" "$RED"
}

log_warning() {
    log "⚠ $1" "$YELLOW"
}

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

################################################################################
# Main Update Process
################################################################################

log "========================================" "$GREEN"
log "TreadWall Update Started" "$GREEN"
log "========================================" "$GREEN"

# Check if we're in the right directory
if [ ! -d "$APP_DIR/.git" ]; then
    error_exit "Git repository not found at $APP_DIR"
fi

cd "$APP_DIR" || error_exit "Failed to change to application directory"

# Get current version info
CURRENT_VERSION=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
log "Current version: $CURRENT_VERSION on branch $CURRENT_BRANCH"

# Check if there are updates available
log "Checking for updates..."
git fetch origin 2>&1 | tee -a "$LOG_FILE"

LOCAL_COMMIT=$(git rev-parse HEAD)
REMOTE_COMMIT=$(git rev-parse origin/main)

if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ]; then
    log_success "Already up to date!"
    exit 0
fi

log "Updates available. Proceeding with update..."

# Create backup
log "Creating backup..."
if cp -r "$APP_DIR" "$BACKUP_DIR"; then
    log_success "Backup created at $BACKUP_DIR"
else
    error_exit "Failed to create backup"
fi

# Stash any local changes (preserves motor_state.json, etc.)
log "Stashing local changes..."
if git stash push -m "Auto-stash before update $(date)" 2>&1 | tee -a "$LOG_FILE"; then
    STASHED=true
    log_success "Local changes stashed"
else
    log_warning "No local changes to stash (this is normal)"
    STASHED=false
fi

# Pull latest code
log "Pulling latest code from origin/main..."
if git pull origin main 2>&1 | tee -a "$LOG_FILE"; then
    NEW_VERSION=$(git rev-parse --short HEAD)
    log_success "Code updated: $CURRENT_VERSION → $NEW_VERSION"
else
    error_exit "Failed to pull latest code"
fi

# Restore local changes
if [ "$STASHED" = true ]; then
    log "Restoring local changes..."
    if git stash pop 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Local changes restored"
    else
        log_warning "Could not restore stashed changes (may need manual merge)"
    fi
fi

# Check if dependencies need updating
if [ -f "Gemfile" ]; then
    log "Checking Ruby dependencies..."

    # Ensure bundler is installed
    if ! command -v bundle &> /dev/null; then
        log "Installing bundler..."
        sudo gem install bundler --no-doc 2>&1 | tee -a "$LOG_FILE"
    fi

    # Verify gems are present (they should be vendored in git)
    if [ -d "vendor/bundle" ]; then
        log_success "Vendored gems found"
    else
        log_warning "Vendored gems not found, installing..."
        bundle config set --local path 'vendor/bundle'
        bundle install 2>&1 | tee -a "$LOG_FILE"
    fi

    log_success "Dependencies ready"
fi

# Restart the service
log "Restarting $SERVICE_NAME..."
if sudo systemctl restart "$SERVICE_NAME" 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Service restarted"
else
    error_exit "Failed to restart service"
fi

# Wait for service to stabilize
log "Waiting for service to stabilize..."
sleep 5

# Health check
log "Performing health check..."
if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    log_success "Service is running!"

    # Additional health check - test API endpoint
    if curl -s -f http://localhost:4567/api/status > /dev/null 2>&1; then
        log_success "API responding correctly!"
    else
        log_warning "Service running but API not responding (may need time to start)"
    fi

    # Update successful
    log "========================================" "$GREEN"
    log_success "Update completed successfully!"
    log "Version: $NEW_VERSION" "$GREEN"
    log "========================================" "$GREEN"

    # Clean up old backups (keep last N)
    log "Cleaning up old backups (keeping last $MAX_BACKUPS)..."
    ls -dt /home/pi/treadwall-backup-* 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -rf 2>/dev/null || true
    log_success "Cleanup complete"

    exit 0
else
    # Service failed - rollback
    log_error "Service failed to start! Rolling back..."

    sudo systemctl stop "$SERVICE_NAME" 2>&1 | tee -a "$LOG_FILE"

    # Remove failed update
    rm -rf "$APP_DIR"

    # Restore backup
    if mv "$BACKUP_DIR" "$APP_DIR"; then
        log_success "Backup restored"
    else
        error_exit "CRITICAL: Failed to restore backup!"
    fi

    # Restart with old version
    if sudo systemctl start "$SERVICE_NAME"; then
        log_warning "Service restarted with previous version"
    else
        error_exit "CRITICAL: Failed to start service with backup!"
    fi

    log "========================================" "$RED"
    log_error "Update failed and was rolled back"
    log "Version: $CURRENT_VERSION (restored)" "$RED"
    log "========================================" "$RED"

    exit 1
fi
