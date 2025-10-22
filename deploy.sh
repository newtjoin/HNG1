#!/bin/sh
#=============================================================================
# HNG DevOps Stage 1 Task: Automated Deployment Bash Script
# created by whiz
# POSIX-compliant deployment script for remote server automation
#=============================================================================

set -e
set -u
set -o pipefail

#=============================================================================
# GLOBAL VARIABLES
#=============================================================================

SCRIPT_NAME=$(basename "$0")
LOG_FILE="deploy_$(date +'%Y%m%d_%H%M%S').log"
CLEANUP_MODE=0

# Exit codes
EXIT_SUCCESS=0
EXIT_PARAM_ERROR=1
EXIT_DOCKERFILE_ERROR=2
EXIT_SSH_ERROR=3
EXIT_REMOTE_SETUP_ERROR=4
EXIT_DEPLOYMENT_ERROR=5
EXIT_NGINX_ERROR=6
EXIT_VALIDATION_ERROR=7
EXIT_GENERAL_ERROR=99

#=============================================================================
# LOGGING FUNCTIONS
#=============================================================================

log_message() {
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

log_error() {
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_success() {
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] SUCCESS: $1" | tee -a "$LOG_FILE"
}

cleanup() {
    log_message "Performing cleanup operations..."
    # Add any necessary cleanup here
}

error_exit() {
    log_error "$1"
    cleanup
    exit "${2:-$EXIT_GENERAL_ERROR}"
}

trap 'error_exit "Script interrupted or failed at line $LINENO" $EXIT_GENERAL_ERROR' INT TERM ERR

#=============================================================================
# PARAMETER COLLECTION AND VALIDATION
#=============================================================================

collect_parameters() {
    log_message "Starting parameter collection..."

    printf "Enter Git Repository URL: "
    read -r REPO_URL
    if [ -z "$REPO_URL" ]; then
        error_exit "Repository URL cannot be empty" $EXIT_PARAM_ERROR
    fi

    printf "Enter Personal Access Token (PAT): "
    stty -echo 2>/dev/null || true
    read -r PAT
    stty echo 2>/dev/null || true
    echo ""
    if [ -z "$PAT" ]; then
        error_exit "Personal Access Token cannot be empty" $EXIT_PARAM_ERROR
    fi

    printf "Enter Branch name [main]: "
    read -r BRANCH
    BRANCH=${BRANCH:-main}

    printf "Enter Remote SSH username: "
    read -r SSH_USER
    if [ -z "$SSH_USER" ]; then
        error_exit "SSH username cannot be empty" $EXIT_PARAM_ERROR
    fi

    printf "Enter Remote Server IP address: "
    read -r SSH_IP
    if [ -z "$SSH_IP" ]; then
        error_exit "Server IP cannot be empty" $EXIT_PARAM_ERROR
    fi

    printf "Enter SSH key path [~/.ssh/id_rsa]: "
    read -r SSH_KEY
    SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}

    case "$SSH_KEY" in
        "~"*) SSH_KEY="$HOME${SSH_KEY#\~}" ;;
    esac

    if [ ! -f "$SSH_KEY" ]; then
        error_exit "SSH key not found at: $SSH_KEY" $EXIT_PARAM_ERROR
    fi

    printf "Enter Application port (container internal): "
    read -r APP_PORT
    if [ -z "$APP_PORT" ]; then
        error_exit "Application port cannot be empty" $EXIT_PARAM_ERROR
    fi

    case "$APP_PORT" in
        ''|*[!0-9]*) error_exit "Port must be a number" $EXIT_PARAM_ERROR ;;
    esac

    PROJECT_NAME=$(basename "$REPO_URL" .git)
    REMOTE_APP_DIR="$HOME/deployments/$PROJECT_NAME"

    log_success "Parameters collected successfully"
    log_message "Repository: $REPO_URL"
    log_message "Branch: $BRANCH"
    log_message "Remote Server: $SSH_USER@$SSH_IP"
    log_message "Application Port: $APP_PORT"
}

#=============================================================================
# GIT REPOSITORY MANAGEMENT
#=============================================================================

clone_or_pull_repo() {
    log_message "Managing Git repository..."

    REPO_URL_WITH_PAT=$(echo "$REPO_URL" | sed "s|https://|https://$PAT@|")

    if [ -d "$PROJECT_NAME" ]; then
        log_message "Repository directory exists. Pulling latest changes..."
        cd "$PROJECT_NAME" || error_exit "Cannot access project directory" $EXIT_GENERAL_ERROR

        git fetch origin || error_exit "Failed to fetch from remote" $EXIT_GENERAL_ERROR
        git checkout "$BRANCH" || error_exit "Failed to checkout branch $BRANCH" $EXIT_GENERAL_ERROR
        git pull origin "$BRANCH" || error_exit "Failed to pull latest changes" $EXIT_GENERAL_ERROR

        cd ..
    else
        log_message "Cloning repository..."
        git clone -b "$BRANCH" "$REPO_URL_WITH_PAT" "$PROJECT_NAME" || \
            error_exit "Failed to clone repository" $EXIT_GENERAL_ERROR
    fi

    log_success "Repository ready"
}

#=============================================================================
# DOCKERFILE VERIFICATION
#=============================================================================

verify_dockerfile() {
    log_message "Verifying Docker configuration files..."

    cd "$PROJECT_NAME" || error_exit "Cannot access project directory" $EXIT_GENERAL_ERROR

    if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] || [ -f "Dockerfile" ]; then
        log_success "Docker configuration files found"
        DOCKER_COMPOSE_FILE=""
        if [ -f "docker-compose.yml" ]; then
            DOCKER_COMPOSE_FILE="docker-compose.yml"
        elif [ -f "docker-compose.yaml" ]; then
            DOCKER_COMPOSE_FILE="docker-compose.yaml"
        fi
    else
        error_exit "No Dockerfile or docker-compose.yml found in project" $EXIT_DOCKERFILE_ERROR
    fi

    cd ..
}

#=============================================================================
# SSH CONNECTIVITY CHECK
#=============================================================================

check_ssh_connectivity() {
    log_message "Testing SSH connectivity to remote server..."

    ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "$SSH_USER@$SSH_IP" 'echo "SSH connection successful"' || \
        error_exit "Cannot connect to remote server via SSH" $EXIT_SSH_ERROR

    log_success "SSH connectivity verified"
}

#=============================================================================
# REMOTE ENVIRONMENT SETUP
#=============================================================================

setup_remote_environment() {
    log_message "Setting up remote environment..."

    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" << 'ENDSSH' || \
        error_exit "Failed to setup remote environment" $EXIT_REMOTE_SETUP_ERROR

# Update system packages
echo "Updating system packages..."
sudo apt-get update -y

if ! command -v docker >/dev/null 2>&1; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo systemctl enable docker
    sudo systemctl start docker
else
    echo "Docker already installed"
fi

if ! command -v docker-compose >/dev/null 2>&1; then
    echo "Installing Docker Compose..."
    sudo apt-get install -y docker-compose
else
    echo "Docker Compose already installed"
fi

if ! command -v nginx >/dev/null 2>&1; then
    echo "Installing Nginx..."
    sudo apt-get install -y nginx
    sudo systemctl enable nginx
    sudo systemctl start nginx
else
    echo "Nginx already installed"
fi

if ! groups | grep -q docker; then
    echo "Adding user to docker group..."
    sudo usermod -aG docker $USER
fi

echo "=== Installed Versions ==="
docker --version
docker-compose --version
nginx -v

ENDSSH

    log_success "Remote environment setup complete"
}

#=============================================================================
# FILE TRANSFER AND DEPLOYMENT
#=============================================================================

transfer_and_deploy() {
    log_message "Transferring project files to remote server..."

    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" \
        "mkdir -p $REMOTE_APP_DIR" || \
        error_exit "Failed to create remote directory" $EXIT_DEPLOYMENT_ERROR

    rsync -avz --delete -e "ssh -i $SSH_KEY" ./ "$SSH_USER@$SSH_IP:~/app_dir/" || \
        error_exit "Failed to transfer files" $EXIT_DEPLOYMENT_ERROR

    log_success "Files transferred successfully"
    log_message "Building and deploying Docker containers..."

    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" << ENDSSH || \
        error_exit "Failed to deploy containers" $EXIT_DEPLOYMENT_ERROR

cd $REMOTE_APP_DIR

if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    echo "Using Docker Compose deployment..."
    docker-compose down 2>/dev/null || true
    docker-compose build
    docker-compose up -d
else
    echo "Using Docker deployment..."
    docker stop $PROJECT_NAME 2>/dev/null || true
    docker rm $PROJECT_NAME 2>/dev/null || true
    docker build -t $PROJECT_NAME .
    docker run -d --name $PROJECT_NAME -p $APP_PORT:$APP_PORT $PROJECT_NAME
fi

sleep 5

echo "=== Container Status ==="
docker ps

ENDSSH

    log_success "Deployment complete"
}

#=============================================================================
# NGINX CONFIGURATION
#=============================================================================

configure_nginx() {
    log_message "Configuring Nginx reverse proxy..."

    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" << ENDSSH || \
        error_exit "Failed to configure Nginx" $EXIT_NGINX_ERROR

sudo tee /etc/nginx/sites-available/$PROJECT_NAME.conf > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/$PROJECT_NAME.conf /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

ENDSSH

    log_success "Nginx reverse proxy configured"
}

#=============================================================================
# DEPLOYMENT VALIDATION
#=============================================================================

validate_deployment() {
    log_message "Validating deployment..."

    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" \
        "sudo systemctl is-active docker" > /dev/null || \
        error_exit "Docker service is not running" $EXIT_VALIDATION_ERROR

    log_message "Checking container health..."
    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" \
        "docker ps --format '{{.Names}} - {{.Status}}'" | tee -a "$LOG_FILE"

    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" \
        "sudo systemctl is-active nginx" > /dev/null || \
        error_exit "Nginx service is not running" $EXIT_VALIDATION_ERROR

    log_message "Testing application endpoint on remote server..."
    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" \
        "curl -s -o /dev/null -w '%{http_code}' http://localhost" | tee -a "$LOG_FILE"

    log_success "Deployment validation complete"
    log_message "Application should be accessible at http://$SSH_IP"
}

#=============================================================================
# CLEANUP MODE
#=============================================================================

perform_cleanup() {
    log_message "Running cleanup mode..."

    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" << ENDSSH || \
        error_exit "Failed to cleanup resources" $EXIT_GENERAL_ERROR

cd $REMOTE_APP_DIR 2>/dev/null || true

if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    docker-compose down -v
else
    docker stop $PROJECT_NAME 2>/dev/null || true
    docker rm $PROJECT_NAME 2>/dev/null || true
    docker rmi $PROJECT_NAME 2>/dev/null || true
fi

sudo rm -f /etc/nginx/sites-available/$PROJECT_NAME.conf
sudo rm -f /etc/nginx/sites-enabled/$PROJECT_NAME.conf
sudo nginx -t && sudo systemctl reload nginx

cd ~ && rm -rf $REMOTE_APP_DIR

echo "Cleanup completed"

ENDSSH

    log_success "Cleanup completed successfully"
    exit $EXIT_SUCCESS
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    log_message "========================================="
    log_message "Docker Deployment Automation Script"
    log_message "========================================="

    if [ "${1:-}" = "--cleanup" ]; then
        CLEANUP_MODE=1
        collect_parameters
        perform_cleanup
    fi

    collect_parameters
    clone_or_pull_repo
    verify_dockerfile
    check_ssh_connectivity
    setup_remote_environment
    transfer_and_deploy
    configure_nginx
    validate_deployment

    log_success "========================================="
    log_success "Deployment completed successfully!"
    log_success "Application URL: http://$SSH_IP"
    log_success "Log file: $LOG_FILE"
    log_success "========================================="
    exit $EXIT_SUCCESS
}

main "$@"
