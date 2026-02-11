import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, time, math
from matplotlib.collections import LineCollection
import matplotlib.cm as cm
import requests    # Required for Discord notifications
import csv         # Required for Excel/CSV logging
import os          # Required for file handling
import xlsxwriter  # Required for professional Excel reports with charts

import serial
# configure the serial port
ser = serial.Serial(
    port='COM5',
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
   bytesize=serial.EIGHTBITS
)
ser.isOpen()

xsize=50
points=0

# --- Data Logging Setup ---
EXCEL_FILENAME = "microwave_thermal_report.xlsx"
LOG_FILENAME = "microwave_backup_log.csv"
GRAPH_FILENAME = "microwave_live_snapshot.png"

# Global list to store session data for the final Excel report
# Format: [timestamp, multimeter_temp, micro_temp, difference, status]
session_data = []

def init_logging():
    """Initializes the CSV backup file with headers"""
    with open(LOG_FILENAME, mode='w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(["Timestamp_Seconds", "Multimeter_Temp", "Micro_Temp", "Difference", "Status"])
    print(f"Initialized logging: {LOG_FILENAME}")

# Start fresh logging when the script runs
init_logging()

def generate_excel_report(file_path):
    """
    Generates a professional Excel (.xlsx) report from session_data 
    with an embedded comparison chart.
    """
    print(f"Generating professional Excel report: {file_path}")
    workbook = xlsxwriter.Workbook(file_path)
    worksheet = workbook.add_worksheet("Thermal Data")
    
    # Define styles
    header_format = workbook.add_format({'bold': True, 'bg_color': '#D9EAD3', 'border': 1})
    data_format = workbook.add_format({'border': 1})
    
    # Write Headers
    headers = ["Time (s)", "Multimeter Temp (C°)", "Microcontroller Temp (C°)", "Difference (C°)", "Status"]
    for col, header in enumerate(headers):
        worksheet.write(0, col, header, header_format)
        
    # Write Data Rows
    for row_idx, row_data in enumerate(session_data):
        for col_idx, value in enumerate(row_data):
            worksheet.write(row_idx + 1, col_idx, value, data_format)
    
    # Create the Comparison Chart
    chart = workbook.add_chart({'type': 'line'})
    
    # Configure Multimeter Series
    chart.add_series({
        'name':       '=Thermal Data!$B$1',
        'categories': ['Thermal Data', 1, 0, len(session_data), 0],
        'values':     ['Thermal Data', 1, 1, len(session_data), 1],
        'line':       {'color': 'red'},
    })
    
    # Configure Microcontroller Series
    chart.add_series({
        'name':       '=Thermal Data!$C$1',
        'values':     ['Thermal Data', 1, 2, len(session_data), 2],
        'line':       {'color': 'blue'},
    })
    
    # Add chart title and labels
    chart.set_title({'name': 'Multimeter vs Microcontroller Correlation'})
    chart.set_x_axis({'name': 'Time (Seconds)'})
    chart.set_y_axis({'name': 'Temperature (°C)'})
    chart.set_style(10) # Clean modern style
    
    # Insert the chart into the worksheet
    worksheet.insert_chart('G2', chart, {'x_scale': 1.5, 'y_scale': 2.0})
    
    workbook.close()
    print("✅ Excel report created successfully!")

# --- Smart Notification Settings ---
DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/1471005567177986182/jn6fy27IzxZ0d9MfQwmBaPWUp83ynQLdEiD4y9NGUPayPYACDkOPIJjouZMTopHHVq_R"

def send_notification(message, file_paths=None):
    """
    Sends a notification to Discord. 
    Can handle plain text or text + multiple file attachments.
    """
    print(f"Triggering Notification: {message}")
    
    if "discord.com" in DISCORD_WEBHOOK_URL:
        try:
            payload = {"content": message}
            
            # Prepare files list if paths are provided
            files_dict = {}
            if file_paths:
                # Handle single path string or list of paths
                if isinstance(file_paths, str):
                    file_paths = [file_paths]
                
                # Zip up all existing files to send
                for i, path in enumerate(file_paths):
                    if os.path.exists(path):
                        # We use 'file1', 'file2', etc. as keys for Discord
                        files_dict[f'file{i}'] = (os.path.basename(path), open(path, 'rb'))

            if files_dict:
                # Send with multiple attachments
                response = requests.post(DISCORD_WEBHOOK_URL, data=payload, files=files_dict)
                # Important: Close files after sending
                for key, val in files_dict.items():
                    val[1].close()
            else:
                # Send text only
                response = requests.post(DISCORD_WEBHOOK_URL, json=payload)
                
            # HTTP 204 or 200 means "Success" in the web world
            if response.status_code in [200, 204]:
                print("✅ Successfully sent notification to Discord!")
            else:
                print(f"❌ Failed to send notification. Error: {response.status_code}")
        except Exception as e:
            print(f"Error sending notification: {e}")

# Default reflow profile parameters (will be updated from serial)
profile_params = {
    'preheat_temp': 150,      # °C
    'preheat_time': 30,       # seconds
    'soak_temp': 140,         # °C
    'soak_time': 150,          # seconds (total time at end of soak)
    'reflow_temp': 235,       # °C
    'reflow_time': 30,        # seconds above reflow
    'peak_temp': 240,         # °C
    'heating_rate': 1,      # °C/s - maximum heating rate
    'cooling_rate': 1         # °C/s - cooling rate
}

profile_updated = False

profile_received = False

def parse_profile_command(text):
    global profile_updated, profile_received
    if text.startswith("PROFILE,"):
        try:
            parts = text.split(',')
            profile_params['soak_temp'] = float(parts[1])
            profile_params['soak_time'] = float(parts[2])
            profile_params['reflow_temp'] = float(parts[3])
            profile_params['reflow_time'] = float(parts[4])
            profile_updated = True
            profile_received = True  # Add this
            print(f"Profile updated and ready to start!")
            return True
        except Exception as e:
            print(f"Error parsing profile command: {e}")
            return False
    return False

def generate_reflow_profile():
    """Generate reflow profile waypoints based on current parameters - physics-based timing"""
    
    # Calculate time points based on temperature deltas and heating rates
    t0 = 0
    
    # Preheat: 25°C → preheat_temp
    preheat_duration = (profile_params['preheat_temp'] - 21) / profile_params['heating_rate']
    t1 = t0 + preheat_duration
    
    # Soak ramp: preheat_temp → soak_temp
    soak_ramp_duration = (profile_params['soak_temp'] - profile_params['preheat_temp']) / profile_params['heating_rate']
    t2_ramp = t1 + soak_ramp_duration
    
    # Hold at soak temp until soak_time is reached (if needed)
    soak_hold_duration = max(0, profile_params['soak_time'] - t2_ramp)
    t2_hold = t2_ramp + soak_hold_duration
    
    # Ramp to reflow: soak_temp → reflow_temp (DYNAMICALLY CALCULATED based on temp difference)
    ramp_to_reflow_duration = (profile_params['reflow_temp'] - profile_params['soak_temp']) / profile_params['heating_rate']
    t3 = t2_hold + ramp_to_reflow_duration
    
    # Ramp to peak: reflow_temp → peak_temp (DYNAMICALLY CALCULATED)
    ramp_to_peak_duration = (profile_params['peak_temp'] - profile_params['reflow_temp']) / profile_params['heating_rate']
    t4 = t3 + ramp_to_peak_duration
    
    # Hold at peak for remaining reflow_time
    reflow_hold_duration = max(0, profile_params['reflow_time'] - ramp_to_peak_duration)
    t5 = t4 + reflow_hold_duration
    
    # Cooling: peak_temp → 25°C
    cooling_duration = (profile_params['peak_temp'] - 25) / profile_params['cooling_rate']
    t6 = t5 + cooling_duration
    
    profile = [
        (t0, 25, "Preheat Start"),
        (t1, profile_params['preheat_temp'], "Preheat"),
        (t2_hold, profile_params['soak_temp'], "Soak"),
        (t3, profile_params['reflow_temp'], "Ramp to Reflow"),
        (t4, profile_params['peak_temp'], "Peak"),
        (t5, profile_params['peak_temp'], "Reflow Hold"),
        (t6, 25, "Cooling")
    ]
    
    return profile

temp_profile = generate_reflow_profile()

def get_target_temp(t_samples):
    """Get target temperature for given time in samples (200ms intervals)"""
    t_seconds = t_samples * 0.25  # Convert samples to seconds
    
    # Find which segment we're in
    for i in range(len(temp_profile) - 1):
        t1, temp1, state1 = temp_profile[i]
        t2, temp2, state2 = temp_profile[i + 1]
        
        if t1 <= t_seconds < t2:
            # Linear interpolation
            ratio = (t_seconds - t1) / (t2 - t1) if t2 != t1 else 0
            target = temp1 + (temp2 - temp1) * ratio
            # Return the state we're heading towards for better clarity
            return target, state2
    
    # If we've reached or passed the last waypoint
    return temp_profile[-1][1], temp_profile[-1][2]

def get_state_color(state):
    """Return color for each state"""
    colors = {
        "Preheat Start": 'lightblue',
        "Preheat": 'lightyellow',
        "Soak": 'lightgreen',
        "Ramp to Reflow": 'wheat',
        "Peak": 'lightcoral',
        "Reflow Hold": 'salmon',
        "Cooling": 'lightgray'
    }
    return colors.get(state, 'white')

def data_gen():
    global profile_received
    t = data_gen.t
    
    # Wait for profile
    while not profile_received:
        strin = ser.readline()
        text = strin.decode('ascii').strip()
        parse_profile_command(text)
    
    print("Profile received! Starting acquisition...")
    while True:
        strin = ser.readline()
        text = strin.decode('ascii').strip()
        
        # Check if it's a profile command
        if parse_profile_command(text):
            global temp_profile
            temp_profile = generate_reflow_profile()
            # Update the full profile view when profile changes
            update_full_profile_view()
            continue  # Don't yield this, get next temperature reading
        
        try:
            # --- Multi-Temperature Parsing ---
            # Handles "Temp1, Temp2, Difference" or a single "Temp"
            parts = text.split(',')
            
            # Extract values based on what the serial sent
            if len(parts) >= 2:
                # Format: Temp1 (Multimeter), Temp2 (Micro), [Diff]
                multi_val = float(parts[0])
                micro_val = float(parts[1])
                diff_val = float(parts[2]) if len(parts) > 2 else (multi_val - micro_val)
            else:
                # Fallback for single-value stream
                micro_val = float(text)
                multi_val = profile_params.get('soak_temp', 0) # Use target as reference if only 1 value
                diff_val = multi_val - micro_val

            # --- The "Secret Handshake" (Sentinel Value Detection) ---
            # The 8051 sends 999.9 degrees when the timer hits zero.
            if micro_val == 999.9:
                # 1. Capture the current Matplotlib live chart as a backup image
                plt.savefig(GRAPH_FILENAME)
                print(f"Live graph snapshot saved: {GRAPH_FILENAME}")
                
                # 2. Build the high-tier professional Excel report
                generate_excel_report(EXCEL_FILENAME)

                # 3. Send BOTH the professional Excel file and the live graph PNG to Discord
                send_notification(
                    "@here 📊 **Process Complete!** Final Lab Report and Correlation Chart generated.", 
                    file_paths=[EXCEL_FILENAME, GRAPH_FILENAME]
                )
                
                # Skip plotting the secret code
                continue 
            
            # --- Real-Time Data Storage ---
            t_seconds = (t + 1) * 0.25
            _, current_state = get_target_temp(t + 1)
            
            # Store in memory for the final Excel report
            session_data.append([t_seconds, multi_val, micro_val, diff_val, current_state])
            
            # Append to CSV backup log for safety
            with open(LOG_FILENAME, mode='a', newline='') as file:
                writer = csv.writer(file)
                writer.writerow([f"{t_seconds:.1f}", multi_val, micro_val, diff_val, current_state])
                
            t += 1
            # Plot the microcontroller value on the live graph
            yield t, micro_val
        except:
            # If not a valid temperature, skip
            continue

def run(data):
    # update the data
    t, y = data
    if t > -1:
        xdata.append(t)
        ydata.append(y)
        
        # Calculate target temperature and state
        target_temp, current_state = get_target_temp(t)
        target_data.append(target_temp)
        
        if t > xsize:  # Scroll to the left.
            ax1.set_xlim(t - xsize, t)
            # ax2 stays zoomed out to show full profile
        
        # Calculate time in seconds for display
        t_seconds = t * 0.25
        
        ax1.set_title(f"Reflow Soldering  |  Time: {t_seconds:.1f}s  |  State: {current_state}  |  Samples: {t}")
        
        delta = y - target_temp
        text.set_text(f"Temp: {y:.2f}°C  Target: {target_temp:.2f}C  Δ: {delta:+.2f}°C")

        window = 10
        if len(ydata) >= window:
            avg = np.mean(ydata[-window:])
            std = np.std(ydata[-window:])
            stats_text.set_text(f"Avg: {avg:.2f}C  σ: {std:.2f}C")

        if len(xdata) > 1:
            pts = np.array([xdata, ydata]).T.reshape(-1, 1, 2)
            segs = np.concatenate([pts[:-1], pts[1:]], axis=1)

            segments.set_segments(segs)
            segments.set_array(np.array(ydata[:-1]))

            # manual y autoscale with margin (top plot only)
            ymin = min(min(ydata), min(target_data))
            ymax = max(max(ydata), max(target_data))
            margin = 0.2 * (ymax - ymin if ymax != ymin else 1)
            ax1.set_ylim(ymin - margin, ymax + margin)

        # Update target temperature line (bottom plot)
        target_line.set_data(xdata, target_data)
        actual_line.set_data(xdata, ydata)
        
        # Draw state regions
        draw_state_regions(ax2, t)

    return segments, text, target_line, actual_line

def update_full_profile_view():
    """Update the bottom plot to show the complete profile"""
    profile_x = []
    profile_y = []
    
    for i in range(len(temp_profile)):
        t_sec, temp, _ = temp_profile[i]
        t_samples = t_sec / 0.2
        profile_x.append(t_samples)
        profile_y.append(temp)
    
    full_profile_line.set_data(profile_x, profile_y)
    
    # Set x-axis to show entire profile with some padding
    if profile_x:
        max_time = max(profile_x)
        ax2.set_xlim(0, max_time * 1.1)  # 10% padding on the right

def draw_state_regions(ax, current_t):
    """Draw colored regions for each state"""
    # Clear previous patches
    for patch in list(ax.patches):
        patch.remove()
    
    for i in range(len(temp_profile) - 1):
        t1_sec, _, state = temp_profile[i]
        t2_sec, _, _ = temp_profile[i + 1]
        
        t1_samples = t1_sec / 0.2
        t2_samples = t2_sec / 0.2
        
        color = get_state_color(state)
        ax.axvspan(t1_samples, t2_samples, alpha=0.2, color=color)

def on_close_figure(event):
    sys.exit(0)

data_gen.t = -1

# Create figure with 2 subplots
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 9), sharex=False)  # sharex=False for independent x-axes
fig.canvas.mpl_connect('close_event', on_close_figure)

# Top plot: Actual temperature with gradient (zoomed, scrolling window)
cmap = cm.plasma
norm = plt.Normalize(15, 50)   # expected temperature range

segments = LineCollection([], cmap=cmap, norm=norm, linewidth=2)
ax1.add_collection(segments)

ax1.set_ylim(5, 50)
ax1.set_xlim(0, xsize)
ax1.grid(True, which="both", linestyle="--", alpha=0.5)
ax1.tick_params(axis='both', labelsize=10)
ax1.set_ylabel("Temperature (C)")
ax1.set_title("Temperature over Time")
ax1.margins(y=0.2)

xdata, ydata = [], []
target_data = []

text = ax1.text(0.0, 1.06, "", transform=ax1.transAxes)
stats_text = ax1.text(0.0, 1.02, "", transform=ax1.transAxes)

# Bottom plot: Full profile view (zoomed out to show entire reflow cycle)
ax2.set_ylim(0, 260)

# Calculate initial x-axis range based on profile
initial_profile_time = temp_profile[-1][0] / 0.2  # Convert to samples
ax2.set_xlim(0, initial_profile_time * 1.1)

ax2.grid(True, which="both", linestyle="--", alpha=0.5)
ax2.tick_params(axis='both', labelsize=10)
ax2.set_xlabel("Time (samples @ 250ms)")
ax2.set_ylabel("Temperature (C)")
ax2.set_title("Complete Reflow Profile - Full View")

# Full profile line (dotted, shows complete future profile)
full_profile_line, = ax2.plot([], [], 'r:', linewidth=2, label='Target Profile', alpha=0.7)

# Target line (what we're following now)
target_line, = ax2.plot([], [], 'r--', linewidth=1.5, label='Target (current)', alpha=0.9)

# Actual temperature line
actual_line, = ax2.plot([], [], 'b-', linewidth=2, label='Actual', alpha=0.9)

ax2.legend(loc='upper left', fontsize=9)

# Initialize the full profile line
update_full_profile_view()

# Draw initial state regions
draw_state_regions(ax2, 0)

plt.tight_layout()

# Print instructions
print("-" * 60)
print("REFLOW SOLDERING PROFILE MONITOR")
print("-" * 60)
print("Send profile via serial in format:")
print("PROFILE,soak_temp,soak_time,reflow_temp,reflow_time[,peak_temp][,heating_rate][,cooling_rate]")
print("\nExample: PROFILE,180,90,235,30")
print("  - Soak: 180°C for 90s total")
print("  - Reflow: 235°C for 30s")
print("-" * 60)

# Important: Although blit=True makes graphing faster, we need blit=False to prevent
# spurious lines to appear when resizing the stripchart.
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()