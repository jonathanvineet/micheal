#!/bin/bash

echo "🔥 3D Printer API Test Script"
echo "============================="
echo ""

# Find the port
PORT=3000
if ! curl -s http://localhost:3000/api/ping > /dev/null 2>&1; then
    PORT=3001
    if ! curl -s http://localhost:3001/api/ping > /dev/null 2>&1; then
        echo "❌ Server not responding on port 3000 or 3001!"
        echo "Start the server with: npm run dev"
        exit 1
    fi
fi

echo "✅ Server running on port $PORT"
echo ""

# Test 1: Set bed temperature to 60°C
echo "Test 1: Setting bed temperature to 60°C (M140 S60)"
echo "------------------------------------------------"
echo "Sending request..."
RESPONSE=$(timeout 15 curl -s -X POST http://localhost:$PORT/api/printer/temperature \
  -H 'Content-Type: application/json' \
  -d '{"action":"bed","temp":60}')

echo "Response: $RESPONSE"
echo ""

if echo "$RESPONSE" | grep -q '"success":true'; then
    echo "✅ SUCCESS! Command sent to printer"
    echo "🔥 Check your printer - the bed should be heating to 60°C!"
else
    echo "❌ FAILED or TIMEOUT!"
    echo "Possible issues:"
    echo "  - Serial port /dev/ttyUSB0 not accessible"
    echo "  - Printer not responding"
    echo "  - Check server logs"
fi

echo ""
echo "---"
echo "Other tests you can try:"
echo ""
echo "# Turn off heaters:"
echo "curl -X POST http://localhost:$PORT/api/printer/temperature \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"action\":\"off\"}'"
echo ""
echo "# Set hotend to 200°C:"
echo "curl -X POST http://localhost:$PORT/api/printer/temperature \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"action\":\"hotend\",\"temp\":200}'"
echo ""
echo "# Read current temperature:"
echo "curl http://localhost:$PORT/api/printer/temperature"
