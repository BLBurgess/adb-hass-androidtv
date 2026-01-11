#!/usr/bin/env bash

# This project is licensed under the MIT License.
# See the LICENSE file for details.

set -euo pipefail
IFS=$'\n\t'

#--------------------------------
# Dependencies
#--------------------------------
YQ_BIN=${YQ_BIN:-/usr/local/bin/yq}
ADB_BIN=${ADB_BIN:-/opt/platform-tools/adb}

#--------------------------------
# Paths
#--------------------------------
CONFIG_DIR="/opt/androidtv-connect"
CONFIG_FILE="${CONFIG_FILE:-$CONFIG_DIR/config.yml}"
PAIRING_RECORD_FILE="$CONFIG_DIR/.paired_devices"
LOG_FILE="$CONFIG_DIR/androidtv-connect.log"

#--------------------------------
# Default values
#--------------------------------
BOOTWAIT_DEFAULT=10
CHECKFREQ_DEFAULT=300

mkdir -p "$CONFIG_DIR"
touch "$PAIRING_RECORD_FILE" "$LOG_FILE"

#--------------------------------
# Logging with rotation
#--------------------------------
log() {
    local message="$*"
    local timestamp
    timestamp=$(date '+%m-%d %H:%M:%S')
    echo "$timestamp androidtv-connect : $message" | tee -a "$LOG_FILE"

    if [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE")" -gt $((5*1024*1024)) ]; then
        for i in {4..1}; do
            [ -f "$CONFIG_DIR/androidtv-connect.log.$i" ] && mv "$CONFIG_DIR/androidtv-connect.log.$i" "$CONFIG_DIR/androidtv-connect.log.$((i+1))"
        done
        mv "$LOG_FILE" "$CONFIG_DIR/androidtv-connect.log.1"
        touch "$LOG_FILE"
    fi
}

log "===== Starting androidtv-connect script ====="

#--------------------------------
# Load configuration
#--------------------------------
declare -A CONFIG
CONFIG["bootwait"]="${bootwait:-$BOOTWAIT_DEFAULT}"
CONFIG["checkfreq"]="${checkfreq:-$CHECKFREQ_DEFAULT}"
CONFIG["enable_adb_usb"]="${enable_adb_usb:-0}"
CONFIG["devicelist"]=""

# Check if YAML file exists
if [[ -f "$CONFIG_FILE" ]]; then
    log "Loading configuration from $CONFIG_FILE..."
    # Preprocess environment variables with defaults
    bootwait_env="${bootwait:-$BOOTWAIT_DEFAULT}"
    checkfreq_env="${checkfreq:-$CHECKFREQ_DEFAULT}"
    enable_adb_usb_env="${enable_adb_usb:-0}"

    # Use preprocessed values in yq expressions
    CONFIG["bootwait"]=$($YQ_BIN eval "select(. | type != \"!!str\" or .[0] != \"#\") | .bootwait // \"$bootwait_env\"" "$CONFIG_FILE")
    CONFIG["checkfreq"]=$($YQ_BIN eval "select(. | type != \"!!str\" or .[0] != \"#\") | .checkfreq // \"$checkfreq_env\"" "$CONFIG_FILE")
    CONFIG["enable_adb_usb"]=$($YQ_BIN eval "select(. | type != \"!!str\" or .[0] != \"#\") | .enable_adb_usb // \"$enable_adb_usb_env\"" "$CONFIG_FILE")
    CONFIG["devicelist"]=$($YQ_BIN eval 'select(. | type != "!!str" or .[0] != "#") | .devicelist // []' "$CONFIG_FILE")
else
    log "Configuration file not found. Falling back to environment variables."
fi

# Process devicelist environment variable if no devicelist in the config.yml file
if [[ -z "${CONFIG["devicelist"]}" || "${CONFIG["devicelist"]}" == "[]" ]]; then
    if [[ -n "${devicelist:-}" ]]; then
        IFS=',' read -r -a dev_array <<< "$devicelist"
        devices_json="["
        for d in "${dev_array[@]}"; do
            host="${d%%:*}"
            rest="${d#*:}"
            port="${rest%%:*}"
            auth_code="${rest#*:}"
            if [[ "$auth_code" == "$rest" ]]; then
                auth_code=""
                auth_port=""
            else
                auth_port="${rest##*:}"
                [[ "$auth_port" == "$auth_code" ]] && auth_port=""
            fi
            devices_json+="{\"host\":\"$host\",\"port\":$port,\"auth_code\":\"$auth_code\",\"auth_port\":\"$auth_port\"},"
        done
        devices_json="${devices_json%,}]"  # remove trailing comma
        CONFIG["devicelist"]="$devices_json"
    fi
fi

# Normalize enable_adb_usb setting to 0 or 1
normalize_enable_adb_usb() {
    local value="$1"
    case "$value" in
        1|yes|YES|true|TRUE) echo 1 ;;
        0|no|NO|false|FALSE) echo 0 ;;
        *) echo 0 ;;  # Default to 0 if invalid
    esac
}

# Normalize enable_adb_usb setting to 0 or 1
CONFIG["enable_adb_usb"]=$(normalize_enable_adb_usb "${CONFIG["enable_adb_usb"]}")

# Exit early if no devices configured
if [[ -z "${CONFIG["devicelist"]}" || "${CONFIG["devicelist"]}" == "[]" ]]; then
    log "No devices configured via YAML or devicelist environment variable. Exiting."
    exit 1
fi

#--------------------------------
# Helper functions
#--------------------------------
is_connected() {
    local host="$1" port="$2"
    "$ADB_BIN" devices | grep -w "${host}:${port}" >/dev/null 2>&1
}

is_paired() {
    local host="$1" auth_port="$2"
    grep -q "^${host}:${auth_port}:" "$PAIRING_RECORD_FILE"
}

record_pairing() {
    local host="$1" auth_port="$2" auth_code="$3"
    sed -i "/^${host}:${auth_port}:/d" "$PAIRING_RECORD_FILE"
    echo "${host}:${auth_port}:${auth_code}" >> "$PAIRING_RECORD_FILE"
}

cleanup_pairings() {
    local current_devices="$1"
    local tmpfile
    tmpfile=$(mktemp)
    grep -Ff <(echo "$current_devices") "$PAIRING_RECORD_FILE" > "$tmpfile" || true
    mv "$tmpfile" "$PAIRING_RECORD_FILE"
}

connect_device() {
    local host="$1" port="$2" auth_code="$3" auth_port="$4"

    if is_connected "$host" "$port"; then
        log "Device $host:$port already connected, skipping."
        return
    fi

    if [[ -n "$auth_code" && -n "$auth_port" ]]; then
        local paired_entry current_code
        paired_entry=$(grep "^${host}:${auth_port}:" "$PAIRING_RECORD_FILE" || true)
        current_code="${paired_entry##*:}"
        if [[ "$current_code" != "$auth_code" ]]; then
            log "Auth code changed or not paired for $host:$auth_port. Pairing..."
            if "$ADB_BIN" pair "$host:$auth_port" "$auth_code"; then
                log "Pairing successful for $host:$auth_port"
                record_pairing "$host" "$auth_port" "$auth_code"
            else
                log "Warning: Pairing failed for $host:$auth_port"
            fi
        fi
    fi

    # Run adb connect in the background
    {
        log "Connecting to $host:$port..."
        adb_output=$("$ADB_BIN" connect "$host:$port" 2>&1)
        if echo "$adb_output" | grep -q "connected to"; then
            log "Connected to $host:$port"
        else
            log "Warning: Failed to connect to $host:$port. Output: $adb_output"
        fi
    } &
}

#--------------------------------
# Validation for bootwait and checkfreq to ensure they are integers within valid range.
validate_integer() {
    local value="$1"
    local default="$2"
    local name="$3"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || ((value <= 0 || value >= 86400)); then
        log "$name is invalid (must be an integer > 0 and < 86400). Using default: $default"
        echo "$default"
    else
        echo "$value"
    fi
}

# Validate bootwait and checkfreq
CONFIG["bootwait"]=$(validate_integer "${CONFIG["bootwait"]}" "$BOOTWAIT_DEFAULT" "bootwait")
CONFIG["checkfreq"]=$(validate_integer "${CONFIG["checkfreq"]}" "$CHECKFREQ_DEFAULT" "checkfreq")

# Validation for host to ensure it is a valid IPv4 address or DNS name.
validate_host() {
    local host="$1"
    if [[ "$host" =~ ^([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,}$ || \
          "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "$host"
    else
        echo ""
    fi
}

# Validate hosts in devicelist
log "Validating hosts & settings in devicelist..."
devices_json="["
declare -A seen_hosts
# Initialize valid_host to avoid unbound variable errors
valid_host=""

for device in $(echo "${CONFIG["devicelist"]}" | $YQ_BIN eval '.[] | @json' - 2>/dev/null || echo ""); do
    host=$(echo "$device" | $YQ_BIN eval '.host // ""' - 2>/dev/null || echo "")
    port=$(echo "$device" | $YQ_BIN eval '.port // 5555' - 2>/dev/null || echo "5555")
    auth_code=$(echo "$device" | $YQ_BIN eval '.auth_code // ""' - 2>/dev/null || echo "")
    auth_port=$(echo "$device" | $YQ_BIN eval '.auth_port // ""' - 2>/dev/null || echo "")
    name=$(echo "$device" | $YQ_BIN eval '.name // "none"' - 2>/dev/null || echo "none")

    # Trim whitespace from port, auth_code, and auth_port
    port=$(echo "$port" | xargs)
    auth_code=$(echo "$auth_code" | xargs)
    auth_port=$(echo "$auth_port" | xargs)

    valid_host=$(validate_host "$host")
    if [[ -z "$valid_host" ]]; then
        log "Invalid host: $host. Skipping."
        continue
    fi

    if ! [[ "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
        log "Invalid port: $port for host $host. Must be between 1 and 65535. Skipping."
        continue
    fi

    if [[ -n "$auth_code" && ! "$auth_code" =~ ^[0-9]{6}$ ]]; then
        log "Invalid auth_code: $auth_code for host $host. Must be a 6-digit number. Skipping."
        continue
    fi

    if [[ -n "$auth_port" && (! "$auth_port" =~ ^[0-9]+$ || auth_port -lt 1 || auth_port -gt 65535) ]]; then
        log "Invalid auth_port: $auth_port for host $host. Must be between 1 and 65535. Skipping."
        continue
    fi

    if [[ "${seen_hosts[$valid_host]:-}" ]]; then
        log "Duplicate host found: $valid_host. Skipping."
        continue
    fi

    log "Valid host named: $name ($valid_host). Adding to devicelist."
    seen_hosts[$valid_host]=1
    devices_json+="{\"name\":\"$name\",\"host\":\"$valid_host\",\"port\":$port,\"auth_code\":\"$auth_code\",\"auth_port\":\"$auth_port\"},"
done
devices_json="${devices_json%,}]"  # remove trailing comma
CONFIG["devicelist"]="$devices_json"

#--------------------------------
# Pretty-print configuration for logging
#--------------------------------
log "==== CONFIGURATION ===="
log "bootwait=${CONFIG["bootwait"]}"
log "checkfreq=${CONFIG["checkfreq"]}"
log "enable_adb_usb=${CONFIG["enable_adb_usb"]}"
log "devicelist="

echo "${CONFIG["devicelist"]}" | $YQ_BIN eval '.[] | "Name: \(.name // \"none\")\n  IP: \(.host // \"N/A\")\n  Port: \(.port // 5555)\n  Auth Port: \(.auth_port // \"N/A\")\n  Auth Code: \(.auth_code // \"N/A\")"' - 2>/dev/null || log "Error parsing devicelist for logging."

log "======================="

#--------------------------------
# Trap SIGINT and SIGTERM to cleanly shut down the ADB server
cleanup() {
    log "Shutting down ADB server..."
    kill "$ADB_SERVER_PID" 2>/dev/null || true  # Kill the ADB server process directly
    wait  # Wait for all background processes to terminate
    log "ADB server shut down. Exiting."
    log "===== androidtv-connect script stopped ====="
    exit 0
}

trap cleanup SIGINT SIGTERM

# Start ADB server
log "Starting ADB server..."
ADB_LIBUSB=${CONFIG["enable_adb_usb"]} "$ADB_BIN" -a -P 5037 server nodaemon &
ADB_SERVER_PID=$!
if [[ "${CONFIG["enable_adb_usb"]}" == "1" ]]; then
    log "ADB USB enabled"
else
    log "ADB USB disabled"
fi
log "Waiting ${CONFIG["bootwait"]} seconds for startup..."
sleep "${CONFIG["bootwait"]}"

#--------------------------------
# Main loop
#--------------------------------
while true; do
    current_device_keys=""
    device_count=$(echo "${CONFIG["devicelist"]}" | $YQ_BIN eval 'length' - 2>/dev/null || echo "0")
    for i in $(seq 0 $((device_count - 1))); do
        host=$(echo "${CONFIG["devicelist"]}" | $YQ_BIN eval ".[$i].host" - 2>/dev/null || echo "")
        port=$(echo "${CONFIG["devicelist"]}" | $YQ_BIN eval ".[$i].port" - 2>/dev/null || echo "")
        auth_code=$(echo "${CONFIG["devicelist"]}" | $YQ_BIN eval ".[$i].auth_code" - 2>/dev/null || echo "")
        auth_port=$(echo "${CONFIG["devicelist"]}" | $YQ_BIN eval ".[$i].auth_port" - 2>/dev/null || echo "")

        [[ -n "$auth_port" ]] && current_device_keys+="${host}:${auth_port}"$'\n'

        connect_device "$host" "$port" "$auth_code" "$auth_port" &
    done

    [[ -n "$current_device_keys" ]] && cleanup_pairings "$current_device_keys"

    log "Sleeping ${CONFIG["checkfreq"]} seconds before next check..."
    sleep "${CONFIG["checkfreq"]}"
done
