#!/bin/sh

BASE_URL="https://truemoney.atlassian.net"
SCRIPT_DIR=$(dirname "$0")
TEMPLATE_DIR="$SCRIPT_DIR/templates"

create_jira_ticket() {
    original_name="$1"
    type="$2"
    service="$3"
    description="$4"
    prefix="${5:-}"

    if [ "$type" = "api" ]; then
        name="create api for ${original_name}"
    else
        name="$original_name"
    fi

    if [ -n "$prefix" ]; then
        summary="${prefix}[${service}] ${name}"
    else
        summary="[${service}] ${name}"
    fi

    formatted_description=""
    case "$type" in
    "api")
        if [ -f "$TEMPLATE_DIR/$type.template" ]; then
            template=$(cat "$TEMPLATE_DIR/$type.template")
            merged_description=$(echo "$template" | jq --arg name "$original_name" --arg service "$service" '.Name = $name | .Service = $service')
            formatted_description=$(format_api_description "$merged_description" | jq -sR .)
        else
            formatted_description=$(echo "Type: $type\nService: $service" | jq -sR .)
        fi
        ;;
    *)
        if [ -n "$description" ]; then
            formatted_description=$(format_description "$description" | jq -sR .)
        else
            formatted_description=$(echo "Type: $type\nService: $service" | jq -sR .)
        fi
        ;;
    esac

    json_payload=$(
        cat <<EOF
{
    "fields": {
        "project": {
            "key": "$PROJECT_KEY"
        },
        "summary": "$summary",
        "description": ${formatted_description},
        "issuetype": {
            "name": "Task"
        },
        "customfield_15626": {
            "id": "$TMN_SCRUM_TEAM"
        },
        "customfield_10008": "$EPIC_KEY"
    }
}
EOF
    )

    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Basic $(printf "%s:%s" "$JIRA_USERNAME" "$JIRA_TOKEN" | base64)" \
        -d "$json_payload" \
        "$BASE_URL/rest/api/2/issue")

    if echo "$response" | jq -e '.key' >/dev/null; then
        ticket_key=$(echo "$response" | jq -r '.key')
        echo "Created ticket $ticket_key: $summary under epic $EPIC_KEY"
    else
        echo "Error creating ticket: $summary"
        echo "Response: $response"
    fi
}

format_description() {
    local desc="$1"
    if echo "$desc" | jq -e . >/dev/null 2>&1; then
        # If input is valid JSON
        local dod_items=$(echo "$desc" | jq -r '.DOD | join("\n")')
        local note=$(echo "$desc" | jq -r '.Note // empty')
        local output="${dod_items}"

        if [ -n "$note" ]; then
            output="${output}\n\n*Note:* ${note}"
        fi

        # Output without quotes or escaping
        printf '%s' "$output"
    else
        # If input is plain text, treat it as is
        printf '%s' "$desc"
    fi
}

if [ "$1" = "deps" ]; then

    services="
    acw-mf-api-gateway-node
    acw-mf-auth-service-node
    acw-mf-cms-service-node
    acw-mf-investment-platform
    acw-core-backoffice-web
    acw-core-bfauth-service-node
    acw-core-bof-gateway-node
    acw-mf-api-gateway
    acw-core-auth-service
    acw-core-cms-service
  "

    printf "Use TAB to select multiple services, ENTER to confirm\n"
    selected=$(printf "%s" "$services" | tr ' ' '\n' | grep -v '^$' |
        fzf --multi --header="Select services to upgrade (TAB to select, ENTER to confirm)" \
            --preview 'echo "Selected service: {}"')
    if [ -z "$selected" ]; then
        echo "No services selected. Exiting."
        exit 1
    fi

    read -r -p "Enter sprint name/number: " sprint
    if [ -z "$sprint" ]; then
        echo "Sprint cannot be empty. Exiting."
        exit 1
    fi

    if [ -z "$TMN_SCRUM_TEAM" ]; then
        printf "Select TMN Scrum Team (Enter the number):\n"
        printf "1) Lumi\n"
        read -r team_choice

        case "$team_choice" in
        1)
            TMN_SCRUM_TEAM="20150"
            ;;
        *)
            echo "Invalid team selection"
            exit 1
            ;;
        esac
    fi

    EPIC_KEY="WE230007-523"
    PROJECT_KEY=$(echo "$EPIC_KEY" | cut -d'-' -f1)

    echo "Creating tickets for selected services:"
    echo "$selected" | while read -r svc; do
        echo "- $svc"
        if [ -f "$TEMPLATE_DIR/deps.template" ]; then
            template=$(cat "$TEMPLATE_DIR/deps.template")
            description=$(echo "$template" | jq --arg name "bi-weekly upgrade dependency sprint $sprint" --arg service "$svc" '. | del(.Name, .Service) | .DOD = ["h2. Dependencies Upgrade", ""] + .DOD + ["", "*Note:* " + .Note]')
        else
            echo "Warning: deps.template not found"
            description="{}"
        fi

        create_jira_ticket \
            "bi-weekly upgrade dependency sprint $sprint" \
            "task" \
            "$svc" \
            "$description"
    done
    exit 0
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 <path-to-config-file>"
    echo "Example: $0 ./cards.json"
    exit 1
fi

CONFIG_FILE="$1"

if [ -z "$JIRA_USERNAME" ]; then
    printf "Enter your Jira username (email):\n"
    read -r JIRA_USERNAME
fi

if [ -z "$JIRA_TOKEN" ]; then
    printf "Enter your Jira API token:\n"
    read -r JIRA_TOKEN
fi

if [ -z "$TMN_SCRUM_TEAM" ]; then
    printf "Select TMN Scrum Team (Enter the number):\n"
    printf "1) Lumi\n"
    read -r team_choice

    case "$team_choice" in
    1)
        TMN_SCRUM_TEAM="20150"
        ;;
    *)
        echo "Invalid team selection"
        exit 1
        ;;
    esac
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required but not installed. Please install it first."
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

EPIC_URL=$(jq -r '.epic' "$CONFIG_FILE")

if [ -z "$EPIC_URL" ] || [ "$EPIC_URL" = "null" ]; then
    echo "Error: Invalid epic URL in config file"
    exit 1
fi

EPIC_KEY=$(echo "$EPIC_URL" | grep -oE '[A-Z][A-Z0-9]+[A-Z0-9]+-[0-9]+')

if [ -z "$EPIC_KEY" ]; then
    echo "Error: Could not extract epic key from URL"
    exit 1
fi

PROJECT_KEY=$(echo "$EPIC_KEY" | cut -d'-' -f1)

format_api_description() {
    local desc="$1"
    local method=$(echo "$desc" | jq -r '.ApiSpec.Method')
    local path=$(echo "$desc" | jq -r '.ApiSpec.Path')
    local headers=$(echo "$desc" | jq -r '.ApiSpec.Headers[] | (.key + ": " + .value)' | paste -sd "\\n" -)
    local request_fields=$(echo "$desc" | jq -r '.Request.Fields[] | select(.name != "") | "|" + .name + "|" + (.type|tostring) + "|" + (.required|tostring) + "|" + (.validation|tostring) + "|"' | sed 's/"/\\"/g')
    local request_example=$(echo "$desc" | jq -r '.Request.Example | tojson' | sed 's/"/\\"/g')
    local response_fields=$(echo "$desc" | jq -r '.Response.Fields[] | select(.name != "") | "|" + .name + "|" + (.type|tostring) + "|" + "-" + "|" + (.description|tostring) + "|"' | sed 's/"/\\"/g')
    local response_example=$(echo "$desc" | jq -r '.Response.Example | tojson' | sed 's/"/\\"/g')

    cat <<EOF
h2. API Specification

||Field||Value||
|Method|${method}|
|Path|${path}|
|Headers|${headers}|

h3. Request Body

||Field||Type||Required||Validation||
${request_fields}

*Example:*
{code:json}
${request_example}
{code}

h3. Response Body

||Field||Type||Required||Description||
${response_fields}

*Example:*
{code:json}
${response_example}
{code}
EOF
}

process_chain_template() {
    local name="$1"
    local service="$2"
    local chain="$3"

    if [ -f "$TEMPLATE_DIR/${chain}.template" ]; then
        # Strip "create api for" prefix if it exists
        local clean_name="${name#create api for }"
        template_content=$(cat "$TEMPLATE_DIR/${chain}.template")
        echo "$template_content" | jq -c --arg name "$clean_name" --arg service "$service" '
            .cards[] | 
            .Name = (.Name | gsub("\\{name\\}"; $name)) |
            .Service = (.Service | gsub("\\{service\\}"; $service))
        ' | while read -r card; do
            card_name=$(echo "$card" | jq -r '.Name')
            card_type=$(echo "$card" | jq -r '.Type')
            card_service=$(echo "$card" | jq -r '.Service')
            card_desc=$(echo "$card" | jq -r '.Description | if type == "object" then . else {"DOD": [.]} end')
            card_prefix=$(echo "$card" | jq -r '.Prefix // empty')
            create_jira_ticket "$card_name" "$card_type" "$card_service" "$card_desc" "$card_prefix"
        done
    else
        echo "Warning: Chain template $chain not found"
    fi
}

jq -c '.cards[]' "$CONFIG_FILE" | while read -r card; do
    name=$(echo "$card" | jq -r '.name')
    type=$(echo "$card" | jq -r '.type')
    service=$(echo "$card" | jq -r '.service')
    create_jira_ticket "$name" "$type" "$service"
    echo "$card" | jq -r '.chains[]?' | while read -r chain; do
        if [ "$chain" != "null" ]; then
            process_chain_template "$name" "$service" "$chain"
        fi
    done
done
