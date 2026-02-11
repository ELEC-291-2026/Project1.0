# Reflow Oven Controller

## Hardware Overview
* Microcontroller: DE10-Lite/DE1-SoC

## Tasks
- Display Room temp and Oven temp on De-10 LCD, and display time and current state on lcd
- Speaker with 1 beep when in new state and 5 beeps when done

## Extra functionality 
  - Show a warning message whenever there is a very large deviation in temperatures(1%) <mark>->extra_features.py current threshold 15 degrees<mark>.
  - Change the oven activation so that we have to hold it down for 3 seconds to start the process(1~2%)
  - Add a progress indicator and progress bar(1~2%)<mark>-> code in progress_bar.txt waiting for implementation<mark>.
  - Short song, once done, instead of 5 beeps(3~5%)

## Extra stuff for Python
  - temp change (fahrenheit, kelvins, Cel)
  - Notification on phone
