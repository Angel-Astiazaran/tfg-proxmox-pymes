# Zero-Touch Provisioning: High Availability Hyperconverged Cluster (Proxmox + Ceph)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Language / Idioma: [Castellano/Español (README_ES.md)](README_ES.md)

This repository contains the source code, playbooks, and infrastructure descriptors developed to completely automate the deployment of a High Availability (HA) hyperconverged architecture.

The core objective is to transform bare-metal servers into an operational infrastructure with distributed storage (Ceph) and automated virtual machines, reducing human configuration time to **zero** after the initial boot.

---

## Repository Structure

The project is structured into three continuous, automated, and decoupled stages. Below is the complete file mapping:

```text
tfg-proxmox-zero-touch/
├── LICENSE                     # MIT License open-source legal descriptor
├── README.md                   # Global documentation and deployment guide (English)
├── README_ES.md                # TFG Official Appendix / Technical guide (Spanish)
├── baremetal/                  # PHASE 1: Native Proxmox unattended installation
│   ├── answer-pve01-master.toml # Unattended installation file for the Primary/Leader node
│   ├── answer-pve02-basic.toml  # Unattended installation template for Slave Node 2
│   ├── answer-pve03-basic.toml  # Unattended installation template for Slave Node 3
│   └── proxmox-post-installation# Post-hook bash script to inject the Systemd daemon
├── ansible/                    # PHASE 2: Hyperconverged cluster orchestration
│   └── tfg-orchestrator.sh     # Master orchestration script (Ansible Local + Node wait loop)
└── iac/                        # PHASE 3: Declarative Infrastructure as Code
    ├── main.tf                 # Terraform architecture descriptor for Proxmox BPG Provider
    ├── user-data-monitor.yaml  # Cloud-Init metadata & configuration for the Telemetry VM
    └── user-data-target.yaml   # Cloud-Init metadata & configuration for the Target VM
```
---

## 1. Material Requirements

The following hardware and media are required to reproduce this infrastructure laboratory: 
* **3 Physical Servers (Nodes):** X86_64 virtualization-enabled hardware (VT-x/AMD-V) with at least two physical storage drives (one for the base OS, one dedicated to the Ceph OSD Pool). 
* **Network Interfaces:** Dual NIC topology is recommended: one for the public management network (Frontend) and an isolated, high-throughput network for internal Ceph replication storage traffic (Backend).
* **4 USB Flash Drives:**
  * 3 USB drives for the base OS automated installer (one per node).
  * 1 Secondary USB drive ("The Orchestrator USB") to inject configurations and IaC scripts into the Leader Node.

---
## 2. Environment Customization (Variables)

Prior to imaging physical drives, you must customize environment variables to match your local network topology. Replace the generic placeholders (`<...>`) in the following files:

### `baremetal/` Directory (OS Installation Profiles)

**1. `answer-pve01-master.toml` (Primary Leader Node):**
* `<YOUR_SECRET_PASSWORD>`: Root access credentials for the Proxmox VE hypervisor.
* `<YOUR_ADMIN_EMAIL>`: System administrator email address for critical alerts.
* `<YOUR_DOMAIN>`: Internal local DNS suffix zone (e.g., `tfg.local`).
* `<PVE01_IP>/<CIDR_MASK>`: Static IPv4 address and CIDR mask for Node 1 management (e.g., `192.168.1.51/24`).
* `<GATEWAY_IP>` / `<DNS_IP>`: Network gateway and primary DNS resolver.
* `<NETWORK_INTERFACE>`: Physical network interface card identifier (e.g., `enp0s31f6`).
* `<OS_DISK_NAME>`: Target drive block device for the Proxmox installation (e.g., `nvme0n1` or `sda`).

**2. `answer-pve0X-basic.toml` (Secondary Slave Nodes templates):**
*Modify the respective files for Node 2 and Node 3:*
* `pve-0X`: Ensure the hostnames are sequentially named (`pve-02`, `pve-03`).
* `<PVE0X_IP>`: Assign the unique management IP address for Node 2 or Node 3.
* *Note: Parameters like root passwords, gateways, and interfaces should match the master profile if the hardware is homogeneous.*

### `ansible/` Directory (Cluster Configuration)

**3. `tfg-orchestrator.sh`:**
* `<PVE0X_IP>`: Management IP addresses for all three clustered nodes (e.g., `192.168.1.51`, `192.168.1.52`, `192.168.1.53`).
* `<CEPH_PVE0X_IP>`: Isolated storage network IP allocations for backend replication (e.g., `10.10.10.51`).
* `<YOUR_SECRET_PASSWORD>`: Root cluster password specified during the Bare-Metal installation phase.
* `<CEPH_NETWORK_CIDR>`: The complete subnet block dedicated to Ceph storage traffic (e.g., `10.10.10.0/24`).
* `<MONITOR_VM_IP>`: Target internal static IP assigned to the Telemetry VM instance.

### `iac/` Directory (Declarative Infrastructure)

**4. `main.tf`:**
* `<PVE01_IP>`: Primary node IP endpoint where Terraform connects to the Proxmox API.
* `<YOUR_SECRET_PASSWORD>`: Superuser cluster password.
* `<MONITOR_VM_IP>/<CIDR_MASK>`: Static network allocation for the Telemetry web instance (e.g., `192.168.1.100/24`).
* `<TARGET_VM_IP>/<CIDR_MASK>`: Static network allocation for the High Availability victim instance (e.g., `192.168.1.101/24`).
* `<GATEWAY_IP>`: Local gateway address for virtual machine routing.

**5. `user-data-monitor.yaml` & `user-data-target.yaml`:**
* `<VM_ADMIN_PASSWORD>`: Admin login password for the automated `tfgadmin` Linux guest user account.
* `<TARGET_VM_IP>` *(Within monitor.yaml)*: Explicit backend destination IP where the Nginx reverse proxy routes async health telemetry polls.

---

## 3. Flash Drive Provisioning

The zero-touch methodology segregates the core installer from orchestration configurations to prevent block device locking or formatting race conditions.

### A) Base OS Flash Drives (Nodes 1, 2, and 3)
These units store raw hypervisor installation binaries.
1. Download the official Proxmox VE installation ISO image.
2. Burn the image across 3 separate USB sticks using tools like Rufus or BalenaEtcher.
3. **Critical:** If utilizing Rufus, you must select **DD Mode** to clone sectors raw, preserving the installer's hybrid partition markers.

### B) The Master Orchestrator USB Drive (Dual-Drive Setup for Node 1)
This fourth independent storage unit injects automation intelligence. It must be wiped and partitioned as follows:
1. Clear all previous partition layouts on the device.
2. **Partition 1 (Installation Automation Hook):**
   * File System: **NTFS** (Mandatory to support long labels; FAT12/16/32 limits labels to 11 characters).
   * Volume Label (Case-Sensitive): **`PROXMOX-AUTO-CONF`**
   * Files: Copy `answer-pve01-master.toml` (renamed to `answer.toml`), `proxmox-post-installation`, and `tfg-orchestrator.sh`.
3. **Partition 2 (Infrastructure as Code payload):**
   * File System: **NTFS** or **ext4**.
   * Volume Label (Case-Sensitive): **`TFG-FASE-3`**
   * Files: Copy `main.tf`, `user-data-monitor.yaml`, `user-data-target.yaml`, and the baseline raw Ubuntu Server Cloud Image (`.img`).

---

## 4. Executing the Zero-Touch Deployment

Once the flash drives are configured, the deployment executes without any physical human intervention:

1. **Boot Slave Nodes (Nodes 2 and 3):** Connect an OS installation drive along with its corresponding basic `answer.toml` profile to each server. Power them up and allow them to complete the automated Proxmox installation. Leave them running at the CLI login prompt.
2. **Boot Leader Node (Node 1):** Connect both the remaining OS installation flash drive and the **Master Orchestrator USB** into available USB ports on Node 1. Power on the system and force a USB boot sequence.
3. **The Automated Cycle:**
   * The installer identifies the `PROXMOX-AUTO-CONF` NTFS volume label, parses the instructions, formats the local disk, and flashes Proxmox.
   * Right before the installation transaction closes, `proxmox-post-installation` runs, injecting `tfg-orchestrator.sh` as a persistent **Systemd** startup daemon inside the system disk.
   * Node 1 reboots. Upon checking the network status, the orchestrator script runs, configures local Ansible, forces secondary nodes to join the secure Corosync mesh cluster, wipes secondary storage targets, constructs Ceph OSD devices, spins up Terraform to clone instances, and passes the targeted virtual machine to the automated cluster High Availability daemon.

---

## 5. Post-Deployment Validation & Health Checks

The automation loop finishes by executing a suite of native system checks. You can monitor the progress of the deployment by opening an SSH terminal session into Node 1 and tracking the system log file:

```bash
tail -f /var/log/tfg-orchestrator.log
```

When successful, the script logs an explicit HTTP 200 state check and prints a termination message. At this point, the hyperconverged cluster is completely active, and the resilience dashboard will be reachable via your web browser at: http://<MONITOR_VM_IP>.