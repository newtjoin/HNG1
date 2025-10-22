# HNG DevOps Stage 1: Automated Deployment Script

This repository contains a POSIX-compliant Bash script for automating the deployment of applications to a remote server. The script collects necessary parameters from the user to perform a complete automated deployment, which includes environment setup, code transfer, containerization with Docker, and reverse proxy configuration with Nginx.

## Features

- **Automated Git Operations**: Clones a new repository or pulls the latest changes from a specific branch.
- **Docker Support**: Automatically detects and uses `Dockerfile` or `docker-compose.yml` for building and running the application.
- **Remote Environment Setup**: Installs and configures Docker, Docker Compose, and Nginx on the remote server if they are not already present.
- **Secure File Transfer**: Uses `rsync` over SSH to efficiently transfer project files.
- **Nginx Reverse Proxy**: Automatically configures Nginx to act as a reverse proxy, making the application accessible on port 80.
- **Deployment Validation**: Performs checks to ensure Docker and Nginx services are running and the application is responsive.
- **Cleanup Mode**: Provides an option to tear down the deployment, removing containers, Nginx configurations, and project files from the remote server.
- **Comprehensive Logging**: Logs all operations to a timestamped log file for easy debugging.

## Prerequisites

### Local Machine

- A POSIX-compliant shell (like Bash or Zsh).
- `git` command-line tool.
- `ssh` client.
- `rsync` command-line tool.
- An SSH key pair for accessing the remote server.

### Remote Server

- A Debian-based Linux distribution (e.g., Ubuntu).
- `sudo` privileges for the SSH user.
- Lastly here, internet access for downloading packages.

## To get started

1.  **Clone the repository  or download the script file `deploy.sh` script.**

2.  **Make the script executable:**
    ```bash
    chmod +x deploy.sh
    ```

3.  **Run the script:**
    ```bash
    ./deploy.sh
    ```

4.  **Follow the interactive prompts:**

    The script will ask for the following information:
    - **Git Repository URL**: Copy your Git repository link here.
    - **Personal Access Token (PAT)**: A Git PAT with repository access rights. This is entered securely.
    - **Branch name**: The branch to deploy (defaults to `main`).
    - **Remote SSH username**: The user for the remote server.
    - **Remote Server IP address**: The IP address of your remote server.
    - **SSH key path**: The local path to your private SSH key (defaults to `~/.ssh/id_rsa`).
    - **Application port**: The internal port the application container listens on.

## Deployment Workflow

The script automates the following steps:

1.  **Parameter Collection**: Securely collects all required deployment details.
2.  **Git Repository Management**: Clones the repository or pulls the latest updates if it already exists locally.
3.  **Dockerfile Verification**: Checks for the presence of a `Dockerfile` or `docker-compose.yml` in the project root.
4.  **SSH Connectivity Check**: Verifies that a connection can be established with the remote server.
5.  **Remote Environment Setup**: Connects to the remote server to:
    - Update system packages.
    - Install Docker, Docker Compose, and Nginx if not already installed.
    - Add the user to the `docker` group.
6.  **File Transfer and Deployment**:
    - Transfers the project files to the remote server using `rsync`.
    - Builds and runs the application using `docker build` and `docker run` or `docker-compose up`.
7.  **Nginx Configuration**:
    - Creates an Nginx server block to proxy requests from port 80 to the application's container port.
    - Enables the new configuration and reloads Nginx.
8.  **Deployment Validation**:
    - Checks if Docker and Nginx services are active.
    - Verifies that the application container is running.
    - Tests the application endpoint to ensure it's responding.

Upon successful completion, the script will display the public URL of the deployed application.

## Cleanup Mode

To remove all deployed resources from the remote server, run the script with the `--cleanup` flag:

```bash
./deploy.sh --cleanup
```

The script will ask for the same parameters to identify the project and server, and then it will:
- Stop and remove Docker containers and images.
- Delete the Nginx configuration file.
- Remove the project directory from the server.

## Logging

All actions performed by the script are logged to a file named `deploy_YYYYMMDD_HHMMSS.log` in the same directory where the script is executed. This file is useful for troubleshooting any issues that may arise during the deployment process.

---
*This script was created by **whiz** for the HNG DevOps Stage 1 task.*
