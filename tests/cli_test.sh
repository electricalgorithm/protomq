#!/bin/bash

echo "📦 Building project..."
zig build
if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "🚀 Starting server..."
./zig-out/bin/protomq-server > server.log 2>&1 &
SERVER_PID=$!
sleep 1

# Check if running
if ! ps -p $SERVER_PID > /dev/null; then
    echo "❌ Server failed to start"
    cat server.log
    exit 1
fi

echo "👂 Starting Subscriber..."
./zig-out/bin/protomq-cli subscribe -t "cli/test" > sub.log 2>&1 &
SUB_PID=$!
sleep 1

echo "📤 Publishing message..."
./zig-out/bin/protomq-cli publish -t "cli/test" -m "HELLO_CLI"

sleep 1

echo "🔍 Verifying receipt..."
if grep -q "HELLO_CLI" sub.log; then
    echo "✅ CLI Integration Test Passed: Message received"
else
    echo "❌ test failed: Message not found in sub.log"
    echo "--- sub.log ---"
    cat sub.log
fi

# Cleanup
kill $SUB_PID 2>/dev/null
kill $SERVER_PID 2>/dev/null

if grep -q "HELLO_CLI" sub.log; then
    exit 0
else
    exit 1
fi
