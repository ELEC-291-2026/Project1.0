# Reflow Oven Controller

![Image](1.jpg)

## Hardware Overview
* Microcontroller: DE10-Lite/DE1-SoC
* Amplifier: OP07PC
* Capacitors: 2 10uF
* Thermocouple
* Keypad
* Resistor 330 Ohms
* Speaker CEM-1302
* Diode 1N4148
* N-channel MOSFET FQU13N06LS
* DC-to-DC Voltage Converter TCP7660
* Two buttons


## Specifications
* Selectable reflow profile parameters such as soak temperature, soak time, reflow
temperature, and reflow time using pushbuttons or switches and displayed on the LCD
* Display of temperature(s), running time, and reflow process current state on an
LCD
* Selectable large display of oven temperature with 7-
segment displays available on the DE10-Lite boards

* Start/Immediate Stop pushbutton.
  
* Temperature strip chart plot in degrees Celsius using the serial port attached to the processor and a
personal computer

* Sound feedback using speaker. Five beeps when the reflow process is
completed. Ten beeps when there is an error.

## Extra functionality 
  - Show a warning message whenever there is a very large deviation in temperatures
  - Change the oven activation so that we have to hold it down for 3 seconds to start the process
  - Add a progress indicator and progress bar
  - Settable songs with 2 octaves played once done

## Extra features for Python
  - Temp change in Fahrenheit, Kelvins, Celcius
  - Notification on phone

## EXTRA FINAL (the final features that made it to the end

# Microwave mode
- has a timer
- has different modes for different foods
- auto ends after timer
- shows timer on LCD
- times and temperatures are perfectly aliged to mimic a microwave
# Keyboard sound mode
- custom music note characters
- allows you to make song
# 2 songs you can pick
- 2 fully done songs that will play at the end when its done
- can chose between them  
# python cool graph
- shows prediction graph by taking in the parameters
- dynamically resizes based on current temp
- changes colour the hotter it is  
# discord messaging
- When the cook cycle elapses, members of the community will be notified on discord, so you can monitor your it from wherever you are

## LCD
- State 0: paramters on the 7segs, temperature of oven and time on the LCD
- State 1-5: oven temperature on the 7segs, and 2 screens on LCD: one parameters, one oven temperature/total time on first row, second row is progress bar and state running time and state number
