#!/bin/bash
# Load client configuration from default and optional user config files

# Arrays to store client names and images (bash 3.2 compatible)
CLIENT_NAMES=()
CLIENT_IMAGES_LIST=()
KNOWN_CLIENTS=("zeam" "ream" "qlean" "lantern" "lighthouse" "grandine")

# Function to load default config
load_default_config() {
    local default_config="$scriptDir/client-cmds/default-client-config.yml"

    if [ ! -f "$default_config" ]; then
        echo "⚠️  Warning: Default config not found at $default_config"
        return 1
    fi

    # Load default images using yq
    while IFS= read -r line; do
        local client_name=$(echo "$line" | awk '{print $1}')
        local client_image=$(echo "$line" | awk '{print $2}')
        CLIENT_NAMES+=("$client_name")
        CLIENT_IMAGES_LIST+=("$client_image")
    done < <(yq eval '.clients[] | .name + " " + .image' "$default_config")

    echo "✓ Loaded default client images from $default_config"
}

# Function to find index of client name
find_client_index() {
    local search_name="$1"
    local i=0
    for name in "${CLIENT_NAMES[@]}"; do
        if [ "$name" == "$search_name" ]; then
            echo "$i"
            return 0
        fi
        ((i++))
    done
    echo "-1"
}

# Function to load user config and override defaults
load_user_config() {
    local user_config="$1"

    if [ -z "$user_config" ]; then
        return 0
    fi

    if [ ! -f "$user_config" ]; then
        echo "⚠️  Warning: User config file not found at $user_config - using defaults"
        return 1
    fi

    echo "Loading user config from $user_config..."

    # Load user-specified images
    local override_count=0
    while IFS= read -r line; do
        local client_name=$(echo "$line" | awk '{print $1}')
        local client_image=$(echo "$line" | awk '{print $2}')

        # Validate client name
        local valid_client=false
        for known in "${KNOWN_CLIENTS[@]}"; do
            if [ "$client_name" == "$known" ]; then
                valid_client=true
                break
            fi
        done

        if [ "$valid_client" == "false" ]; then
            echo "⚠️  Warning: Unknown client '$client_name' in config - skipping"
            continue
        fi

        # Validate image format (basic check)
        if [[ ! "$client_image" =~ ^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$ ]]; then
            echo "⚠️  Warning: Invalid image format '$client_image' for client '$client_name' - using default"
            continue
        fi

        # Find and update the client image
        local idx=$(find_client_index "$client_name")
        if [ "$idx" != "-1" ]; then
            CLIENT_IMAGES_LIST[$idx]="$client_image"
            echo "  ✓ Override $client_name: $client_image"
            ((override_count++))
        fi
    done < <(yq eval '.clients[] | .name + " " + .image' "$user_config" 2>/dev/null)

    if [ $override_count -eq 0 ]; then
        echo "⚠️  No valid overrides found in user config"
    else
        echo "✓ Applied $override_count custom image(s) from user config"
    fi
}

# Function to get image for a specific client
get_client_image() {
    local client_name="$1"
    local idx=$(find_client_index "$client_name")
    if [ "$idx" != "-1" ]; then
        echo "${CLIENT_IMAGES_LIST[$idx]}"
    fi
}

# Function to display loaded configuration
display_client_config() {
    echo ""
    echo "=================================================="
    echo "Client Configuration:"
    echo "=================================================="
    printf "%-12s | %s\n" "Client" "Docker Image"
    echo "--------------------------------------------------"
    local i=0
    for client in "${CLIENT_NAMES[@]}"; do
        if [ -n "${CLIENT_IMAGES_LIST[$i]}" ]; then
            printf "%-12s | %s\n" "$client" "${CLIENT_IMAGES_LIST[$i]}"
        fi
        ((i++))
    done
    echo "=================================================="
    echo ""
}

# Load default configuration
load_default_config

# Load user configuration if provided
if [ -n "$configFile" ]; then
    load_user_config "$configFile"
fi
