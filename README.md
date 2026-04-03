# SONiC Lab Workbook

A containerized network lab environment using [containerlab](https://containerlab.dev) with Arista **cEOS-lab** and **SONiC** (Software for Open Networking in the Cloud) as node operating systems. The devcontainer setup ensures a consistent Linux environment on any platform — macOS, Windows (WSL2), or GitHub Codespaces.

---

## Repository Layout

```
.
├── .devcontainer/
│   ├── devcontainer.json   # Dev container configuration
│   ├── Dockerfile          # Container image with containerlab + tools
│   ├── requirements.txt    # Python networking libraries
│   └── post-create.sh      # One-time setup script
├── labs/
│   └── 01-hello-world/
│       ├── topology.yml    # Containerlab topology: ceos1 <--> sonic1
│       └── configs/
│           └── ceos1.cfg   # cEOS startup configuration
├── Makefile                # Convenience targets (deploy, destroy, inspect, …)
└── README.md
```

---

## Prerequisites

| Platform | Requirement |
|---|---|
| macOS (Intel) | [Docker Desktop](https://www.docker.com/products/docker-desktop/) 4.x+ |
| macOS (Apple Silicon) | Docker Desktop 4.x+ with **Rosetta emulation enabled** (Settings → General → "Use Rosetta for x86/amd64 emulation") |
| Windows | [Docker Desktop](https://www.docker.com/products/docker-desktop/) with WSL2 backend |
| Linux | Docker Engine 24+ |
| Any | [VS Code](https://code.visualstudio.com/) + [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) |

> **System resources** — each lab node consumes RAM. Recommended: 16 GB RAM, 4+ CPU cores, 30 GB free disk.

> **Apple Silicon (ARM) note** — cEOS-lab has native ARM64 builds since 4.28, so prefer downloading the ARM64 variant from arista.com. SONiC VS is x86-only and runs via Rosetta 2 emulation; expect higher CPU usage and slower boot times compared to native.

---

## Step 1 — Open the Repository in the Dev Container

The dev container provides a pre-configured Linux environment with containerlab, Docker CLI, and Python networking tools already installed.

### Option A: VS Code (local)

1. Clone this repository:
   ```bash
   git clone https://gitlab.aristanetworks.com/tac-team/sonic-lab-workbook.git sonic-lab-workbook
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
2. Wait for the environment to build (first run ~3–5 minutes).
3. The integrated terminal is the lab environment.

> **Note for Codespaces** — Docker images (cEOS, SONiC) are not pre-loaded. You need to import them after the codespace starts. See [Step 2](#step-2--import-lab-images).

---

## Step 2 — Import Lab Images

Neither cEOS-lab nor SONiC VS is available on public registries — both must be imported manually. Run all commands **inside the dev container terminal**.

---

### 2a — cEOS-lab (Arista)

**Download**

1. Create a free account at [arista.com](https://www.arista.com).
2. Go to **Software Downloads → EOS → cEOS-lab**.
3. Download `cEOS-lab-<version>.tar.xz` (e.g., `cEOS-lab-4.32.0F.tar.xz`).

**Transfer into the dev container** (macOS / Linux host)

If working locally, the container shares the host Docker daemon, so you can import from the host terminal or from the VS Code terminal — both write to the same Docker image store.

**Import**

```bash
# Replace the filename with the version you downloaded
docker import cEOS-lab-4.32.0F.tar.xz ceos:4.32.0F
```

**Verify**

```bash
docker images | grep ceos
# Expected output:
# ceos   4.32.0F   <id>   <date>   <size>
```

> If you downloaded a different version, update the `image:` field in [labs/01-hello-world/topology.yml](labs/01-hello-world/topology.yml) accordingly.

---

### 2b — SONiC Virtual Switch

**Download**

SONiC VS images are built by the SONiC community CI pipeline. Two sources:

**Option 1 — sonic.software (recommended)**

Visit [sonic.software](https://sonic.software) and download the latest `docker-sonic-vs.gz` artifact for the `vs` platform.

**Option 2 — Azure DevOps build artifacts**

```bash
# List recent VS builds (requires Azure CLI, optional)
# Or download directly from the build UI:
# https://sonic-build.azurewebsites.net/ui/sonic/pipelines
```

**Load**

```bash
# If the file is a .gz (gzip-compressed tar)
docker load -i docker-sonic-vs.gz

# If the file has a different extension, Docker auto-detects the format:
docker load -i docker-sonic-vs.tar
```

**Tag** (if the loaded image has a non-descriptive tag)

```bash
# Check what tag was loaded
docker images | grep sonic

# If needed, retag to match topology.yml
docker tag <image-id> docker-sonic-vs:latest
```

**Verify**

```bash
docker images | grep sonic
# Expected output:
# docker-sonic-vs   latest   <id>   <date>   <size>
```

---

### 2c — Confirm both images are present

```bash
docker images | grep -E "ceos|sonic"
```

Expected output (exact tags may differ):

```
ceos              4.32.0F   abc123   2 days ago   1.2GB
docker-sonic-vs   latest    def456   1 week ago   1.8GB
```

---

## Step 3 — Deploy Lab 01: Hello World

The topology connects one cEOS node to one SONiC node with a single point-to-point link:

```
  ┌─────────────────┐          ┌─────────────────┐
  │     ceos1       │          │     sonic1      │
  │  (Arista EOS)   │          │    (SONiC VS)   │
  │                 │          │                 │
  │  Ethernet1      ├──────────┤  eth1           │
  │  192.168.1.1/30 │          │  192.168.1.2/30 │
  └─────────────────┘          └─────────────────┘
        │                              │
        └──── Management (172.20.20.0/24) ────┘
```

**Deploy**

```bash
clab deploy --topo labs/01-hello-world/topology.yml --reconfigure
```

Containerlab prints a summary table with each node's management IP once all containers are running.

Example output:

```
+---+-----------------------------+--------------+------------------------+-------+
| # | Name                        | Container ID | Image                  | State |
+---+-----------------------------+--------------+------------------------+-------+
| 1 | clab-01-hello-world-ceos1   | a1b2c3d4e5f6 | ceos:4.32.0F           | running |
| 2 | clab-01-hello-world-sonic1  | b2c3d4e5f6a1 | docker-sonic-vs:latest | running |
+---+-----------------------------+--------------+------------------------+-------+
```

**Check status**

```bash
clab inspect --all
```

---

## Step 4 — Access the Nodes

### ceos1 (Arista EOS CLI)

```bash
docker exec -it clab-01-hello-world-ceos1 Cli
```

Inside EOS:

```
ceos1> enable
ceos1# show interfaces Ethernet1
ceos1# show ip interface brief
ceos1# ping 192.168.1.2     ! ping sonic1
```

### sonic1 (SONiC bash shell)

```bash
docker exec -it clab-01-hello-world-sonic1 bash
```

Inside SONiC:

```bash
# Check interface status
show interfaces status

# Check IP configuration
show ip interfaces

# Ping ceos1
ping 192.168.1.1 -c 3
```

### SSH access (alternative)

Containerlab assigns management IPs from the `172.20.20.0/24` subnet. Find them with:

```bash
clab inspect --all
```

Then SSH directly (cEOS credentials: `admin` / `admin`):

```bash
ssh admin@172.20.20.X
```

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
ping 192.168.1.1 -I eth1 -c 3
```

A successful ping confirms the virtual link is operational.

---

## Step 6 — Tear Down

When you are done, destroy the lab to free resources:

```bash
clab destroy --topo labs/01-hello-world/topology.yml --cleanup
```

This removes all containers, virtual interfaces, and the management Docker network.

---

## Common containerlab Commands

```bash
# Deploy a topology
clab deploy --topo <topology.yml> --reconfigure

# List running nodes and management IPs
clab inspect --all

# Destroy a lab and clean up networks
clab destroy --topo <topology.yml> --cleanup

# Generate an interactive HTML topology diagram
clab graph --topo <topology.yml>
```

The [Makefile](Makefile) wraps these commands for multi-step workflows (e.g., setting LAB variables across deploy/destroy/inspect in one shot).

---

## Troubleshooting

### `clab deploy` fails: permission denied

The clab binary has file capabilities set (`cap_net_admin`, `cap_net_raw`, `cap_sys_admin`) so it runs without sudo inside the dev container. If you still see a permission error, verify the capabilities are intact:

```bash
getcap /usr/bin/containerlab
# Expected: /usr/bin/containerlab cap_net_admin,cap_net_raw,cap_sys_admin=eip
```

If missing, rebuild the dev container (Command Palette → "Dev Containers: Rebuild Container").

### Docker image not found

Ensure the image name and tag in `topology.yml` exactly match what is in your local Docker image store:

```bash
docker images
# Compare output with the image: fields in topology.yml
```

### cEOS takes long to boot

cEOS-lab typically takes 60–90 seconds to finish initializing. If `Cli` reports an error immediately after `clab deploy`, wait a moment and retry.

### SONiC takes long to boot

SONiC VS can take 2–3 minutes before all services are up. Check readiness with:

```bash
docker exec clab-01-hello-world-sonic1 sonic-cfggen --print-data 2>/dev/null | head -5
```

### Connectivity issues between nodes

Verify the link is present in both OS views:

```bash
# From ceos1 EOS CLI
show interfaces Ethernet1

# From sonic1 bash
ip link show eth1
```

### Codespaces: image files too large to upload

GitHub Codespaces has an upload size limit via the browser. For large images (>1 GB), use the [GitHub CLI](https://cli.github.com/) or consider hosting images in a private container registry and pulling them via `docker pull`.

---

## Resources

- [Containerlab documentation](https://containerlab.dev/quickstart/)
- [Containerlab cEOS kind](https://containerlab.dev/manual/kinds/ceos/)
- [Containerlab SONiC kind](https://containerlab.dev/manual/kinds/sonic-vs/)
- [Arista cEOS-lab download](https://www.arista.com/en/support/software-download)
- [SONiC project](https://sonic-net.github.io/SONiC/)
- [sonic.software image downloads](https://sonic.software)
