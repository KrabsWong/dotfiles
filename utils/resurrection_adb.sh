#!/bin/bash

# resurrection adb by killing all of the current processes

echo "Searching for processes with executable name 'adb'..."
# Use pgrep adb to find PIDs of processes whose executable name is 'adb'
# pgrep directly outputs the PIDs
PIDS=$(pgrep adb)

if [ -z "$PIDS" ]; then
  echo "No running processes with executable name 'adb' found."
else
  # pgrep outputs PIDs separated by newlines. We can format them for display.
  FORMATTED_PIDS=$(echo $PIDS | tr '\n' ' ')
  echo "Found the following adb process PIDs: $FORMATTED_PIDS"
  echo "Terminating adb processes..."
  # Use xargs to pass the PIDs to the kill -9 command
  # kill -9 forcefully terminates the process [citation:1][citation:3][citation:4][citation:5]
  echo "$PIDS" | xargs kill -9
  # Check if kill was successful (optional, basic check)
  if pgrep adb > /dev/null; then
    echo "Warning: Some adb processes might still be running. Manual check recommended."
  else
    echo "adb processes terminated."
  fi
fi

echo "Starting adb server..."
# Start the adb server [citation:10]
adb start-server
# Check adb server status (optional)
adb devices > /dev/null
if [ $? -eq 0 ]; then
    echo "adb server started successfully."
else
    echo "Failed to start adb server. Please check manually."
fi


exit 0
