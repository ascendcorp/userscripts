#!/bin/sh

# Check if gsed is installed
if ! command -v gsed &> /dev/null; then
    echo "gsed is not installed. Please install it before running this script."
    exit 1
fi

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "git is not installed. Please install it before running this script."
    exit 1
fi

# Settings
BASE_URL="https://truemoney.atlassian.net"
API_URL="$BASE_URL/rest/api/2/issue"
CHANGELOG_FILE="CHANGELOG.md"
TARGET_BRANCH="master"

# Check if CHANGELOG.md exists
if [ ! -f "$CHANGELOG_FILE" ]; then
    echo "$CHANGELOG_FILE does not exist. Creating the file..."
    touch "$CHANGELOG_FILE"
    echo -e "# CHANGELOG\n\n" > "$CHANGELOG_FILE"
fi

# Select target branch
git fetch
git checkout "$TARGET_BRANCH"
git pull

# Prompt the user inputs
echo "Enter the new tag version: "
read tag_version

echo "Enter your Jira username (user@example.com): "
read username

echo "Enter your Jira API token (https://id.atlassian.com/manage-profile/security/api-tokens): "
read api_token

# Get the last tag
last_tag=$(git describe --tags `git rev-list --tags --max-count=1`)

# Get the Jira issue IDs
issue_ids=$(git log --oneline $last_tag..HEAD | grep '\[' | awk -F'[][]' '{print $2}' | sort -u)
echo "Issue ID list: $issue_ids"

# Prepare the new section of issues
new_section="## $tag_version\n\n"

while read issue_id; do
  # Make a GET request to the Jira API to get the issue for the issue ID
  url="$API_URL/$issue_id"
  title=$(curl -s -X GET -u "$username:$api_token" -H "Content-Type: application/json" -H "Accept: application/json" "$url" | jq -r '.fields.summary')

  if [ "$title" = null ]
  then
    title="Issue not found"
  fi

  # Remove the brackets from the title
  title=$(echo "$title" | sed -E 's/\[[^]]*\]//g' | sed 's/^[[:space:]]*//')
  
  # Append the a issue to the new section
  new_section="$new_section- [$issue_id]($BASE_URL/browse/$issue_id) $title\n"

  # Print the issue ID and issue title
  echo "$issue_id: $title"
done <<< "$issue_ids"

# Insert the new list at line 3 in the CHANGELOG.md file
gsed -i "3i $new_section" CHANGELOG.md
