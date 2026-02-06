#!/bin/bash
set -e

# Build
zig build

# Start Server
./zig-out/bin/protomq-server &
SERVER_PID=$!
echo "Server started with PID $SERVER_PID"

sleep 2

# Run Discovery CLI
# Capture stderr since std.debug.print outputs there
echo "Running discovery..."
./zig-out/bin/protomq-cli discover --proto-dir schemas 2>&1 | tee discovery_output.txt

# Clean up
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null || true

# Check output content
# The debug output prints tags, not field names, so we look for the values
# Check for topic, message type, AND source code content (e.g., "package iot.sensor")
if grep -q "Services:" discovery_output.txt && \
   grep -q "SensorData" discovery_output.txt && \
   grep -q "sensor/data" discovery_output.txt && \
   grep -q "package iot.sensor" discovery_output.txt; then
    echo "Discovery Test Passed!"
else
    echo "Discovery Test Failed!"
    cat discovery_output.txt
    exit 1
fi
