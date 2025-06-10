#!/bin/sh

BASE_URL="https://truemoney.atlassian.net"
SCRIPT_DIR=$(dirname "$0")
TEMPLATE_DIR="$SCRIPT_DIR/templates"
SUMMARY_FILE=$(mktemp)

link_issues() {
    local inward_issue="$1"
    local outward_issue="$2"

    if [ -z "$JIRA_USERNAME" ] || [ -z "$JIRA_TOKEN" ]; then
        echo "Error: JIRA_USERNAME and JIRA_TOKEN must be set"
        return 1
    fi

    auth_header=$(printf "%s:%s" "$JIRA_USERNAME" "$JIRA_TOKEN" | base64)

    json_payload=$(
        cat <<EOF
{
    "outwardIssue": {
        "key": "$outward_issue"
    },
    "inwardIssue": {
        "key": "$inward_issue"
    },
    "type": {
        "id": "10003",
        "name": "Relates"
    }
}
EOF
    )

    response=$(curl -s -X POST -w "\nHTTP_STATUS:%{http_code}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "Authorization: Basic $auth_header" \
        -d "$json_payload" \
        "$BASE_URL/rest/api/3/issueLink")

    http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d":" -f2)
    api_response=$(echo "$response" | grep -v "HTTP_STATUS:")

    if [ "$http_status" = "201" ] || [ "$http_status" = "200" ]; then
        echo "✓ Successfully linked $inward_issue to $outward_issue"
        return 0
    else
        echo "✗ Error linking issues. Status: $http_status"
        echo "Error details: $api_response"
        return 1
    fi
}

create_jira_ticket() {
    local original_name="$1"
    local type="$2"
    local service="$3"
    local description="$4"
    local prefix="${5:-}"
    local parent_ticket="${6:-}"

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

    if [ "$type" = "caller" ]; then
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
        "customfield_10008": "$EPIC_KEY",
        "customfield_10004": 1
    }
}
EOF
        )
    else
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
    fi

    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Basic $(printf "%s:%s" "$JIRA_USERNAME" "$JIRA_TOKEN" | base64)" \
        -d "$json_payload" \
        "$BASE_URL/rest/api/2/issue")

    if echo "$response" | jq -e '.key' >/dev/null; then
        ticket_key=$(echo "$response" | jq -r '.key')
        echo "Created ticket $ticket_key: $summary under epic $EPIC_KEY"
        printf "%s" "$ticket_key"
    else
        echo "Error creating ticket: $summary"
        echo "Response: $response"
        return 1
    fi
}

format_description() {
    local desc="$1"
    if echo "$desc" | jq -e . >/dev/null 2>&1; then
        local dod_items=$(echo "$desc" | jq -r '.DOD | join("\n")')
        local note=$(echo "$desc" | jq -r '.Note // empty')
        local output="${dod_items}"

        if [ -n "$note" ]; then
            output="${output}\n\n*Note:* ${note}"
        fi

        printf '%s' "$output"
    else
        printf '%s' "$desc"
    fi
}

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
    local type="$3"
    local api_ticket="$4"
    local temp_caller="$5"
    local temp_integrate="$6"
    local temp_file
    temp_file=$(mktemp)
    local test_case_key=""
    local test_script_key=""

    echo "Processing type template: $type for ticket: $api_ticket"

    if [ -f "$TEMPLATE_DIR/${type}.template" ]; then
        local clean_name="${name#create api for }"
        template_content=$(cat "$TEMPLATE_DIR/${type}.template")

        echo "$template_content" |
            jq -c --arg name "$clean_name" --arg service "$service" \
                '.cards[] | .Name = (.Name | gsub("\\{name\\}"; $name)) | .Service = (.Service | gsub("\\{service\\}"; $service))' |
            while read -r card; do
                [ -z "$card" ] && continue

                card_name=$(echo "$card" | jq -r '.Name')
                card_type=$(echo "$card" | jq -r '.Type')
                card_service=$(echo "$card" | jq -r '.Service')
                card_desc=$(echo "$card" | jq -r '.Description | if type == "object" then . else {"DOD": [.]} end')
                card_prefix=$(echo "$card" | jq -r '.Prefix // empty')

                ticket_key=$(create_jira_ticket "$card_name" "$card_type" "$card_service" "$card_desc" "$card_prefix" "$api_ticket" | tail -n1)

                if [ -n "$ticket_key" ]; then
                    echo "Created $card_type ticket: $ticket_key"

                    if echo "$card_name" | grep -q "test case"; then
                        echo "test case:${ticket_key}" >>"$temp_file"
                        test_case_key="$ticket_key"
                    elif echo "$card_name" | grep -q "test script"; then
                        echo "test script:${ticket_key}" >>"$temp_file"
                        test_script_key="$ticket_key"
                    else
                        echo "${card_type}:${ticket_key}" >>"$temp_file"
                    fi

                    case "$card_type" in
                    "caller")
                        echo "$ticket_key" >"$temp_caller"
                        ;;
                    "integrate")
                        echo "$ticket_key" >>"$temp_integrate"
                        ;;
                    esac
                fi
            done

        echo "Created tickets:"
        cat "$temp_file"

        if [ -s "$temp_file" ]; then
            echo "Processing ticket links..."

            while read -r line; do
                [ -z "$line" ] && continue
                type=${line%%:*}
                key=${line#*:}

                case "$type" in
                "test case")
                    test_case_key="$key"
                    ;;
                "test script")
                    test_script_key="$key"
                    ;;
                esac
            done <"$temp_file"

            while read -r line; do
                [ -z "$line" ] && continue
                type=${line%%:*}
                key=${line#*:}

                case "$type" in
                "caller" | "diagram" | "perf" | "test case" | "test script")
                    link_issues "$api_ticket" "$key"
                    ;;
                esac
            done <"$temp_file"

            if [ -n "$test_case_key" ] && [ -n "$test_script_key" ]; then
                link_issues "$test_case_key" "$test_script_key"
            fi
        fi
    else
        echo "Warning: Type template $type not found"
    fi

    rm -f "$temp_file"
}

process_type_template() {
    local name="$1"
    local service="$2"
    local type="$3"
    local api_ticket="$4"
    local temp_caller="$5"
    local temp_integrate="$6"
    local temp_file
    temp_file=$(mktemp)
    local robot_test_keys=""

    echo "Processing type template: $type for ticket: $api_ticket"

    if [ -f "$TEMPLATE_DIR/${type}.template" ]; then
        local clean_name="${name#create api for }"
        template_content=$(cat "$TEMPLATE_DIR/${type}.template")

        echo "$template_content" |
            jq -c --arg name "$clean_name" --arg service "$service" \
                '.cards[] | .Name = (.Name | gsub("\\{name\\}"; $name)) | .Service = (.Service | gsub("\\{service\\}"; $service))' |
            while read -r card; do
                [ -z "$card" ] && continue

                card_name=$(echo "$card" | jq -r '.Name')
                card_type=$(echo "$card" | jq -r '.Type')
                card_service=$(echo "$card" | jq -r '.Service')
                card_desc=$(echo "$card" | jq -r '.Description | if type == "object" then . else {"DOD": [.]} end')
                card_prefix=$(echo "$card" | jq -r '.Prefix // empty')

                ticket_key=$(create_jira_ticket "$card_name" "$card_type" "$card_service" "$card_desc" "$card_prefix" "$api_ticket" | tail -n1)

                if [ -n "$ticket_key" ]; then
                    printf "Card: [%s] %s\nLink: %s/browse/%s\n\n" "$card_service" "$card_name" "$BASE_URL" "$ticket_key" >>"$SUMMARY_FILE"

                    if [ "$type" = "robot" ]; then
                        if [ -z "$robot_test_keys" ]; then
                            robot_test_keys="$ticket_key"
                        else
                            echo "$robot_test_keys" | tr ' ' '\n' | while read -r prev_key; do
                                [ -n "$prev_key" ] && link_issues "$prev_key" "$ticket_key"
                            done
                            robot_test_keys="$robot_test_keys $ticket_key"
                        fi
                    fi

                    case "$card_type" in
                    "caller")
                        echo "$ticket_key" >"$temp_caller"
                        ;;
                    "integrate")
                        echo "$ticket_key" >>"$temp_integrate"
                        ;;
                    esac
                fi
            done

        if [ -n "$api_ticket" ]; then
            echo "$robot_test_keys" | tr ' ' '\n' | while read -r key; do
                [ -n "$key" ] && link_issues "$api_ticket" "$key"
            done
        fi
    else
        echo "Warning: Type template $type not found"
    fi

    rm -f "$temp_file"
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

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required but not installed. Please install it first."
    exit 1
fi

if ! command -v fzf >/dev/null 2>&1; then
    echo "Error: fzf is required but not installed. Please install it first."
    exit 1
fi

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

printf "Enter Epic URL (e.g., https://truemoney.atlassian.net/browse/WE230007-730):\n"
read -r EPIC_URL

if [ -z "$EPIC_URL" ]; then
    echo "Error: Epic URL cannot be empty"
    exit 1
fi

EPIC_KEY=$(echo "$EPIC_URL" | grep -oE '[A-Z][A-Z0-9]+[A-Z0-9]+-[0-9]+')

if [ -z "$EPIC_KEY" ]; then
    echo "Error: Could not extract epic key from URL"
    exit 1
fi

PROJECT_KEY=$(echo "$EPIC_KEY" | cut -d'-' -f1)

printf "Enter card name:\n"
read -r card_name

if [ -z "$card_name" ]; then
    echo "Error: Card name cannot be empty"
    exit 1
fi

printf "Enter service name (e.g., mf-gw):\n"
read -r service_name

if [ -z "$service_name" ]; then
    echo "Error: Service name cannot be empty"
    exit 1
fi

types="
api
caller
diagram
integrate
perf
robot
"

printf "Use TAB to select multiple types, ENTER to confirm\n"
selected_types=$(printf "%s" "$types" | tr ' ' '\n' | grep -v '^$' |
    fzf --multi --header="Select types to create (TAB to select, ENTER to confirm)" \
        --preview 'echo "Selected type: {}"')

if [ -z "$selected_types" ]; then
    echo "No types selected. Exiting."
    exit 1
fi

parent_key=""

if echo "$selected_types" | grep -q "^api$"; then
    echo "Creating API ticket: $card_name for service: $service_name"
    parent_key=$(create_jira_ticket "$card_name" "api" "$service_name" | tail -n1)

    if [ -z "$parent_key" ]; then
        echo "Failed to create API ticket"
        exit 1
    fi
    printf "Card: [%s] %s\nLink: %s/browse/%s\n\n" "$service_name" "$card_name" "$BASE_URL" "$parent_key" >>"$SUMMARY_FILE"
fi

temp_caller=$(mktemp)
temp_integrate=$(mktemp)

echo "$selected_types" | while read -r type; do
    if [ -n "$type" ] && [ "$type" != "api" ]; then
        process_type_template "$card_name" "$service_name" "$type" "$parent_key" "$temp_caller" "$temp_integrate"
    fi
done

if [ -s "$temp_integrate" ]; then
    if [ -s "$temp_caller" ]; then
        caller_key=$(cat "$temp_caller")
        while read -r integrate_key; do
            [ -z "$integrate_key" ] && continue
            link_issues "$caller_key" "$integrate_key"
        done <"$temp_integrate"
    fi
fi

if [ -s "$SUMMARY_FILE" ]; then
    echo "\n=== Summary of Created Cards ==="
    cat "$SUMMARY_FILE"
fi

rm -f "$temp_caller" "$temp_integrate" "$SUMMARY_FILE"
