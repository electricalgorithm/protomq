#!/bin/bash
set -euo pipefail

echo "=========================================="
echo " Admin Server Integration Test"
echo "=========================================="

echo "🔨 Building with Admin Server enabled..."
zig build -Dadmin_server=true

echo "🚀 Starting ProtoMQ server..."
./zig-out/bin/protomq-server &
SERVER_PID=$!

# Ensure server stops on exit
cleanup() {
    echo "🛑 Stopping server..."
    kill $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
    rm -f schemas/TestAdminSchema.proto
}
trap cleanup EXIT

# Wait for server to start
sleep 1

# Test 1: Unauthorized access
echo "🧪 Test: Unauthorized access"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/metrics)
if [ "$HTTP_CODE" -ne 401 ]; then
    echo "❌ Failed: Expected 401 for missing token, got $HTTP_CODE"
    exit 1
fi

# Test 2: GET /metrics
echo "🧪 Test: GET /metrics"
RESPONSE=$(curl -s -H "Authorization: Bearer admin_secret" http://127.0.0.1:8080/metrics)
if ! echo "$RESPONSE" | grep -q '"connections"'; then
    echo "❌ Failed: Invalid metrics response: $RESPONSE"
    exit 1
fi
echo "✓ Metrics retrieved successfully: $RESPONSE"

# Test 3: POST /api/v1/schemas
echo "🧪 Test: POST /api/v1/schemas"
cat <<EOF > test_payload.json
{
  "topic": "test/admin",
  "message_type": "TestAdminSchema",
  "proto_file_content": "syntax = \"proto3\";\nmessage TestAdminSchema {\n  int32 id = 1;\n}\n"
}
EOF

POST_RESPONSE=$(curl -s -d @test_payload.json -H "Authorization: Bearer admin_secret" http://127.0.0.1:8080/api/v1/schemas)
rm test_payload.json

if [ "$POST_RESPONSE" != "OK" ]; then
    echo "❌ Failed: Schema registration failed: $POST_RESPONSE"
    exit 1
fi
echo "✓ Schema registered successfully"

# Test 4: GET /api/v1/schemas
echo "🧪 Test: GET /api/v1/schemas"
GET_SCHEMAS_RESPONSE=$(curl -s -H "Authorization: Bearer admin_secret" http://127.0.0.1:8080/api/v1/schemas)
if ! echo "$GET_SCHEMAS_RESPONSE" | grep -q 'test/admin'; then
    echo "❌ Failed: Registered schema not found in response: $GET_SCHEMAS_RESPONSE"
    exit 1
fi
echo "✓ Registered schema validated"

echo "✅ Admin Server Integration Test Passed!"
