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

# Install containerlab via apt — works on both amd64 and arm64, no hanging curl script
RUN echo "deb [trusted=yes] https://apt.fury.io/netdevops/ /" \
    | tee /etc/apt/sources.list.d/netdevops.list \
    && apt-get update \
    && apt-get install -y containerlab \
    && rm -rf /var/lib/apt/lists/*

# Grant containerlab the Linux capabilities it needs so it runs without sudo.
# cap_net_admin: create/modify network interfaces and namespaces
# cap_net_raw:   raw socket access (needed for some lab operations)
# cap_sys_admin: mount namespaces, needed for veth pair setup
RUN setcap cap_net_admin,cap_net_raw,cap_sys_admin+eip /usr/bin/containerlab
