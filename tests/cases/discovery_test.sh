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
echo "Running discovery..."
./zig-out/bin/protomq-cli discover --proto-dir schemas > discovery_output.txt 2>&1 || true

# Clean up
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null || true

# Check output content
if grep -q "Services:" discovery_output.txt && \
   grep -q "SensorData" discovery_output.txt && \
   grep -q "sensor/data" discovery_output.txt && \
   grep -q "package iot.sensor" discovery_output.txt; then
    echo "Discovery Test Passed!"
    rm discovery_output.txt
else
    echo "Discovery Test Failed!"
    cat discovery_output.txt
    rm discovery_output.txt
    exit 1
fi
