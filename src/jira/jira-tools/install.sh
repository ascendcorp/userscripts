#!/bin/sh

# Variables
SCRIPT_URL="https://raw.githubusercontent.com/ascendcorp/userscripts/refs/heads/main/src/jira/jira-tools/jira-cards.sh"
TEMPLATES_BASE_URL="https://raw.githubusercontent.com/ascendcorp/userscripts/refs/heads/main/src/jira/jira-tools/templates"
SCRIPT_NAME="jira-cards.sh"
INSTALL_DIR="/usr/local/bin"
TEMPLATES_DIR="/usr/local/share/jira-tools/templates"
ALIAS_NAME="jira-cards"

# List of template files to download
TEMPLATE_FILES="
api.template
caller.template
deps.template
diagram.template
integrate.template
perf.template
robot.template
"

# Download the script
echo "Downloading script from $SCRIPT_URL..."
curl -O $SCRIPT_URL

# Make the script executable
echo "Making the script executable..."
chmod +x $SCRIPT_NAME

# Create templates directory
echo "Creating templates directory at $TEMPLATES_DIR..."
sudo mkdir -p $TEMPLATES_DIR

# Download and install templates
echo "Downloading and installing templates..."
for template in $TEMPLATE_FILES; do
    echo "Downloading $template..."
    sudo curl -s "$TEMPLATES_BASE_URL/$template" -o "$TEMPLATES_DIR/$template"
    if [ $? -eq 0 ]; then
        echo "✓ Successfully installed $template"
    else
        echo "✗ Failed to download $template"
    fi
done

# Move the script to the install directory
echo "Moving the script to $INSTALL_DIR..."
sudo mv $SCRIPT_NAME $INSTALL_DIR/$ALIAS_NAME

# Update script to use new templates location
sudo sed -i.bak "s|TEMPLATE_DIR=\"\$SCRIPT_DIR/templates\"|TEMPLATE_DIR=\"$TEMPLATES_DIR\"|" "$INSTALL_DIR/$ALIAS_NAME"

# Add alias to shell configuration files if they exist
if [ -f "$HOME/.zshrc" ]; then
    echo "Adding alias to .zshrc..."
    grep -q "alias $ALIAS_NAME=" "$HOME/.zshrc" || echo "alias $ALIAS_NAME='$INSTALL_DIR/$ALIAS_NAME'" >>"$HOME/.zshrc"
fi

if [ -f "$HOME/.bashrc" ]; then
    echo "Adding alias to .bashrc..."
    grep -q "alias $ALIAS_NAME=" "$HOME/.bashrc" || echo "alias $ALIAS_NAME='$INSTALL_DIR/$ALIAS_NAME'" >>"$HOME/.bashrc"
fi

echo "Installation complete!"
echo "Please run one of the following commands to activate the alias in your current shell:"
echo "  For zsh: source ~/.zshrc"
echo "  For bash: source ~/.bashrc"
echo "Alternatively, you can start a new terminal session."
echo "After that, you can run the script using the command: $ALIAS_NAME"
