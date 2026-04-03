FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

ARG DEBIAN_FRONTEND=noninteractive

# Install system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    vim \
    nano \
    jq \
    tree \
    iputils-ping \
    iproute2 \
    tcpdump \
    net-tools \
    nmap \
    sshpass \
    python3-pip \
    bash-completion \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Install containerlab
RUN bash -c "$(curl -sL https://get.containerlab.dev)"

# Install Python networking libraries
COPY requirements.txt /tmp/pip-requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/pip-requirements.txt \
    && rm /tmp/pip-requirements.txt
