import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import serial
import sys
import math
from matplotlib.collections import LineCollection
import matplotlib.cm as cm

# Serial connection setup
ser = serial.Serial(
    port='COM5',
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
    bytesize=serial.EIGHTBITS,
)

# Global state
profile_received = False
profile_updated = False
xdata, ydata, target_data = [], [], []
temp_profile = []

# Configuration
GRAPH_WINDOW_SIZE = 50
SAMPLE_PERIOD = 0.2  # seconds per sample

# Reflow profile parameters (only the essentials we receive)
profile_params = {
    'soak_temp': 180,
    'soak_time': 90,
    'reflow_temp': 235,
    'reflow_time': 30,
}


def parse_profile_command(text):
    """Parse incoming profile commands from serial (format: PROFILE,soak_temp,soak_time,reflow_temp,reflow_time)"""
    global profile_updated, profile_received

    if not text.startswith("PROFILE,"):
        return False

    try:
        parts = text.split(',')
        
        # Values come as 4-digit BCD with last digit as tenths (e.g., "1800" = 180.0)
        profile_params['soak_temp'] = float(parts[1]) / 10.0
        profile_params['soak_time'] = float(parts[2]) / 10.0
        profile_params['reflow_temp'] = float(parts[3]) / 10.0
        profile_params['reflow_time'] = float(parts[4]) / 10.0

        profile_received = True
        profile_updated = True
        print(f"Profile received: Soak {profile_params['soak_temp']}°C for {profile_params['soak_time']}s, "
              f"Reflow {profile_params['reflow_temp']}°C for {profile_params['reflow_time']}s")
        return True

    except Exception as e:
        print(f"Error parsing profile: {e}")
        print(f"Received: {text}")
        return False


def generate_reflow_profile():
    """Generate temperature profile waypoints based on parameters"""
    
    # Fixed parameters
    ROOM_TEMP = 25
    PREHEAT_TEMP = 150
    PEAK_TEMP = 245
    HEATING_RATE = 2.5
    COOLING_RATE = 3
    
    # Calculate phase durations
    preheat_duration = (PREHEAT_TEMP - ROOM_TEMP) / HEATING_RATE
    t_preheat = preheat_duration
    
    soak_ramp = (profile_params['soak_temp'] - PREHEAT_TEMP) / HEATING_RATE
    t_soak_start = t_preheat + soak_ramp
    
    soak_hold = max(0, profile_params['soak_time'] - t_soak_start)
    t_soak_end = t_soak_start + soak_hold
    
    reflow_ramp = (profile_params['reflow_temp'] - profile_params['soak_temp']) / HEATING_RATE
    t_reflow = t_soak_end + reflow_ramp
    
    peak_ramp = (PEAK_TEMP - profile_params['reflow_temp']) / HEATING_RATE
    t_peak = t_reflow + peak_ramp
    
    reflow_hold = max(0, profile_params['reflow_time'] - peak_ramp)
    t_hold_end = t_peak + reflow_hold
    
    cooling = (PEAK_TEMP - ROOM_TEMP) / COOLING_RATE
    t_cool = t_hold_end + cooling

    # Build profile waypoints
    return [
        (0, ROOM_TEMP, "Preheat Start"),
        (t_preheat, PREHEAT_TEMP, "Preheat"),
        (t_soak_end, profile_params['soak_temp'], "Soak"),
        (t_reflow, profile_params['reflow_temp'], "Ramp to Reflow"),
        (t_peak, PEAK_TEMP, "Peak"),
        (t_hold_end, PEAK_TEMP, "Reflow Hold"),
        (t_cool, ROOM_TEMP, "Cooling")
    ]


def get_target_temp(sample_count):
    """Calculate target temperature for a given sample number"""
    elapsed_time = sample_count * SAMPLE_PERIOD

    for i in range(len(temp_profile) - 1):
        t1, temp1, _ = temp_profile[i]
        t2, temp2, state = temp_profile[i + 1]

        if t1 <= elapsed_time < t2:
            # Linear interpolation between waypoints
            progress = (elapsed_time - t1) / (t2 - t1)
            current_temp = temp1 + (temp2 - temp1) * progress
            return current_temp, state

    # After profile ends, return final state
    return temp_profile[-1][1], temp_profile[-1][2]


def data_gen():
    """Generator that yields temperature data from serial"""
    global profile_received, temp_profile
    sample_count = -1

    while True:
        text = ser.readline().decode().strip()
        
        # Debug: print what we received
        if text:
            print(f"Received: '{text}'")

        # Check if this is a profile command
        if parse_profile_command(text):
            temp_profile = generate_reflow_profile()
            continue

        # Wait for profile before processing temperature data
        if not profile_received:
            continue

        # Try to parse as temperature reading
        try:
            temperature = float(text)
            sample_count += 1
            yield sample_count, temperature
        except ValueError:
            continue


def update_plot(data):
    """Animation update function"""
    global profile_updated
    
    sample, temp = data

    # Add new data points
    xdata.append(sample)
    ydata.append(temp)
    
    target_temp, state = get_target_temp(sample)
    target_data.append(target_temp)

    # Update x-axis to show rolling window
    ax1.set_xlim(max(0, sample - GRAPH_WINDOW_SIZE), sample + 1)

    # Update plot lines
    line_actual.set_data(xdata, ydata)
    line_target.set_data(xdata, target_data)

    # Update title with current time and state
    elapsed = sample * SAMPLE_PERIOD
    ax1.set_title(f"Time: {elapsed:.1f}s | State: {state}")

    # Update prediction graph when profile changes
    if profile_updated and temp_profile:
        profile_updated = False
        
        # Clear waiting text
        ax1.clear()
        ax1.set_ylim(0, 260)
        ax1.set_xlim(max(0, sample - GRAPH_WINDOW_SIZE), sample + 1)
        ax1.set_xlabel("Time (samples)")
        ax1.set_ylabel("Temperature (°C)")
        ax1.grid(True, alpha=0.3)
        ax1.legend(loc='upper left')
        
        ax2.clear()
        ax2.set_xlabel("Time (s)")
        ax2.set_ylabel("Temperature (°C)")
        ax2.set_title("Full Reflow Profile")
        ax2.grid(True, alpha=0.3)
        
        # Generate prediction curve
        times = [t for t, _, _ in temp_profile]
        temps = [temp for _, temp, _ in temp_profile]
        
        # Re-create lines after clearing
        line_actual.set_data(xdata, ydata)
        line_target.set_data(xdata, target_data)
        ax1.add_line(line_actual)
        ax1.add_line(line_target)
        
        prediction_line.set_data(times, temps)
        ax2.add_line(prediction_line)
        ax2.set_xlim(0, max(times) if times else 1)
        ax2.set_ylim(0, 260)
        ax2.legend(loc='upper left')

    return line_actual, line_target, prediction_line


# Set up the plot with prediction graph
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))

# Main temperature graph
ax1.set_ylim(0, 260)
ax1.set_xlim(0, GRAPH_WINDOW_SIZE)
ax1.set_xlabel("Time (samples)")
ax1.set_ylabel("Temperature (°C)")
ax1.grid(True, alpha=0.3)
ax1.text(GRAPH_WINDOW_SIZE/2, 130, 'Waiting for profile...', 
         ha='center', va='center', fontsize=20, color='gray')

line_actual, = ax1.plot([], [], 'b-', linewidth=2, label="Actual Temperature")
line_target, = ax1.plot([], [], 'r--', linewidth=2, label="Target Temperature")
ax1.legend(loc='upper left')

# Prediction graph (full profile view)
ax2.set_xlabel("Time (s)")
ax2.set_ylabel("Temperature (°C)")
ax2.set_title("Full Reflow Profile")
ax2.set_xlim(0, 100)
ax2.set_ylim(0, 260)
ax2.grid(True, alpha=0.3)
ax2.text(50, 130, 'Waiting for profile...', 
         ha='center', va='center', fontsize=20, color='gray')
prediction_line, = ax2.plot([], [], 'r--', linewidth=2, label="Target Profile")

# Start the animation
print("=" * 50)
print("REFLOW PROFILE MONITOR")
print("=" * 50)
print("Waiting for profile data...")
print("Expected format: PROFILE,soak_temp,soak_time,reflow_temp,reflow_time")
print("Example: PROFILE,1800,0900,2350,0300 (values are 10x with decimal)")
print("         (means: 180.0°C, 90.0s, 235.0°C, 30.0s)")
print("=" * 50)

ani = animation.FuncAnimation(
    fig,
    update_plot,
    data_gen,
    interval=100,
    blit=False,
    cache_frame_data=False
)

plt.show()