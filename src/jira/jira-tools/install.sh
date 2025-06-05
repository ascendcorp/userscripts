#!/bin/sh

# Variables
SCRIPT_URL="https://raw.githubusercontent.com/ascendcorp/userscripts/refs/heads/main/src/jira/jira-tools/jira-tools.sh"
SCRIPT_NAME="jira-tools.sh"
INSTALL_DIR="/usr/local/bin"
TEMPLATES_DIR="/usr/local/share/jira-tools/templates"
ALIAS_NAME="jira"

# Determine which shell configuration file to use
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
    CURRENT_SHELL="zsh"
else
    SHELL_RC="$HOME/.bashrc"
    CURRENT_SHELL="bash"
fi

# Download the script
echo "Downloading script from $SCRIPT_URL..."
curl -O $SCRIPT_URL

# Make the script executable
echo "Making the script executable..."
chmod +x $SCRIPT_NAME

# Create templates directory
echo "Creating templates directory at $TEMPLATES_DIR..."
sudo mkdir -p $TEMPLATES_DIR

# Copy templates to the installation directory
echo "Copying templates..."
if [ -d "templates" ]; then
    sudo cp templates/* $TEMPLATES_DIR/
else
    echo "Warning: templates directory not found in current directory"
fi

# Move the script to the install directory
echo "Moving the script to $INSTALL_DIR..."
sudo mv $SCRIPT_NAME $INSTALL_DIR/$ALIAS_NAME

# Update script to use new templates location
sudo sed -i.bak "s|TEMPLATE_DIR=\"\$SCRIPT_DIR/templates\"|TEMPLATE_DIR=\"$TEMPLATES_DIR\"|" "$INSTALL_DIR/$ALIAS_NAME"

# Add alias to shell configuration
echo "Adding alias to $SHELL_RC..."
echo "alias $ALIAS_NAME='$INSTALL_DIR/$ALIAS_NAME'" >>$SHELL_RC

# Reload shell configuration only if in the correct shell
if [ "$SHELL" == "/bin/$CURRENT_SHELL" ]; then
    echo "Reloading shell configuration..."
    source $SHELL_RC
else
    echo "Please restart your terminal or run 'source $SHELL_RC' in your $CURRENT_SHELL shell to apply changes."
fi

echo "Installation complete. You can now run the script using the command: $ALIAS_NAME"
