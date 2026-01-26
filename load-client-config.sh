#!/bin/bash
# Load client configuration from validator-config.yaml and optional user config file

# Associative array to store client images (requires bash 4+, but we'll use parallel arrays for bash 3.2 compatibility)
CLIENT_NAMES=()
CLIENT_IMAGES_LIST=()
KNOWN_CLIENTS=("zeam" "ream" "qlean" "lantern" "lighthouse" "grandine")

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

# Function to extract client type from node name (e.g., zeam_0 -> zeam)
get_client_type() {
    echo "$1" | sed 's/_[0-9]*$//'
}

# Function to load default config from validator-config.yaml
load_default_config() {
    local validator_config="$configDir/validator-config.yaml"

    if [ ! -f "$validator_config" ]; then
        echo "⚠️  Warning: validator-config.yaml not found at $validator_config"
        return 1
    fi

    # Load images from validators array using yq
    for client in "${KNOWN_CLIENTS[@]}"; do
        # Find the first validator matching this client type (e.g., zeam_0 for zeam)
        local image=$(yq eval ".validators[] | select(.name | test(\"^${client}_\")) | .image" "$validator_config" 2>/dev/null | head -1)
        if [ -n "$image" ] && [ "$image" != "null" ]; then
            CLIENT_NAMES+=("$client")
            CLIENT_IMAGES_LIST+=("$image")
        fi
    done

    echo "✓ Loaded default client images from $validator_config"
}

# Function to load user config and override defaults
# User config format uses node names (e.g., zeam_0) instead of client names
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

    # Load user-specified images (supports both 'nodes' and 'clients' format for backwards compatibility)
    local override_count=0

    # Try 'nodes' format first (new format with zeam_0, etc.)
    local nodes_exist=$(yq eval '.nodes // empty' "$user_config" 2>/dev/null)

    if [ -n "$nodes_exist" ]; then
        # New format: nodes with zeam_0 style names
        while IFS= read -r line; do
            local node_name=$(echo "$line" | awk '{print $1}')
            local node_image=$(echo "$line" | awk '{print $2}')

            # Extract client type from node name (zeam_0 -> zeam)
            local client_type=$(get_client_type "$node_name")

            # Validate client type
            local valid_client=false
            for known in "${KNOWN_CLIENTS[@]}"; do
                if [ "$client_type" == "$known" ]; then
                    valid_client=true
                    break
                fi
            done

            if [ "$valid_client" == "false" ]; then
                echo "⚠️  Warning: Unknown client type '$client_type' from node '$node_name' - skipping"
                continue
            fi

            # Validate image format (basic check)
            if [[ ! "$node_image" =~ ^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$ ]]; then
                echo "⚠️  Warning: Invalid image format '$node_image' for node '$node_name' - using default"
                continue
            fi

            # Find and update the client image
            local idx=$(find_client_index "$client_type")
            if [ "$idx" != "-1" ]; then
                CLIENT_IMAGES_LIST[$idx]="$node_image"
                echo "  ✓ Override $client_type (from $node_name): $node_image"
                ((override_count++))
            fi
        done < <(yq eval '.nodes[] | .name + " " + .image' "$user_config" 2>/dev/null)
    else
        # Fallback: try 'clients' format (old format for backwards compatibility)
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
    fi

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

# Load default configuration from validator-config.yaml
load_default_config

# Load user configuration if provided
if [ -n "$configFile" ]; then
    load_user_config "$configFile"
fi
