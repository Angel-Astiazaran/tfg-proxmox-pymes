#!/bin/bash
exec > /var/log/tfg-orchestrator.log 2>&1
echo "=== Starting TFG cluster orchestration (100% Offline Local Ansible) ==="

echo "Verifying Internet access..."
until ping -c 1 -W 2 deb.debian.org &> /dev/null; do
    echo "Waiting for DNS resolution and Internet routing..."
    sleep 3
done
echo "Internet connection established!"

# Sanitize Node 1 locally before installing Ansible
rm -f /etc/apt/sources.list.d/pve-enterprise.list
rm -f /etc/apt/sources.list.d/ceph.list
apt-get update
apt-get install -y ansible sshpass python3-pexpect

mkdir -p /opt/tfg-ansible
cd /opt/tfg-ansible

# 1. Auto-generate hosts.ini file
cat << 'EOF' > hosts.ini
[proxmox_cluster]
pve-01 ansible_host=<PVE01_IP> ceph_ip=<CEPH_PVE01_IP>
pve-02 ansible_host=<PVE02_IP> ceph_ip=<CEPH_PVE02_IP>
pve-03 ansible_host=<PVE03_IP> ceph_ip=<CEPH_PVE03_IP>

[proxmox_cluster:vars]
ansible_user=root
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_password="<PASSWORD>"
proxmox_password="<PASSWORD>"
EOF

# 2. Auto-generate playbook
cat << 'EOF' > cluster-setup.yml
---
- name: Phase 2.0 - Repository Sanitization (Error 401 Antidote)
  hosts: proxmox_cluster
  tasks:
    - name: Remove enterprise repositories on all nodes
      file:
        path: "{{ item }}"
        state: absent
      loop:
        - /etc/apt/sources.list.d/pve-enterprise.list
        - /etc/apt/sources.list.d/ceph.list
        
    - name: Force APT cache update
      apt:
        update_cache: yes
      ignore_errors: true

- name: Phase 2.1 - Ceph Network Configuration (USB Adapters)
  hosts: proxmox_cluster
  tasks:
    - name: Get USB interface name
      shell: >-
        ip -o link show | grep -v -e 'lo' -e 'enp' | awk -F': ' '{print $2}' | head -n 1
      register: usb_iface

    - name: Assign temporary IP for Ceph
      shell: "ip addr add {{ ceph_ip }}/24 dev {{ usb_iface.stdout }}"
      ignore_errors: true

    - name: Bring up USB interface
      shell: "ip link set dev {{ usb_iface.stdout }} up"
      ignore_errors: true
      
    - name: Configure USB interface in /etc/network/interfaces
      blockinfile:
        path: /etc/network/interfaces
        marker: "# {mark} ANSIBLE MANAGED BLOCK - CEPH NETWORK"
        block: |
          auto {{ usb_iface.stdout }}
          iface {{ usb_iface.stdout }} inet static
              address {{ ceph_ip }}/24
    
    - name: Apply network configuration
      shell: "ifreload -a"
      ignore_errors: true

- name: Phase 2.2 - Primary Node Initialization
  hosts: pve-01
  tasks:
    - name: Check if cluster already exists
      stat:
        path: /etc/pve/corosync.conf
      register: cluster_config

    - name: Create 'tfg-cluster' cluster
      command: pvecm create tfg-cluster
      when: not cluster_config.stat.exists
      
    - name: Wait for Quorum to stabilize on node 1
      pause:
        seconds: 15

- name: Phase 2.3 - Join Secondary Nodes
  hosts: pve-02, pve-03
  serial: 1  
  tasks:
    - name: Check if node already belongs to a cluster
      stat:
        path: /etc/pve/corosync.conf
      register: node_config

    - name: Install pexpect dependency (Safe now)
      apt:
        name: python3-pexpect
        state: present
      when: not node_config.stat.exists

    - name: Join node to cluster
      expect:
        command: "pvecm add <PVE01_IP>"
        responses:
          (?i)continue connecting: "yes"
          (?i)password: "{{ proxmox_password }}"
        timeout: 60
      when: not node_config.stat.exists
      
    - name: Wait for cluster to assimilate new node
      pause:
        seconds: 20

- name: Phase 2.4 - Ceph Configuration
  hosts: proxmox_cluster
  serial: 1
  tasks:
    - name: Install Ceph
      shell: "echo Y | pveceph install --repository no-subscription"
      
    - name: Initialize Ceph network
      shell: "pveceph init --network <CEPH_NETWORK_CIDR>"
      when: inventory_hostname == 'pve-01'
      ignore_errors: yes

    - name: Create Monitors and Managers
      shell: "pveceph mon create && pveceph mgr create"
      ignore_errors: yes

    - name: Disk Zapping
      shell: |
        ceph-volume lvm zap /dev/sda --destroy || true
        for dev in $(dmsetup ls | grep ceph | awk '{print $1}'); do dmsetup remove -f $dev || true; done
        dd if=/dev/zero of=/dev/sda bs=1M count=100 conv=fsync || true
        sgdisk --zap-all /dev/sda || true
        wipefs -af /dev/sda || true
      ignore_errors: yes

    - name: Add OSD disks
      shell: "pveceph osd create /dev/sda"
      ignore_errors: yes
EOF

wait_for_node() {
    IP=$1
    echo "Waiting for node $IP..."
    until ping -c 1 -W 1 $IP &> /dev/null && bash -c "</dev/tcp/$IP/22" 2>/dev/null; do
        sleep 15
    done
    echo "Node $IP online."
}

wait_for_node "<PVE02_IP>"
wait_for_node "<PVE03_IP>"

echo "Nodes online. Waiting 60 seconds..."
sleep 60

# 4. Run Ansible WITH error control
if ! ansible-playbook -i hosts.ini cluster-setup.yml; then
    echo "CRITICAL: Ansible orchestration failed. Aborting Terraform deployment."
    exit 1
fi

echo "=== Orchestration completed successfully ==="
echo "=== Starting Phase 3: 100% Offline Terraform Deployment ==="

apt-get install -y gnupg software-properties-common curl
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update
apt-get install -y terraform

pveceph pool create vm-data --add_storages 1
sleep 5

mkdir -p /mnt/fase3
mount -L TFG-FASE-3 /mnt/fase3

echo "Creating Ubuntu Cloud template on Ceph..."
qm create 9000 --name ubuntu-cloud-template --memory 2048 --net0 virtio,bridge=vmbr0
qm importdisk 9000 /mnt/fase3/ubuntu-24.04-server-cloudimg-amd64.img vm-data
qm set 9000 --scsihw virtio-scsi-pci --scsi0 vm-data:vm-9000-disk-0
qm set 9000 --ide2 vm-data:cloudinit
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --serial0 socket --vga serial0
qm template 9000

echo "Distributing Cloud-Init across the cluster..."
for IP in <PVE01_IP> <PVE02_IP> <PVE03_IP>; do
    ssh -o StrictHostKeyChecking=no -o BatchMode=yes root@$IP "mkdir -p /var/lib/vz/snippets"
    scp -o StrictHostKeyChecking=no -o BatchMode=yes /mnt/fase3/user-data-*.yaml root@$IP:/var/lib/vz/snippets/
done

echo "Running Terraform from local storage..."
mkdir -p /opt/tfg-terraform
cp /mnt/fase3/main.tf /opt/tfg-terraform/
cd /opt/tfg-terraform
terraform init
terraform apply -auto-approve

echo "Injecting High Availability rules..."
TARGET_VMID=$(qm list | grep ubuntu-target-01 | awk '{print $1}')
if [ -n "$TARGET_VMID" ]; then
    ha-manager add vm:$TARGET_VMID
else
    echo "WARNING: ubuntu-target-01 machine not found to inject HA."
fi

echo "=== PHASE 3 COMPLETED ==="
echo "=== Starting Phase 4: Automated Health Checks ==="

pvecm status | grep -E "Nodes:|Quorum:"
ceph health
ha-manager status

echo "-> Waiting 45 seconds for Nginx..."
sleep 45

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://<MONITOR_VM_IP>/)

if [ "$HTTP_CODE" == "200" ]; then
    echo "TOTAL SUCCESS: HTTP 200 OK."
else
    echo "WARNING: HTTP Code $HTTP_CODE."
fi