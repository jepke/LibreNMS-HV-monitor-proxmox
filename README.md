# Proxmox HV Monitor Script for LibreNMS

A modular Bash script designed to feed VM and node-level metrics into **LibreNMS** via SNMP extend — fully compatible with the **LibreNMS HV-Monitor plugin** (`hv-monitor.inc.php`).

> 📡 Intended for use with LibreNMS’s `hv-monitor` SNMP extend configuration for Proxmox hosts.

---

## 🔍 Overview

This script queries the local Proxmox node using `pvesh`, reads `/proc` stats for VMs, and formats everything into a structured JSON block expected by **LibreNMS's Proxmox HV-Monitor module**.

It outputs to: `/etc/snmp/snmpd.conf.d/proxmox_hvmonitor.json`


This is the expected path used by `hv-monitor.inc.php` when added to your SNMP `extend` config.

---

## 🧰 Key Features

- 🖥️ Supports VM-level stats: CPU, memory, disk, network
- 📊 Collects node-level totals from `/proc` and `pvesh`
- 💾 Gathers per-disk I/O via Proxmox blockstat and `/proc/diskstats`
- 🌐 Optional NIC metrics via QEMU Guest Agent
- 🧪 Fully shell-based (no Python or Docker needed)
- 🐚 Verbose debug output with `--verbose` or `-V`

---

## 🧪 Project Context

This was built and tested on a **small standalone Proxmox node**, with no access to a medium or production cluster. It was created as a **weekend tinkering project**, mostly for fun and learning.

> ⚠️ Not guaranteed to work out of the box on multi-node or large clusters, though it can likely be extended.

---

## 📦 Output Format

Top-level JSON keys:

- `"hv"`: hypervisor name (e.g., `"proxmox"`)
- `"totals"`: node usage
- `"VMs"`: per-VM stats
- `"VMdisks"`: individual disk usage (not processed by hv-monitor atm)
- `"VMifs"`: reserved placeholder (not processed by hv-monitor atm)
- `"VMstatus"`: reserved placeholder (not processed by hv-monitor atm)

---

## 🛠 Setup

Make sure:
- SNMP extend is configured in `snmpd.conf`
  `extend hv-monitor /usr/bin/cat /etc/snmp/snmpd.conf.d/proxmox_hvmonitor.json`
- `jq` is installed
- Your Proxmox node can access `pvesh` and `/proc`
- QEMU Guest Agent is enabled on VMs (optional)

Run manually:
```bash
./proxmox_hv_monitor.sh
./proxmox_hv_monitor.sh --verbose
```

### 🔗 Related Projects & Documentation

- HV-Monitor GitHub: [https://github.com/VVelox/HV-Monitor](https://github.com/VVelox/HV-Monitor)  
- LibreNMS HV Monitor Docs: [https://docs.librenms.org/Extensions/Applications/HV%20Monitor/](https://docs.librenms.org/Extensions/Applications/HV%20Monitor/)
