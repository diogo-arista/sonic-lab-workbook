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
    iptables \
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

# Switch iptables to legacy mode. GitHub Codespaces (and some Linux hosts) use
# the nftables backend by default, which is incompatible with containerlab's
# iptables rules. iptables-legacy uses the traditional kernel API that clab expects.
RUN update-alternatives --set iptables  /usr/sbin/iptables-legacy  2>/dev/null || true \
    && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

# Grant containerlab the Linux capabilities it needs so it runs without sudo.
# cap_net_admin: create/modify network interfaces and namespaces
# cap_net_raw:   raw socket access (needed for some lab operations)
# cap_sys_admin: mount namespaces, needed for veth pair setup
# cap_chown:     chown the authorized_keys file containerlab creates for SSH access
RUN setcap cap_net_admin,cap_net_raw,cap_sys_admin,cap_chown+eip /usr/bin/containerlab

# The containerlab apt package creates the 'clab_admins' group.
# Add vscode to it here so the containerlab VS Code extension activates without
# errors. The 'docker' group is handled in post-create.sh because its GID is
# determined at runtime by the docker-outside-of-docker feature.
RUN usermod -aG clab_admins vscode
