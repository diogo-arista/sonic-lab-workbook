# SONiC Lab Workbook

A containerized network lab environment using [containerlab](https://containerlab.dev) with Arista **cEOS-lab** and **SONiC** as node operating systems. The devcontainer setup ensures a consistent Linux environment on any platform — macOS, Windows (WSL2), or GitHub Codespaces.

SONiC runs as a full KVM virtual machine wrapped in Docker via [vrnetlab](https://github.com/srl-labs/vrnetlab). This gives it a proper boot sequence, reliable SSH, and predictable configuration loading — unlike the container-based `sonic-vs` image.

---

## Repository Layout

```
.
├── .devcontainer/
│   ├── devcontainer.json        # Dev container configuration
│   ├── Dockerfile               # Container image with containerlab + tools
│   ├── requirements.txt         # Python networking libraries
│   └── post-create.sh           # One-time setup script
├── labs/
│   └── 01-hello-world/
│       ├── topology.clab.yml    # Containerlab topology: ceos1 <--> sonic1
│       └── configs/
│           ├── ceos1.cfg        # cEOS startup configuration
│           └── sonic1-config.json  # SONiC config_db.json
├── scripts/
│   ├── build-sonic-vm.sh        # Download + build the SONiC vrnetlab image
│   └── get-sonic-vs.sh          # (Legacy) Download sonic-vs Docker image
├── Makefile                     # Convenience targets
└── README.md
```

---

## Prerequisites

| Platform | Requirement |
|---|---|
| macOS (Intel or Apple Silicon) | [Docker Desktop](https://www.docker.com/products/docker-desktop/) 4.x+ |
| Windows | [Docker Desktop](https://www.docker.com/products/docker-desktop/) with WSL2 backend |
| Linux | Docker Engine 24+ |
| Any | [VS Code](https://code.visualstudio.com/) + [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) |

> **System resources** — each lab node consumes RAM. Recommended: 16 GB RAM, 4+ CPU cores, 30 GB free disk.

> **KVM (nested virtualization) — required for SONiC**
> SONiC runs as a KVM virtual machine. `/dev/kvm` must be accessible inside the dev container.
> - **GitHub Codespaces** — supported. The devcontainer runs in privileged mode which exposes `/dev/kvm`. Use an **8-core or larger** machine.
> - **Linux host** — supported. KVM is available natively.
> - **macOS (Docker Desktop)** — `/dev/kvm` is **not** exposed by Docker Desktop on macOS. You can build the lab image on a Linux machine or Codespaces and export it, but you cannot run `sonic-vm` nodes locally on macOS.

> **Apple Silicon note** — cEOS-lab has native ARM64 builds since 4.28. Prefer the ARM64 variant from arista.com.

---

## Step 1 — Open the Repository in the Dev Container

The dev container provides a pre-configured Linux environment with containerlab, Docker CLI, and Python networking tools already installed.

### Option A: VS Code (local)

1. Clone this repository:
   ```bash
   git clone https://github.com/diogo-arista/sonic-lab-workbook.git sonic-lab-workbook
   cd sonic-lab-workbook
   ```

2. Open the folder in VS Code:
   ```bash
   code .
   ```

3. When prompted *"Reopen in Container"*, click it. Alternatively, open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`) and run:
   ```
   Dev Containers: Reopen in Container
   ```

4. VS Code will build the image and start the container. This takes a few minutes on the first run. The terminal inside VS Code is now the lab environment.

### Option B: GitHub Codespaces

1. On the repository page, click **Code → Codespaces → Create codespace on main**.
2. When prompted to choose a machine, select **8-core or larger** (required for the SONiC VM).
3. Wait for the environment to build (first run ~3–5 minutes).
4. The integrated terminal is the lab environment.

> **Note for Codespaces** — Docker images are not pre-loaded. Import them after the codespace starts (see Step 2).

---

## Step 2 — Import Lab Images

Neither cEOS-lab nor the SONiC vrnetlab image are available on public registries — both must be built or imported manually. Run all commands **inside the dev container terminal**.

---

### 2a — cEOS-lab (Arista)

**Download**

1. Create a free account at [arista.com](https://www.arista.com).
2. Go to **Software Downloads → EOS → cEOS-lab**.
3. Download `cEOS-lab-<version>.tar.xz` (e.g., `cEOS-lab-4.32.0F.tar.xz`).
   - On Apple Silicon, prefer the **ARM64** build.

**Transfer into the dev container** (macOS / Linux host)

The container shares the host Docker daemon, so you can import from either the host terminal or the VS Code terminal — both write to the same Docker image store.

**Import**

```bash
# Replace the filename with the version you downloaded
docker import cEOS-lab-4.32.0F.tar.xz ceos:latest
```

**Verify**

```bash
docker images | grep ceos
# ceos   latest   <id>   <date>   <size>
```

> If you downloaded a different version, update the `image:` field in [labs/01-hello-world/topology.clab.yml](labs/01-hello-world/topology.clab.yml).

---

### 2b — SONiC VM (vrnetlab)

SONiC runs as a full KVM virtual machine wrapped in Docker via vrnetlab. This requires building a Docker image from the SONiC KVM disk image.

#### What `build-sonic-vm.sh` does

1. Downloads `sonic-vs.img.gz` (the KVM disk image) from [sonic.software](https://sonic.software)
2. Decompresses and renames it to the format vrnetlab expects (`sonic-vs-YYYYMM.qcow2`)
3. Clones [srl-labs/vrnetlab](https://github.com/srl-labs/vrnetlab) and runs `make` in the `sonic/` directory
4. Tags the resulting image as `vrnetlab/vr-sonic:latest`
5. Cleans up build artifacts (the downloaded `.img.gz` is kept for re-use)

The build takes **10–20 minutes** and requires roughly 6 GB of free disk space during the build (the final image is ~3.2 GB).

#### Run the build script

```bash
# Build from the latest stable release branch (recommended)
bash scripts/build-sonic-vm.sh

# List all available release branches first
bash scripts/build-sonic-vm.sh --branch list

# Pin a specific release branch
bash scripts/build-sonic-vm.sh --branch 202411
```

Or via Make:

```bash
make build-sonic-vm                        # latest release branch
SONIC_BRANCH=202411 make build-sonic-vm   # specific branch
```

If you already have a `sonic-vs.img` or `sonic-vs.img.gz` from a previous download, skip the download step:

```bash
bash scripts/build-sonic-vm.sh --image /path/to/sonic-vs.img.gz
```

**Verify**

```bash
docker images | grep vr-sonic
# vrnetlab/vr-sonic   latest    <id>   <date>   ~3.2GB
# vrnetlab/vr-sonic   202411    <id>   <date>   ~3.2GB
```

#### Behind the scenes — how vrnetlab works

vrnetlab wraps a KVM/QEMU virtual machine inside a Docker container. When containerlab starts the `sonic-vm` node, it launches the Docker container, which in turn boots the SONiC VM using QEMU inside it. The VM gets its management interface from the containerlab management network and its data interfaces via `tc` (traffic control) tap devices. This gives SONiC a complete, unmodified boot sequence identical to a bare-metal or cloud deployment.

---

### 2c — Confirm both images are present

```bash
docker images | grep -E "ceos|vr-sonic"
```

Expected output (exact tags may differ):

```
ceos              latest    abc123   2 days ago   1.2GB
vrnetlab/vr-sonic latest    def456   1 hour ago   3.2GB
```

---

## Step 3 — Deploy Lab 01: Hello World

The topology connects one cEOS node to one SONiC node with a single point-to-point link:

```
  ┌─────────────────┐          ┌─────────────────┐
  │     ceos1       │          │     sonic1      │
  │  (Arista EOS)   │          │    (SONiC VM)   │
  │  mgmt: .11      │          │  mgmt: .12      │
  │                 │          │                 │
  │  Ethernet1      ├──────────┤  Ethernet0      │
  │  192.168.1.1/30 │          │  192.168.1.2/30 │
  └─────────────────┘          └─────────────────┘
        │                              │
        └──── Management 172.20.20.0/24 ──────┘
```

> **SONiC interface naming** — containerlab assigns Linux interface names to the VM. Inside SONiC, data interfaces are named `Ethernet0`, `Ethernet4`, `Ethernet8`, … (incrementing by 4 lanes per port for the Force10-S6000 hwsku). The mapping is:
> - `eth0` → management (connected to containerlab mgmt network)
> - `eth1` → `Ethernet0` (first data port)
> - `eth2` → `Ethernet4` (second data port)

**Deploy**

```bash
clab deploy --topo labs/01-hello-world/topology.clab.yml --reconfigure
```

Containerlab prints a summary table with management IPs once all containers are running:

```
+---+--------+----+--------------+--------------------------+---------+----------------+
| # | Name   | .. | Container ID | Image                    | State   | IPv4 Address   |
+---+--------+----+--------------+--------------------------+---------+----------------+
| 1 | ceos1  |    | a1b2c3d4e5f6 | ceos:latest              | running | 172.20.20.11/24|
| 2 | sonic1 |    | b2c3d4e5f6a1 | vrnetlab/vr-sonic:latest | running | 172.20.20.12/24|
+---+--------+----+--------------+--------------------------+---------+----------------+
```

> **Boot times** — cEOS typically takes 60–90 seconds. The SONiC VM takes **2–3 minutes** to fully boot (the QEMU VM must start, run the SONiC init sequence, and bring up all services before SSH is available). Wait before trying to connect.

**Check status**

```bash
clab inspect --topo labs/01-hello-world/topology.clab.yml
```

---

## Step 4 — Access the Nodes

### ceos1 (Arista EOS CLI)

SSH is configured with no password — just press Enter or use SSH directly:

```bash
ssh admin@172.20.20.11
# or
docker exec -it ceos1 Cli
```

Inside EOS:

```
ceos1> enable
ceos1# show interfaces Ethernet1
ceos1# show ip interface brief
ceos1# ping 192.168.1.2     ! ping sonic1 Ethernet0
```

### sonic1 (SONiC)

SSH with `admin` / `admin`:

```bash
ssh admin@172.20.20.12
```

Inside SONiC:

```bash
# Check interface and IP status
show interfaces status
show ip interfaces

# Ping ceos1 Ethernet1
ping 192.168.1.1 -c 3
```

> Because sonic1 runs as a VM, `docker exec` gives you access to the vrnetlab wrapper container, not the SONiC VM itself. Always use SSH to reach the SONiC shell.

### Management IPs

| Node   | Management IP  | Credentials           |
|--------|----------------|-----------------------|
| ceos1  | 172.20.20.11   | admin / (no password) |
| sonic1 | 172.20.20.12   | admin / admin         |

---

## Step 5 — Verify Connectivity

From ceos1 EOS CLI, ping sonic1's data-plane IP:

```
ceos1# ping 192.168.1.2 source Ethernet1
PING 192.168.1.2 (192.168.1.2) 72(100) bytes of data.
80 bytes from 192.168.1.2: icmp_seq=1 ttl=64 time=X ms
```

From sonic1 bash shell, ping ceos1:

```bash
ping 192.168.1.1 -I Ethernet0 -c 3
```

A successful ping confirms the virtual link is operational.

---

## Step 6 — Tear Down

When you are done, destroy the lab to free resources:

```bash
clab destroy --topo labs/01-hello-world/topology.clab.yml --cleanup
```

This removes all containers, virtual interfaces, and the management Docker network. The vrnetlab/vr-sonic Docker image remains in your local image store.

---

## Common containerlab Commands

```bash
# Deploy a topology
clab deploy --topo <topology.clab.yml> --reconfigure

# List running nodes and management IPs for a specific lab
clab inspect --topo <topology.clab.yml>

# Destroy a lab and clean up networks
clab destroy --topo <topology.clab.yml> --cleanup

# Generate an interactive HTML topology diagram
clab graph --topo <topology.clab.yml>
```

The [Makefile](Makefile) wraps these commands for convenience.

---

## Troubleshooting

### `/dev/kvm` not found when running `build-sonic-vm.sh`

You are on macOS with Docker Desktop, which does not expose `/dev/kvm` to containers. Run the build in GitHub Codespaces or on a Linux host, then export the image and import it elsewhere:

```bash
# On a Linux machine / Codespaces — save the image
docker save vrnetlab/vr-sonic:latest | gzip > vr-sonic.tar.gz

# On macOS — load it
docker load -i vr-sonic.tar.gz
```

### `clab deploy` fails: permission denied

The clab binary has the SUID bit set so it runs as root without sudo. Verify it is intact:

```bash
ls -l /usr/bin/containerlab
# Expected: -rwsr-xr-x ... /usr/bin/containerlab
```

If missing, rebuild the dev container (Command Palette → "Dev Containers: Rebuild Container").

### Docker image not found

Ensure the image name and tag in `topology.clab.yml` exactly match your local Docker image store:

```bash
docker images
# Compare with the image: fields in topology.clab.yml
```

### cEOS takes long to boot

cEOS-lab typically takes 60–90 seconds to finish initializing. If `Cli` reports an error immediately after `clab deploy`, wait a moment and retry.

### SONiC takes long to boot

The SONiC VM boots inside QEMU and runs the full SONiC init sequence. Allow **2–3 minutes** before SSH becomes available. Watch for readiness:

```bash
# Poll until SSH responds
until ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@172.20.20.12 "show version" 2>/dev/null; do
    echo "Waiting for SONiC..."; sleep 10
done
```

### SONiC SSH connection refused

If SSH is still refused after 3 minutes, check the vrnetlab wrapper container logs:

```bash
docker logs sonic1 | tail -30
```

Look for QEMU boot errors or kernel panics. If the VM failed to start, redeploy:

```bash
clab destroy --topo labs/01-hello-world/topology.clab.yml --cleanup
clab deploy  --topo labs/01-hello-world/topology.clab.yml --reconfigure
```

### Connectivity issues between nodes

Verify the link is present in both OS views:

```bash
# From ceos1 EOS CLI
show interfaces Ethernet1

# From sonic1 via SSH
ssh admin@172.20.20.12 "show interfaces status"
```

### Codespaces: image files too large to upload

GitHub Codespaces has an upload size limit via the browser. For large files (>1 GB), use the [GitHub CLI](https://cli.github.com/) to copy files into the codespace, or run `build-sonic-vm.sh` directly inside Codespaces (it downloads from sonic.software automatically).

---

## Resources

- [Containerlab documentation](https://containerlab.dev/quickstart/)
- [Containerlab cEOS kind](https://containerlab.dev/manual/kinds/ceos/)
- [Containerlab sonic-vm kind](https://containerlab.dev/manual/kinds/sonic-vm/)
- [vrnetlab — srl-labs/vrnetlab](https://github.com/srl-labs/vrnetlab)
- [Arista cEOS-lab download](https://www.arista.com/en/support/software-download)
- [SONiC project](https://sonic-net.github.io/SONiC/)
- [sonic.software image downloads](https://sonic.software)
