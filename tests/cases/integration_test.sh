#!/bin/bash

# Integration test for ProtoMQ Server
# Tests the server with protomq-cli

set -e

echo "🧪 ProtoMQ Integration Test"
echo "================================"
echo ""

# Build the project
echo "📦 Building project..."
zig build
echo ""

# Start server in background
echo "🚀 Starting server..."
./zig-out/bin/protomq-server > server.log 2>&1 &
SERVER_PID=$!

# Give server time to start
sleep 1

# Check if server is running
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ Server failed to start"
    cat server.log
    exit 1
fi

echo "✓ Server started (PID: $SERVER_PID)"
echo ""

# Test: Wildcard Subscription and Match
echo "Test 1: Wildcard Subscription (+)"
echo "---------------------------------"

# Start subscriber in background
./zig-out/bin/protomq-cli subscribe -t "sensors/+" > sub.log 2>&1 &
SUB_PID=$!
sleep 1

# Publish to a matching topic
echo "📤 Publishing to 'sensors/temp'..."
./zig-out/bin/protomq-cli publish -t "sensors/temp" -m "22.5"

sleep 1

# Verify receipt
echo "🔍 Verifying receipt..."
if grep -q "22.5" sub.log; then
    echo "✅ Wildcard match test passed"
else
    echo "❌ Wildcard match test failed"
    echo "--- sub.log ---"
    cat sub.log
    kill $SUB_PID 2>/dev/null
    kill $SERVER_PID 2>/dev/null
    exit 1
fi
echo ""

# Cleanup
echo "🧹 Stopping server and clients..."
kill $SUB_PID 2>/dev/null
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null || true
echo ""

echo "🎉 All ProtoMQ integration tests passed!"
