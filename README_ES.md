# Zero-Touch Provisioning: Clúster Hiperconvergente HA (Proxmox + Ceph)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Language / Idioma:** [🇬🇧 English (README.md)](README.md)

Este repositorio contiene el código y los descriptores de infraestructura desarrollados para automatizar el despliegue de una arquitectura hiperconvergente de Alta Disponibilidad.

El objetivo principal es transformar servidores *Bare-Metal* en un clúster operativo con almacenamiento distribuido (Ceph) y máquinas virtuales desplegadas, reduciendo el tiempo de configuración y la intervención humana a **cero** tras el encendido inicial.

---
## Estructura del Repositorio

El proyecto está estructurado en tres fases continuas, automatizadas y desacopladas. A continuación se detalla el mapa completo de archivos:

```text
tfg-proxmox-zero-touch/
├── LICENSE                     # Licencia MIT de código abierto
├── README.md                   # Documentación global y guía de despliegue (Inglés)
├── README_ES.md                # Anexo oficial del TFG / Guía técnica (Español)
├── baremetal/                  # FASE 1: Instalación desatendida nativa de Proxmox
│   ├── answer-pve01-master.toml # Archivo de autoinstalación para el Nodo 1 (Líder)
│   ├── answer-pve02-basic.toml  # Plantilla de autoinstalación para el Nodo 2 (Esclavo)
│   ├── answer-pve03-basic.toml  # Plantilla de autoinstalación para el Nodo 3 (Esclavo)
│   └── proxmox-post-installation# Script post-hook para inyectar el demonio Systemd
├── ansible/                    # FASE 2: Orquestación del clúster hiperconvergente
│   └── tfg-orchestrator.sh     # Script maestro de orquestación (Ansible Local)
└── iac/                        # FASE 3: Infraestructura como Código (Declarativa)
    ├── main.tf                 # Descriptor de arquitectura Terraform (Proxmox BPG)
    ├── user-data-monitor.yaml  # Metadatos Cloud-Init para la VM de Telemetría (Monitor)
    └── user-data-target.yaml   # Metadatos Cloud-Init para la VM Objetivo (Target)
```
---

## 1. Requisitos Materiales

Para reproducir este laboratorio se requiere el siguiente hardware:
* **3 Servidores Físicos (Nodos):** Compatibles con virtualización de hardware (VT-x/AMD-V) y con al menos dos discos de almacenamiento cada uno (uno principal para el SO y otro secundario para el Pool de Ceph).
* **Adaptadores de Red:** Capacidad para establecer una red de gestión (Frontend) y una red dedicada y aislada para el tráfico de almacenamiento de Ceph (Backend).
* **4 Unidades USB (Pendrives):**
  * 3 USBs destinados al sistema de instalación base (uno por cada nodo).
  * 1 USB secundario destinado a inyectar la configuración y la Infraestructura como Código (IaC) en el Nodo Líder.

---

## 2. Personalización del Entorno (Variables)

Antes de preparar los medios físicos, es obligatorio adaptar el código a la topología de la red destino. Busque y modifique las siguientes etiquetas genéricas en los archivos correspondientes:

### Directorio `baremetal/` (Archivos de autoinstalación)

**1. `answer-pve0X-master.toml` (Para el Nodo 1 - Líder):**
* `<YOUR_SECRET_PASSWORD>`: Contraseña del usuario root del servidor.
* `<YOUR_ADMIN_EMAIL>`: Correo electrónico de contacto del administrador del clúster.
* `<YOUR_DOMAIN>`: Dominio interno o local de la red (Ej: `tfg.local`).
* `<PVE01_IP>/<CIDR_MASK>`: La IP estática del Nodo 1 acompañada de la máscara de subred (Ej: `192.168.1.51/24`).
* `<GATEWAY_IP>` y `<DNS_IP>`: Puerta de enlace y servidor DNS de la red.
* `<NETWORK_INTERFACE>`: El nombre lógico de la tarjeta de red física del servidor (Ej: `enp0s31f6`).
* `<OS_DISK_NAME>`: Identificador del disco duro físico donde se instalará Proxmox (Ej: `nvme0n1` o `sda`).

**2. `answer-pve0X-basic.toml` (Para los Nodos 2 y 3 - Esclavos):**
*(Indique que se deben crear dos copias de este archivo: una para el Nodo 2 y otra para el Nodo 3, y en cada una modificar lo siguiente)*:
* `pve-0X`: Cambiar la X por el número del nodo (2 o 3).
* `<PVE0X_IP>`: Poner la IP estática correspondiente al Nodo 2 o al Nodo 3.
* *Nota: El resto de parámetros (contraseña, gateway, disco, interfaz) deben ser idénticos a los definidos en el archivo master, asumiendo hardware homogéneo.*

### Directorio `ansible/` (Orquestación del clúster)

**3. `tfg-orchestrator.sh`:**
* `<PVE0X_IP>`: Direcciones IP de la red de gestión pública de los 3 nodos (Ej: `192.168.1.51`).
* `<CEPH_PVE0X_IP>`: Direcciones IP para la red privada y exclusiva de almacenamiento Ceph (Ej: `10.10.10.51`).
* `<YOUR_SECRET_PASSWORD>`: Contraseña root del hipervisor (debe ser la misma en todos los nodos).
* `<CEPH_NETWORK_CIDR>`: El rango completo de la red de almacenamiento con su máscara (Ej: `10.10.10.0/24`).
* `<MONITOR_VM_IP>`: La IP estática que se le asignará por Terraform a la máquina virtual que ejecuta la telemetría (Ej: `192.168.1.100`).

### Directorio `iac/` (Infraestructura como Código)

**4. `main.tf`:**
* `<PVE01_IP>`: La dirección IP del nodo principal (Líder) donde Terraform ejecutará las llamadas a la API de Proxmox.
* `<YOUR_SECRET_PASSWORD>`: La contraseña de root del clúster de Proxmox.
* `<MONITOR_VM_IP>/<CIDR_MASK>`: Dirección IP estática y máscara de subred para la máquina de telemetría (Ej: `192.168.1.100/24`).
* `<TARGET_VM_IP>/<CIDR_MASK>`: Dirección IP estática y máscara para la máquina objetivo de las pruebas (Ej: `192.168.1.101/24`).
* `<GATEWAY_IP>`: La puerta de enlace de la red donde residirán las máquinas virtuales.
* *Nota técnica: Los valores `node_name = "pve-01"` y `"pve-02"` deben coincidir exactamente con los nombres de host (hostnames) definidos durante la instalación Bare-Metal.*

**5. `user-data-monitor.yaml` y `user-data-target.yaml`:**
* `<VM_ADMIN_PASSWORD>`: La contraseña que se le asignará al usuario `tfgadmin` para acceder por SSH a las máquinas virtuales.
* `<TARGET_VM_IP>` *(Solo en monitor.yaml)*: La dirección IP de la máquina objetivo a la que el proxy inverso (Nginx) hará el polling de estado. **Importante:** Debe coincidir exactamente con la IP asignada a la máquina target en el archivo `main.tf`.

---

## 3. Preparación de los Medios Físicos (USB)

El despliegue se basa en la división lógica del sistema operativo y los *scripts* de orquestación para evitar conflictos en la lectura de particiones.

### A) Pendrives Base (Para los 3 Nodos)
Estos 3 pendrives contendrán únicamente el instalador del sistema operativo.
1. Descargue la ISO oficial de Proxmox VE.
2. Utilice una herramienta de flasheo (ej. Rufus o BalenaEtcher) para grabar la ISO en los 3 pendrives.
3. **Importante:** Si utiliza Rufus, seleccione obligatoriamente el **Modo DD** (grabación a nivel de bloques) para preservar el sector de arranque híbrido. No modifique estas unidades tras la grabación.

### B) El USB Orquestador (El "Doble Pendrive" para el Nodo 1)
Este cuarto pendrive actuará como el cerebro de la automatización. Debe ser formateado completamente desde cero.
1. Conecte el USB y elimine todas sus particiones.
2. **Partición 1 (Configuración de Instalación):**
   * Formato: **NTFS** (Crucial para superar el límite de 11 caracteres de FAT32).
   * Etiqueta de volumen obligatoria: **`PROXMOX-AUTO-CONF`**
   * Contenido: Copie aquí los archivos `answer-pve01-master.toml` (renombrado a `answer.toml`), `proxmox-post-installation` y `tfg-orchestrator.sh`.
3. **Partición 2 (Infraestructura como Código):**
   * Formato: **NTFS** o **ext4**.
   * Etiqueta de volumen obligatoria: **`TFG-FASE-3`**
   * Contenido: Copie aquí `main.tf`, `user-data-monitor.yaml`, `user-data-target.yaml` y la imagen `.img` original de Ubuntu Cloud.

---

## 4. Ejecución del Despliegue Zero-Touch

Una vez preparados los medios, el proceso es completamente desatendido:

1. **Nodos 2 y 3 (Esclavos):** Conecte uno de los Pendrives Base junto con un USB que contenga su respectivo `answer.toml` básico. Enciéndalos. Una vez finalizada la instalación y el reinicio, déjelos en la pantalla de *login*.
2. **Nodo 1 (Líder/Orquestador):** Conecte **simultáneamente** el Pendrive Base restante y el USB Orquestador (el del paso 3B). Encienda el servidor forzando el arranque desde el Pendrive Base.
3. **El Proceso Automático:**
   * El instalador detectará la partición `PROXMOX-AUTO-CONF`, formateará el disco e instalará el sistema.
   * Justo antes de reiniciar, inyectará `tfg-orchestrator.sh` como un servicio *systemd*.
   * Tras el primer arranque del disco duro, el script maestro tomará el control: configurará Ansible localmente, unirá a los Nodos 2 y 3, montará la red Ceph, desplegará la Infraestructura con Terraform, e inyectará las reglas de Alta Disponibilidad.

---

## 5. Monitorización y Health Checks

El despliegue finaliza ejecutando rutinas de validación integradas. Para monitorizar el estado en tiempo real durante la instalación, puede acceder por SSH al Nodo 1 y revisar el log maestro:

```bash
tail -f /var/log/tfg-orchestrator.log
```
