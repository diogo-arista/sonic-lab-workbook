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

**Option 1 — Download script (recommended)**

A script is provided that queries [sonic.software](https://sonic.software) for the latest build, downloads it, and loads it into Docker in one step:

```bash
# Download and load the latest stable release branch
bash scripts/get-sonic-vs.sh --load

# List all available branches first
bash scripts/get-sonic-vs.sh --branch list

# Pin a specific release branch
bash scripts/get-sonic-vs.sh --branch 202411 --load
```

Or via Make:

```bash
make get-sonic                         # latest release branch
SONIC_BRANCH=202411 make get-sonic     # specific branch
```

**Option 2 — Manual download**

Visit [sonic.software](https://sonic.software) or the [Azure DevOps build UI](https://sonic-build.azurewebsites.net/ui/sonic/pipelines) and download `docker-sonic-vs.gz`, then:

```bash
docker load -i docker-sonic-vs.gz
docker tag <loaded-image-id> docker-sonic-vs:latest
```

> **Pick the right file.** The SONiC build produces two similarly named files:
> - `docker-sonic-vs.gz` — Docker image tarball. **This is what you need.**
> - `sonic-vs.img.gz` — Raw KVM/QEMU disk image. `docker load` will reject it with `invalid tar header`.

**Verify**

```bash
docker images | grep sonic
# docker-sonic-vs   latest   <id>   <date>   ~800MB
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
  │  mgmt: .11      │          │  mgmt: .12      │
  │                 │          │                 │
  │  Ethernet1      ├──────────┤  Ethernet0      │
  │  192.168.1.1/30 │          │  192.168.1.2/30 │
  └─────────────────┘          └─────────────────┘
        │                              │
        └──── Management 172.20.20.0/24 ──────┘
```

> **SONiC interface naming** — containerlab assigns Linux interface names (`eth0`, `eth1`, …) to the container. Inside SONiC, data interfaces are named `Ethernet0`, `Ethernet4`, `Ethernet8`, … (incrementing by 4 lanes per port for the Force10-S6000 hwsku). The mapping is:
> - `eth0` → management (connected to containerlab mgmt network)
> - `eth1` → `Ethernet0` (first data port)
> - `eth2` → `Ethernet4` (second data port)

**Deploy**

```bash
clab deploy --topo labs/01-hello-world/topology.yml --reconfigure
```

The topology uses `prefix: ""` so container names are simply `ceos1` and `sonic1`. Containerlab prints a summary table with management IPs once all containers are running:

```
+---+--------+----+--------------+------------------------+---------+----------------+
| # | Name   | .. | Container ID | Image                  | State   | IPv4 Address   |
+---+--------+----+--------------+------------------------+---------+----------------+
| 1 | ceos1  |    | a1b2c3d4e5f6 | ceos:latest            | running | 172.20.20.11/24|
| 2 | sonic1 |    | b2c3d4e5f6a1 | docker-sonic-vs:latest | running | 172.20.20.12/24|
+---+--------+----+--------------+------------------------+---------+----------------+
```

**Check status**

```bash
clab inspect --topo labs/01-hello-world/topology.yml
```

**If SONiC interface IP is not applied after boot**, re-apply the startup config manually:

```bash
docker cp labs/01-hello-world/configs/sonic1-config.json sonic1:/etc/sonic/config_db.json
docker exec sonic1 sudo config reload -y
```

---

## Step 4 — Access the Nodes

### ceos1 (Arista EOS CLI)

```bash
docker exec -it ceos1 Cli
```

Inside EOS:

```
ceos1> enable
ceos1# show interfaces Ethernet1
ceos1# show ip interface brief
ceos1# ping 192.168.1.2     ! ping sonic1 Ethernet0
```

### sonic1 (SONiC bash shell)

```bash
docker exec -it sonic1 bash
```

Inside SONiC:

```bash
# Check interface and IP status
show interfaces status
show ip interfaces

# Ping ceos1 Ethernet1
ping 192.168.1.1 -c 3
```

### SSH access

Management IPs are static (defined in `topology.yml`):

| Node   | Management IP  | Credentials   |
|--------|---------------|---------------|
| ceos1  | 172.20.20.11  | admin / admin |
| sonic1 | 172.20.20.12  | admin / admin |

```bash
ssh admin@172.20.20.11   # ceos1
ssh admin@172.20.20.12   # sonic1
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
ping 192.168.1.1 -I Ethernet0 -c 3
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

## SONiC VS Configuration Architecture

Understanding how SONiC configuration works is essential for future labs.

### Two separate config files

SONiC uses `docker_routing_config_mode = split-unified` in this project. That means configuration is split into two independent files:

| File | Purpose |
|---|---|
| `/etc/sonic/config_db.json` | System state: ports, interfaces, VLANs, VXLAN tunnels, device metadata |
| `/etc/sonic/frr/frr.conf` | Routing protocols: BGP neighbors, EVPN, route maps, prefix lists |

In split-unified mode, SONiC will **never overwrite** `frr.conf` from ConfigDB — you own it completely. This is the right approach for labs and matches production deployments.

### Applying changes

**ConfigDB changes** (interfaces, VLANs, etc.):
```bash
docker exec sonic1 sudo config reload -y
```

**FRR changes** (BGP, routing):
```bash
docker exec sonic1 vtysh -f /etc/sonic/frr/frr.conf
# Or interactively:
docker exec -it sonic1 vtysh
```

### SONiC VS virtual switch quirk — ebtables

SONiC ships with ebtables rules designed for hardware ASIC switches. On virtual switches, these rules **block all forwarded traffic** silently. The topology applies this fix automatically via `exec` on container start:

```bash
ebtables -D FORWARD -j DROP
```

If traffic between nodes is not flowing after deploy, verify the rule is gone:
```bash
docker exec sonic1 ebtables -L FORWARD
# Should show: no rules
```

---

## Common containerlab Commands

```bash
# Deploy a topology
clab deploy --topo <topology.yml> --reconfigure

# List running nodes and management IPs for a specific lab
clab inspect --topo <topology.yml>

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
