#!/bin/bash
# manual-fan-control.sh
# Usage:
#   --enable         : Sets policy to 'user_space' (allows manual control)
#   --disable        : Sets policy to 'step_wise' (kernel automatic control)
#   --pwm <0-255>    : Sets fan speed (only if policy is user_space)
#   --status         : Shows current zone, policy, and fan path
#   --monitor        : Live feed of Temp, PWM, and RPM
#   --install <0-255>: Installs systemd service with default boot speed
#   --uninstall      : Removes systemd service

# Service constants
SERVICE_NAME="manual-fan.service"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
SCRIPT_INSTALL_PATH="/usr/local/bin/manual-fan-control.sh"

# Exit on error
set -e

# --- 1. Root Check ---
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script requires root privileges. Please run with sudo."
  exit 1
fi

# --- 2. Argument Parsing ---
MODE=""
PWM_VALUE=0

if [[ "$1" == "--enable" ]]; then
    MODE="SET_POLICY"
    TARGET_POLICY="user_space"
    echo "Mode: ENABLE (Setting policy to user_space)"

elif [[ "$1" == "--disable" ]]; then
    MODE="SET_POLICY"
    TARGET_POLICY="step_wise"
    echo "Mode: DISABLE (Restoring policy to step_wise)"

elif [[ "$1" == "--pwm" ]]; then
    MODE="SET_PWM"
    PWM_VALUE="$2"
    # Validate Integer and Range (0-255)
    if ! [[ "$PWM_VALUE" =~ ^[0-9]+$ ]] || [ "$PWM_VALUE" -lt 0 ] || [ "$PWM_VALUE" -gt 255 ]; then
        echo "Error: --pwm requires an integer between 0 and 255."
        exit 1
    fi

elif [[ "$1" == "--status" ]]; then
    MODE="STATUS"

elif [[ "$1" == "--monitor" ]]; then
    MODE="MONITOR"

elif [[ "$1" == "--install" ]]; then
    MODE="INSTALL"
    BOOT_PWM="$2"
    # Validate Integer and Range (0-255)
    if ! [[ "$BOOT_PWM" =~ ^[0-9]+$ ]] || [ "$BOOT_PWM" -lt 0 ] || [ "$BOOT_PWM" -gt 255 ]; then
        echo "Error: --install requires a default boot fan speed (0-255)."
        echo "Usage: sudo ./manual-fan-control.sh --install 128"
        exit 1
    fi

elif [[ "$1" == "--uninstall" ]]; then
    MODE="UNINSTALL"

else
    cat <<EOF
Usage: $0
  --enable          | Set fan to manual control
  --disable         | Set fan to kernel control
  --pwm <0-255>     | Set fan pwm speed (manual control only)
  --status          | View present fan details
  --monitor         | Get live fan data feed (CTRL-C to exit)
  --install <0-255> | Install systemd service to boot with manual fan at constant speed
  --uninstall       | Disable and delete systemd service
EOF
    exit 1
fi

# --- 3. Helper Function: Find Fan PWM Path ---
get_pwm_path() {
    for h in /sys/class/hwmon/hwmon*; do
        if [ -f "$h/pwm1" ]; then
            echo "$h" 
            return 0
        fi
    done
    return 1
}

# --- 4. Logic Implementation ---

# --- ACTION: INSTALL SERVICE ---
if [[ "$MODE" == "INSTALL" ]]; then
    echo "------------------------------------------------"
    echo "INSTALLING SYSTEMD SERVICE"
    echo "------------------------------------------------"
    
    # 1. Copy script to /usr/local/bin if not already there or if different
    CURRENT_SCRIPT=$(realpath "$0")
    if [[ "$CURRENT_SCRIPT" != "$SCRIPT_INSTALL_PATH" ]]; then
        echo "Copying script to $SCRIPT_INSTALL_PATH..."
        cp "$CURRENT_SCRIPT" "$SCRIPT_INSTALL_PATH"
        chmod +x "$SCRIPT_INSTALL_PATH"
    else
        echo "Script is already in $SCRIPT_INSTALL_PATH."
    fi

    # 2. Create Service File
    echo "Creating service file at $SERVICE_PATH..."
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Manual Fan Control Service
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SCRIPT_INSTALL_PATH --enable
ExecStart=$SCRIPT_INSTALL_PATH --pwm $BOOT_PWM
ExecStop=$SCRIPT_INSTALL_PATH --disable

[Install]
WantedBy=multi-user.target
EOF

    # 3. Enable and Start
    echo "Reloading systemd daemon..."
    systemctl daemon-reload
    echo "Enabling $SERVICE_NAME..."
    systemctl enable "$SERVICE_NAME"
    echo "Starting $SERVICE_NAME (Setting fan to $BOOT_PWM)..."
    systemctl start "$SERVICE_NAME"
    
    echo "Success! Service installed and running."
    exit 0
fi

# --- ACTION: UNINSTALL SERVICE ---
if [[ "$MODE" == "UNINSTALL" ]]; then
    echo "------------------------------------------------"
    echo "UNINSTALLING SYSTEMD SERVICE"
    echo "------------------------------------------------"
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "Stopping service..."
        systemctl stop "$SERVICE_NAME"
    fi
    
    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        echo "Disabling service..."
        systemctl disable "$SERVICE_NAME"
    fi
    
    if [ -f "$SERVICE_PATH" ]; then
        echo "Removing service file $SERVICE_PATH..."
        rm "$SERVICE_PATH"
        systemctl daemon-reload
        echo "Success: Service uninstalled."
    else
        echo "Service file not found. Nothing to uninstall."
    fi
    
    echo "Note: The script at $SCRIPT_INSTALL_PATH was NOT removed."
    exit 0
fi

# --- STANDARD MODES (Enable, Disable, PWM, Monitor, Status) ---
FOUND_ZONE=false

for zone in /sys/class/thermal/thermal_zone*; do
    if [ -f "$zone/type" ]; then
        type=$(cat "$zone/type")
        if [[ "$type" == "soc-thermal" ]] || [[ "$type" == "cpu-thermal" ]]; then
            FOUND_ZONE=true
            
            # --- MONITOR ---
            if [[ "$MODE" == "MONITOR" ]]; then
                FAN_DIR=$(get_pwm_path)
                if [ -z "$FAN_DIR" ]; then echo "Error: Fan controller not found"; exit 1; fi

                echo "Monitoring Fan and Temp... (Ctrl+C to stop)"
                echo "Zone: $zone ($type)"
                echo "Fan Interface: $FAN_DIR"
                echo "----------------------------------------------------"
                printf "%-10s %-10s %-10s %-10s\n" "Time" "Temp(C)" "PWM" "RPM"
                echo "----------------------------------------------------"
                while true; do
                    TEMP_RAW=$(cat "$zone/temp"); TEMP_C=$((TEMP_RAW / 1000))
                    PWM=$(cat "$FAN_DIR/pwm1")
                    if [ -f "$FAN_DIR/fan1_input" ]; then RPM=$(cat "$FAN_DIR/fan1_input"); else RPM="N/A"; fi
                    printf "%-10s %-10s %-10s %-10s\n" "$(date +%H:%M:%S)" "$TEMP_C" "$PWM" "$RPM"
                    sleep 1
                done
                exit 0
            fi

            # --- STATUS ---
            if [[ "$MODE" == "STATUS" ]]; then
                echo "------------------------------------------------"
                echo "SYSTEM FAN STATUS"
                echo "------------------------------------------------"
                echo "Thermal Zone Found : $zone"
                echo "Zone Type          : $type"
                echo "Current Policy     : $(cat "$zone/policy")"
                FAN_DIR=$(get_pwm_path)
                if [ -n "$FAN_DIR" ]; then
                    echo "Fan Control Path   : $FAN_DIR/pwm1"
                    echo "Current PWM Value  : $(cat "$FAN_DIR/pwm1")"
                    if [ -f "$FAN_DIR/fan1_input" ]; then echo "Current RPM        : $(cat "$FAN_DIR/fan1_input")"; fi
                else
                    echo "Fan Control Path   : [NOT FOUND]"
                fi
                # Check Service Status
                if systemctl is-active --quiet manual-fan.service; then
                    echo "Systemd Service    : Active (Running)"
                else
                    echo "Systemd Service    : Inactive"
                fi
                echo "------------------------------------------------"
                exit 0
            fi

            # --- SET PWM ---
            if [[ "$MODE" == "SET_PWM" ]]; then
                CURRENT_POLICY=$(cat "$zone/policy")
                if [[ "$CURRENT_POLICY" == "step_wise" ]]; then
                    echo "Error: Kernel is currently controlling the fan (policy: step_wise)."
                    echo "Run '$0 --enable' first to switch to user_space."
                    exit 1
                elif [[ "$CURRENT_POLICY" == "user_space" ]]; then
                    FAN_DIR=$(get_pwm_path)
                    if [ -z "$FAN_DIR" ]; then echo "Error: Fan controller not found"; exit 1; fi
                    echo "$PWM_VALUE" > "$FAN_DIR/pwm1"
                    echo "Success: Set fan to pwm mode $PWM_VALUE."
                    exit 0
                else
                    echo "Error: Unknown policy '$CURRENT_POLICY'."
                    exit 1
                fi
            
            # --- SET POLICY (Enable/Disable) ---
            elif [[ "$MODE" == "SET_POLICY" ]]; then
                echo "------------------------------------------------"
                echo "Found CPU thermal zone at $zone ($type)"
                echo "Setting policy to $TARGET_POLICY..."
                echo "$TARGET_POLICY" > "$zone/policy"
                if [[ "$(cat "$zone/policy")" == "$TARGET_POLICY" ]]; then
                    echo "Success: Policy is now $TARGET_POLICY."
                else
                    echo "Error: Failed to set policy."
                    exit 1
                fi
            fi
        fi
    fi
done

if [ "$FOUND_ZONE" = false ]; then
    echo "Warning: No matching 'soc-thermal' or 'cpu-thermal' zones found."
    exit 1
fi

echo "------------------------------------------------"
exit 0
