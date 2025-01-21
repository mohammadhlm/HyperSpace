#!/bin/bash

# Define color variables
CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Log file path
LOG_FILE="/root/script_progress.log"
CONTAINER_NAME="aios-container"

# Logging function
log_message() {
    echo -e "$1"
    echo "$(date): $1" >> $LOG_FILE
}

# Retry function
retry() {
    local n=1
    local delay=10
    while true; do
        "$@" && return 0
        log_message "Attempt $n failed! Retrying in $delay seconds..."
        sleep $delay
        ((n++))
    done
}

# Check and install Docker
check_and_install_docker() {
    if ! command -v docker &> /dev/null; then
        log_message "${RED}Docker not found. Installing Docker...${RESET}"
        retry apt-get update -y
        retry apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        retry apt update -y
        retry apt install -y docker-ce
        systemctl start docker
        systemctl enable docker
        log_message "${GREEN}Docker installed and started.${RESET}"
    else
        log_message "${GREEN}Docker already installed.${RESET}"
    fi
}

# Start Docker container
start_container() {
    log_message "${BLUE}Starting Docker container...${RESET}"
    retry docker run -d --name aios-container --restart unless-stopped -v /root:/root kartikhyper/aios /app/aios-cli start
    log_message "${GREEN}Docker container started.${RESET}"
}

# Wait for container initialization
wait_for_container_to_start() {
    log_message "${CYAN}Waiting for container initialization...${RESET}"
    sleep 30
}

# Check daemon status
check_daemon_status() {
    log_message "${BLUE}Checking daemon status inside container...${RESET}"
    docker exec -i aios-container /app/aios-cli status
    if [[ $? -ne 0 ]]; then
        log_message "${RED}Daemon not running, restarting...${RESET}"
        docker exec -i aios-container /app/aios-cli kill
        sleep 2
        docker exec -i aios-container /app/aios-cli start
        log_message "${GREEN}Daemon restarted.${RESET}"
    else
        log_message "${GREEN}Daemon is running.${RESET}"
    fi
}

# Install local model with retry logic
install_local_model() {
    log_message "${BLUE}Installing local model...${RESET}"
    retry docker exec -i aios-container /app/aios-cli models add hf:afrideva/Tiny-Vicuna-1B-GGUF:tiny-vicuna-1b.q4_k_m.gguf
    log_message "${GREEN}Local model installed successfully.${RESET}"
}

# Hive login function
hive_login() {
    log_message "${CYAN}Logging into Hive...${RESET}"

    n=1
    delay=10
    while true; do
        docker exec -i aios-container /app/aios-cli hive import-keys /root/my.pem
        if [ $? -ne 0 ]; then
            log_message "Attempt $n failed: Failed to import keys. Exit code: $?"
        fi

        docker exec -i aios-container /app/aios-cli hive login
        if [ $? -ne 0 ]; then
            log_message "Attempt $n failed: Hive login failed. Exit code: $?"
        fi

        docker exec -i aios-container /app/aios-cli hive select-tier 3
        if [ $? -ne 0 ]; then
            log_message "Attempt $n failed: Failed to select tier 3. Exit code: $?"
        fi

        docker exec -i aios-container /app/aios-cli hive connect
        if [ $? -ne 0 ]; then
            log_message "Attempt $n failed: Failed to connect to Hive. Exit code: $?"
        fi

        if [ $? -eq 0 ]; then
            log_message "${GREEN}Hive login successful.${RESET}"
            return 0
        fi

        ((n++))
        log_message "Hive login and connection failed, attempt $n failed! Retrying in $delay seconds..."
        sleep $delay
    done
}

# Check Hive points
check_hive_points() {
    log_message "${BLUE}Checking Hive points...${RESET}"
    docker exec -i aios-container /app/aios-cli hive points || log_message "${RED}Failed to get Hive points.${RESET}"
    log_message "${GREEN}Hive points check completed.${RESET}"
}

# Get currently signed-in keys
get_current_signed_in_keys() {
    log_message "${BLUE}Retrieving current login keys...${RESET}"
    docker exec -i aios-container /app/aios-cli hive whoami
}

# Cleanup package lists
cleanup_package_lists() {
    log_message "${BLUE}Cleaning package lists...${RESET}"
    sudo rm -rf /var/lib/apt/lists/*
}

# Main script execution
check_and_install_docker
start_container
wait_for_container_to_start
install_local_model
check_daemon_status
hive_login
check_hive_points
get_current_signed_in_keys
cleanup_package_lists

# Container log monitoring
while true; do
    log_message "${BLUE}Starting container log monitoring...${RESET}"

    # Read last 10 logs and process line by line
    docker logs --tail 10 "$CONTAINER_NAME" | while read -r line; do
        # Trigger restart only on specific errors
        if echo "$line" | grep -qE "Last pong received.*Sending reconnect signal|Failed to authenticate|Failed to connect to Hive|already running|\"message\": \"Internal server error\"" ; then
            log_message "${BLUE}Error detected, reconnecting...${RESET}"

            # Container operations
            docker exec -i "$CONTAINER_NAME" /app/aios-cli kill
            sleep 2
            docker exec -i "$CONTAINER_NAME" /app/aios-cli start

            # Hive operations
            hive_login
            check_hive_points
            get_current_signed_in_keys

            # Log restart
            echo "$(date): Service restarted" >> "$LOG_FILE"

            # Exit current loop
            break
        fi
    done

    # Wait 5 minutes between checks
    log_message "${BLUE}Log check completed. Next check in 5 minutes...${RESET}"
    sleep 300
done
