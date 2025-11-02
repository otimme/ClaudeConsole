#!/bin/bash

echo "PS4 Controller Fix Script"
echo "========================="
echo ""
echo "This script will help fix PS4 controller recognition issues."
echo ""

# Get the controller's Bluetooth address
CONTROLLER_ADDRESS="84:17:66:63:A1:98"

echo "Step 1: Disconnecting current controller..."
blueutil --disconnect $CONTROLLER_ADDRESS 2>/dev/null

echo "Step 2: Please do the following:"
echo "  1. Hold the PS button for 10 seconds to turn OFF the controller"
echo "  2. Press the reset button on the back with a paperclip for 5 seconds"
echo ""
read -p "Press Enter when done..."

echo ""
echo "Step 3: Putting controller in pairing mode:"
echo "  - Hold PS + Share buttons together"
echo "  - The light bar should flash white rapidly"
echo ""
read -p "Press Enter when the light is flashing..."

echo ""
echo "Step 4: Reconnecting..."
blueutil --connect $CONTROLLER_ADDRESS 2>/dev/null

echo ""
echo "Step 5: Testing connection..."
sleep 2

# Check if connected
if system_profiler SPBluetoothDataType | grep -q "DUALSHOCK 4 Wireless Controller"; then
    echo "✅ Controller connected via Bluetooth!"
    echo ""
    echo "Now please:"
    echo "1. Open ClaudeConsole from Xcode (press ⌘R)"
    echo "2. Click the PS4 button in the bottom toolbar"
    echo "3. Press controller buttons to test"
else
    echo "❌ Controller not found. Please try:"
    echo "1. Connect via USB cable first"
    echo "2. Once recognized, disconnect USB"
    echo "3. Then try Bluetooth pairing again"
fi