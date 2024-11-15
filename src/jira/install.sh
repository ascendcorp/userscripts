#!/bin/bash

# Variables
SCRIPT_URL="https://raw.githubusercontent.com/ascendcorp/userscripts/refs/heads/main/src/jira/generate-changelog.sh"
SCRIPT_NAME="generate-changelog.sh"
INSTALL_DIR="/usr/local/bin"
ALIAS_NAME="changelog"

# Determine which shell configuration file to use
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
else
    SHELL_RC="$HOME/.bashrc"
fi

# Download the script
echo "Downloading script from $SCRIPT_URL..."
curl -O $SCRIPT_URL

# Make the script executable
echo "Making the script executable..."
chmod +x $SCRIPT_NAME

# Move the script to the install directory
echo "Moving the script to $INSTALL_DIR..."
sudo mv $SCRIPT_NAME $INSTALL_DIR/$ALIAS_NAME

# Add alias to shell configuration
echo "Adding alias to $SHELL_RC..."
echo "alias $ALIAS_NAME='$INSTALL_DIR/$ALIAS_NAME'" >> $SHELL_RC

# Reload shell configuration
echo "Reloading shell configuration..."
source $SHELL_RC

echo "Installation complete. You can now run the script using the command: $ALIAS_NAME"
