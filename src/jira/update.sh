#!/bin/sh

# Variables
SCRIPT_URL="https://raw.githubusercontent.com/ascendcorp/userscripts/refs/heads/main/src/jira/generate-changelog.sh"
SCRIPT_NAME="generate-changelog.sh"
INSTALL_DIR="/usr/local/bin"

# Download the updated script
echo "Downloading updated script from $SCRIPT_URL..."
curl -O $SCRIPT_URL

# Make the script executable
echo "Making the script executable..."
chmod +x $SCRIPT_NAME

# Replace the old script with the updated one
echo "Updating the script in $INSTALL_DIR..."
sudo mv $SCRIPT_NAME $INSTALL_DIR/$SCRIPT_NAME

echo "Update complete. The script has been updated to the latest version."