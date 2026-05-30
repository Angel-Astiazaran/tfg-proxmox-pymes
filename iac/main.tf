terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.68.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://<PVE01_IP>:8006/"
  username = "root@pam"
  password = "<PASSWORD>"
  insecure = true
}

# --- VM 1: THE MONITOR (Safe Node) ---
resource "proxmox_virtual_environment_vm" "ubuntu_monitor" {
  name      = "ubuntu-monitor-01"
  node_name = "pve-02"

  clone {
    vm_id     = 9000
    node_name = "pve-01"
    full      = true
  }
  
  agent { enabled = true }
  cpu { cores = 1 }
  memory { dedicated = 1024 }

  initialization {
    ip_config {
      ipv4 {
        address = "<MONITOR_VM_IP>/<CIDR_MASK>"
        gateway = "<GATEWAY_IP>"
      }
    }
    user_data_file_id = "local:snippets/user-data-monitor.yaml"
  }
  
  network_device { bridge = "vmbr0" }
  
  disk {
    datastore_id = "vm-data"
    interface    = "scsi0"
    size         = 10
  }
  
  operating_system { type = "l26" }
}

# --- VM 2: THE TARGET (Sacrifice Node) ---
resource "proxmox_virtual_environment_vm" "ubuntu_target" {
  name      = "ubuntu-target-01"
  node_name = "pve-01"

  # Wait for VM 1 to finish to avoid cloning lock saturation in Proxmox
  depends_on = [proxmox_virtual_environment_vm.ubuntu_monitor]

  clone {
    vm_id     = 9000
    node_name = "pve-01"
    full      = true
  }
  
  agent { enabled = true }
  cpu { cores = 1 }
  memory { dedicated = 1024 }

  initialization {
    ip_config {
      ipv4 {
        address = "<TARGET_VM_IP>/<CIDR_MASK>"
        gateway = "<GATEWAY_IP>"
      }
    }
    user_data_file_id = "local:snippets/user-data-target.yaml"
  }
  
  network_device { bridge = "vmbr0" }
  
  disk {
    datastore_id = "vm-data"
    interface    = "scsi0"
    size         = 10
  }
  
  operating_system { type = "l26" }
}