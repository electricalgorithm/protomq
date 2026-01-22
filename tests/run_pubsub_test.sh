#!/bin/bash

# Pub/Sub Integration Test

echo "📦 Building server..."
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

echo "🧪 Running Python Pub/Sub Test..."
python3 tests/pubsub_test.py
EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "🎉 INTEGRATION TEST PASSED"
else
    echo "❌ INTEGRATION TEST FAILED"
    echo "--- Server Log ---"
    cat server.log
fi

kill $SERVER_PID 2>/dev/null
exit $EXIT_CODE
