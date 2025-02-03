#!/bin/bash

# Update and install common dependencies
echo "Updating and installing common dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq git curl vim mercurial make binutils bison gcc build-essential pkg-config libssl-dev zlib1g-dev apt-transport-https ca-certificates gnupg lsb-release

# Configure Git if desired
git_username_set=$(git config --global user.name)
git_email_set=$(git config --global user.email)

if [[ -z "$git_username_set" || -z "$git_email_set" ]]; then
    read -p "Do you want to configure Git username and email? (y/n): " configure_git
    if [[ "$configure_git" =~ ^[Yy]$ ]]; then
        if [[ -z "$git_username_set" ]]; then
            read -p "Enter the Git username: " git_username
            git config --global user.name "$git_username"
        else
            echo "Git username is already set to '$git_username_set'."
        fi
        
        if [[ -z "$git_email_set" ]]; then
            read -p "Enter the Git email: " git_email
            git config --global user.email "$git_email"
        else
            echo "Git email is already set to '$git_email_set'."
        fi
    fi
else
    echo "Git username and email are already configured."
fi

# Install Go
if ! command -v go &> /dev/null; then
    read -p "Do you want to install the default Go version 1.22.10? (y/n): " go_default
    if [[ "$go_default" =~ ^[Yy]$ ]]; then
        go_version="1.22.10"
    else
        read -p "Enter the Go version you want to install (e.g., 1.22.10): " go_version
    fi

    echo "Installing Go $go_version..."
    wget -q https://golang.org/dl/go$go_version.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go$go_version.linux-amd64.tar.gz
    if ! grep -q 'export PATH=$PATH:/usr/local/go/bin' ~/.profile; then
        echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.profile
    fi
    source ~/.profile

    # Fix to pull private repositories via go get
    git config --global url.git@github.com:.insteadOf https://github.com/
    go env -w GOPRIVATE=github.com/stakater-ab/
else
    echo "Go is already installed."
fi

# Clone and install GVM
if ! command -v gvm &> /dev/null; then
    echo "Installing GVM..."
    bash < <(curl -s https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer)
    [[ -s "$HOME/.gvm/scripts/gvm" ]] && source "$HOME/.gvm/scripts/gvm"
    gvm install go$go_version -B
    gvm use go$go_version --default
else
    echo "GVM is already installed."
fi

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    sudo apt-get remove -y -qq docker docker-engine docker.io containerd runc
    sudo mkdir -p /etc/apt/keyrings
    if ! sudo test -f /etc/apt/keyrings/docker.gpg; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    fi
    if ! grep -q 'download.docker.com' /etc/apt/sources.list.d/docker.list; then
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi
    sudo apt-get update -qq
    sudo apt-get remove -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add current user to the docker group to fix permission issues
    sudo usermod -aG docker $USER
    newgrp docker
    
    # Docker login
    read -p "Do you want to login to Docker? (y/n): " docker_login
    if [[ "$docker_login" =~ ^[Yy]$ ]]; then
        while true; do
            read -p "Enter your Docker username: " docker_username
            read -sp "Enter your Docker password: " docker_password
            echo
            echo "$docker_password" | docker login --username "$docker_username" --password-stdin
            if [[ $? -eq 0 ]]; then
                echo "Docker login successful."
                break
            else
                echo "Docker login failed. Please try again."
            fi
        done
    fi
else
    echo "Docker is already installed."
fi

# Install Tilt
if ! command -v tilt &> /dev/null; then
    echo "Installing Tilt..."
    curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash
    if ! grep -q 'source <(tilt completion bash)' ~/.bashrc; then
        echo 'source <(tilt completion bash)' >> ~/.bashrc
    fi
else
    echo "Tilt is already installed."
fi

# Install kubectl and oc CLI
if ! command -v kubectl &> /dev/null || ! command -v oc &> /dev/null; then
    echo "Installing OpenShift OC CLI and Kubernetes kubectl..."
    curl -sLO "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz"
    tar -xzf openshift-client-linux.tar.gz
    sudo mv oc kubectl /usr/local/bin
    sudo chmod +x /usr/local/bin/oc /usr/local/bin/kubectl
    rm openshift-client-linux.tar.gz

    # Enable kubectl autocomplete
    if ! grep -q 'source <(kubectl completion bash)' ~/.bashrc; then
        echo "source <(kubectl completion bash)" >> ~/.bashrc
    fi
    if ! grep -q 'alias k=kubectl' ~/.bashrc; then
        echo "alias k=kubectl" >> ~/.bashrc
    fi
    if ! grep -q 'complete -F __start_kubectl k' ~/.bashrc; then
        echo "complete -F __start_kubectl k" >> ~/.bashrc
    fi

    # Enable oc autocomplete
    if ! grep -q 'source <(oc completion bash)' ~/.bashrc; then
        echo "source <(oc completion bash)" >> ~/.bashrc
    fi
else
    echo "kubectl and oc CLI are already installed."
fi

# Install Helm
if ! command -v helm &> /dev/null; then
    echo "Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    # Enable Helm autocomplete
    if ! grep -q 'source <(helm completion bash)' ~/.bashrc; then
        echo "source <(helm completion bash)" >> ~/.bashrc
    fi
else
    echo "Helm is already installed."
fi

# Install Visual Studio Code if desired
if ! command -v code &> /dev/null; then
    read -p "Do you want to install Visual Studio Code? (y/n): " vscode_choice
    if [[ "$vscode_choice" =~ ^[Yy]$ ]]; then
        echo "Installing Visual Studio Code..."
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
        sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
        if ! grep -q 'packages.microsoft.com/repos/vscode' /etc/apt/sources.list.d/vscode.list; then
            sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list'
        fi
        sudo apt-get update -qq
        sudo apt-get install -y -qq code
    fi
else
    echo "Visual Studio Code is already installed."
fi

# Install k3d if desired
if ! command -v k3d &> /dev/null; then
    read -p "Do you want to install k3d? (y/n): " k3d_choice
    if [[ "$k3d_choice" =~ ^[Yy]$ ]]; then
        echo "Installing k3d..."
        curl -s https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash
        if ! grep -q 'source <(k3d completion bash)' ~/.bashrc; then
            echo 'source <(k3d completion bash)' >> ~/.bashrc
        fi
    fi
else
    echo "k3d is already installed."
fi

# Install Sublime Text if desired
if ! command -v subl &> /dev/null; then
    read -p "Do you want to install Sublime Text? (y/n): " sublime_choice
    if [[ "$sublime_choice" =~ ^[Yy]$ ]]; then
        echo "Installing Sublime Text..."
        
        # Add new GPG key
        wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor > sublimehq-pub.gpg
        sudo install -o root -g root -m 644 sublimehq-pub.gpg /etc/apt/trusted.gpg.d/
        rm sublimehq-pub.gpg
        
        # Add Sublime Text repository
        if ! grep -q 'download.sublimetext.com' /etc/apt/sources.list.d/sublime-text.list; then
            echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
        fi
        
        # Update and install Sublime Text
        sudo apt-get update -qq
        sudo apt-get install -y -qq sublime-text
    fi
else
    echo "Sublime Text is already installed."
fi

# Install Google Chrome if desired
if ! command -v google-chrome &> /dev/null; then
    read -p "Do you want to install Google Chrome? (y/n): " chrome_choice
    if [[ "$chrome_choice" =~ ^[Yy]$ ]]; then
        echo "Installing Google Chrome..."
        cd /tmp
        wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
        sudo dpkg -i google-chrome-stable_current_amd64.deb || sudo apt-get -f install -y -qq
        rm google-chrome-stable_current_amd64.deb
    fi
else
    echo "Google Chrome is already installed."
fi

# Install Microsoft Edge if desired
if ! command -v microsoft-edge &> /dev/null; then
    read -p "Do you want to install Microsoft Edge? (y/n): " edge_choice
    if [[ "$edge_choice" =~ ^[Yy]$ ]]; then
        echo "Installing Microsoft Edge..."
        curl -s https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
        sudo install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/
        if ! grep -q 'packages.microsoft.com/repos/edge' /etc/apt/sources.list.d/microsoft-edge-dev.list; then
            sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge-dev.list'
        fi
        sudo apt-get update -qq
        sudo apt-get install -y -qq microsoft-edge-stable
    fi
else
    echo "Microsoft Edge is already installed."
fi

# Install Postman if desired
if ! command -v postman &> /dev/null; then
    read -p "Do you want to install Postman? (y/n): " postman_choice
    if [[ "$postman_choice" =~ ^[Yy]$ ]]; then
        echo "Installing Postman..."
        sudo snap install postman
    fi
else
    echo "Postman is already installed."
fi

# Install Slack if desired
if ! command -v slack &> /dev/null; then
    read -p "Do you want to install Slack? (y/n): " slack_choice
    if [[ "$slack_choice" =~ ^[Yy]$ ]]; then
        echo "Installing Slack..."
        sudo snap install slack --classic
    fi
else
    echo "Slack is already installed."
fi

# Install Termius if desired
if ! command -v termius-app &> /dev/null; then
    read -p "Do you want to install Termius? (y/n): " termius_choice
    if [[ "$termius_choice" =~ ^[Yy]$ ]]; then
        echo "Installing Termius..."
        curl -fsSL https://www.termius.com/download/linux/Termius.deb -o termius.deb
        sudo dpkg -i termius.deb || sudo apt-get -f install -y -qq
        rm termius.deb
    fi
else
    echo "Termius is already installed."
fi

# Source .bashrc to apply changes
source ~/.bashrc