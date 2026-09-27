# Infrastructure Documentation

## Overview

This document describes the user's homelab network topology and data replication setup.

## Hardware

### Synology NAS Units

| Device | Model | Role |
|--------|-------|------|
| NAS-1 | DS718+ | Primary storage / main NAS |
| NAS-2 | DS213air | Secondary storage / backup device |

### Laptops

Multiple laptops (specific models not specified). All run the same software stack as the Synology units.

## Network Hardware (Cable / FRITZ!)

### Cable Internet (ISP: CGA)

| Device | Role |
|--------|------|
| CGA / Technicolor | DOCSIS modem (cable WAN) |
| FRITZ!Box 6670 | Current main router · FRITZ!Mesh master · DVB-C cable TV tuner |
| FRITZ!Box 7530AX | FRITZ!Mesh member — joined via a **LAN uplink** to the master (a FRITZ!Box can't do a wireless repeater backhaul) |
| FRITZ!Repeater 3000 AX | FRITZ!Mesh node — wired backhaul to the 6670 over MoCA 2.5 · **can also serve as Mesh Master** |
| FRITZ!Repeater 1200 AX | FRITZ!Mesh node |

> **Mesh master:** the Mesh Master is the FRITZ! device that provides the home network / is connected to the router or ISP device. It does **not** have to be a FRITZ!Box — a FRITZ!Repeater can also be the Mesh Master (e.g. attached directly to the router or the ISP's modem/ONT). In this setup the 6670 is the master today; the **3000 AX could take that role instead** if desired (e.g. living-room placement is poorer than the office).

### Coax Backbone (MoCA 2.5)

Two **goCoax MoCA 2.5** adapters carry a wired backhaul over the existing home coax between floors:

- **Living room (floor 0)**: FRITZ!Box 6670 ↔ goCoax MoCA adapter #1
- **Office (floor +1)**: goCoax MoCA adapter #2 ↔ FRITZ!Repeater 3000 AX

A coax splitter with proper **MoCA / PoE filters** keeps MoCA, DOCSIS, and DVB-C signals from interfering with each other or leaking onto the CGA line.

Topology (WAN + backhaul):

```
CGA coax line
  └─ splitter + MoCA/PoE filters
       ├── Technicolor (DOCSIS modem) ── Ethernet ─┐
       └── DVB-C ──────────────────────────────────┐│
                                                   ▼▼
Floor 0 (living room)                     FRITZ!Box 6670  (router + FRITZ!Mesh master)
                                                   │
                                           goCoax MoCA 2.5 #1
                                                   │
                                     ══════ coax ══════
                                                   │
                                           goCoax MoCA 2.5 #2
                                                   │ Ethernet
Floor +1 (office)                   FRITZ!Repeater 3000 AX  (mesh node)
                                   (+ FRITZ!Repeater 1200 AX / FRITZ!Box 7530AX as LAN mesh member)
```

> Note: the 6670 is directly wired to the CGA coax drop. The 7530AX joins the mesh as a **LAN-wired mesh member**; the 3000 AX has a **wired (MoCA) backhaul** and bridges the floors.

## Network & Connectivity

### Tailscale

All machines in the infrastructure run **Tailscale**, providing a private mesh network overlay.

- Enables secure, encrypted communication between all devices regardless of physical location
- Provides stable private IP addresses for service discovery and API access
- Serves as the primary connectivity layer for cross-device services

### Syncthing

All machines also run **Syncthing** for file-level data replication.

> ⚠️ **Important:** Syncthing in this setup is used for **replication**, not backup.
>
> - Replication = continuous mirroring between devices
> - Does NOT provide version history or retention
> - A deletion synced to one device propagates to all
> - Not a substitute for a proper backup strategy

### Failover / Backup WAN (4G)

Goal: keep the LAN online when the CGA cable WAN drops, using a 4G dongle.

- **NOT via the 3000 AX.** As Mesh Master a FRITZ!Repeater needs a **wired LAN uplink** to the existing router (AVM KB #3795). FRITZ!Repeaters have no router/NAT or WiFi-as-WAN function; their only WiFi-uplink mode ("conventional wireless extender", KB #3487) merely re-broadcasts the dongle's own hotspot network — not this LAN, and not a mesh.
- **Correct place = the 6670 (router).** The 6670 Cable has a USB port and FRITZ!OS **fallback protection** (AVM KB #76):
  - Plug the 4G dongle into the 6670's USB port (USB tethering / LTE stick) → FRITZ!OS auto-falls back to mobile when the cable WAN drops.
  - Alternatively, FRITZ!OS can use a "mobile network router" connected via LAN cable as the fallback source.
- **Caveat:** USB tethering requires the dongle to expose a USB/RNDIS mode. A WiFi-only hotspot needs a WiFi-as-WAN bridge device (e.g. a travel router / OpenWrt box) in front of the router.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                     Tailscale Mesh                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │  Synology    │  │  Synology    │  │   Laptop A   │   │
│  │  DS718+      │  │  DS213air    │  │              │   │
│  │  (Primary)   │  │  (Secondary) │  │              │   │
│  │  Syncthing   │◄──┤Syncthing    │◄──┤ Syncthing   │   │
│  └──────────────┘  └──────────────┘  └──────────────┘   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │   Laptop B   │  │   Laptop C   │  │   Laptop D   │   │
│  │              │  │              │  │              │   │
│  │ Syncthing    │  │ Syncthing    │  │ Syncthing    │   │
│  └──────────────┘  └──────────────┘  └──────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## Key Characteristics

- **Replication, not backup**: Data is mirrored in real-time but there is no redundancy against logical deletion or simultaneous device failure.
- **Tailscale-first networking**: All inter-device communication goes through the Tailscale overlay for consistency and security.
- **Homogeneous software stack**: Same services (Syncthing) run on all nodes, simplifying maintenance and discovery.

## Future Considerations

If you want to add true backup resilience:

1. Configure Syncthing with a dedicated "backup" folder that syncs to both NAS units
2. Consider adding versioned backups to an offsite location (e.g., object storage, another physical location)
3. Document retention policies for each data tier

## Related Files

- `infra.md` — this file
- Potentially: `.config/opencode/opencode.json` for tooling configuration
- Potentially: NixOS modules in `roles/`, `services/`, or `desktop/` if you want to declaratively manage Tailscale/Syncthing configs via Nix
