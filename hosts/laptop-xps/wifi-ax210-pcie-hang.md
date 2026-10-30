# laptop-xps — Wi-Fi (Intel AX210) hangs after cold boot: fatal PCIe error

## Symptom

After some cold boots the Wi-Fi shows **no networks at all**:

- `nmcli device` lists `wlp58s0` as `unavailable`
- `nmcli device wifi list` returns an empty table
- NetworkManager log: `device (wlp58s0): Couldn't initialize supplicant
  interface: Timeout was reached`
- wpa_supplicant log: `Could not set interface wlp58s0 flags (UP):
  Connection timed out` / `Failed to initialize driver interface`
- `dmesg` (kernel):
  - `iwlwifi 0000:3a:00.0: AER: PCIe Bus Error: severity=Uncorrectable
    (Fatal), type=Inaccessible`
  - `iwlwifi 0000:3a:00.0: AER: can't recover (no error_detected callback)`
  - `Timeout waiting for hardware access (CSR_GP_CNTRL 0xffffffff)`

Everything else (wired USB-C ethernet, Tailscale, Bluetooth) works normally.

## Root cause (diagnosed 2026-10-30)

The iwlwifi **driver is not at fault** — the card's own firmware dies, and
the driver is just the first thing to notice.

The AX210 (`0000:3a:00.0`, CNVi, M.2 2230) is a small SoC: the driver talks
to its microcontroller over PCIe. At the *first* open of `wlp58s0` after a
cold boot (NetworkManager starting Wi-Fi, ~50 s in), the firmware issued a
DMA read that the IOMMU **blocked**:

```
DMAR: [DMA Read NO_PASID] Request device [0000:3a:00.0] fault addr 0xfea7c000
       [fault reason 0x06] PTE Read access is not set
```

(This host deliberately runs `intel_iommu=on iommu=force` — see the comment
in `hardware-configuration.nix`.) The firmware treats the blocked DMA as
unrecoverable and reports a **fatal PCIe AER error**, after which the card
stops answering the bus entirely (register reads return `0xffffffff`). Every
nl80211 command then times out — no supplicant, no iwd, no NetworkManager
configuration can revive a card that is silent on the PCIe link.

It is a firmware/BIOS/platform cold-boot timing bug, not a NixOS config
issue. On 2026-10-30 it happened once at boot and did **not** recur after a
driver rebind. Environment at the time: BIOS 2.21.0 (06/02/2022),
linux-zen 7.2.11, Intel firmware 89.ucode (linux-firmware via nixpkgs).

> Unrelated noise: the Thunderbolt 3 bridge (`0000:01:00.0`, Alpine Ridge)
> logs thousands of *correctable* AER errors per boot. Harmless, and not the
> Wi-Fi problem.

## Fix (no reboot)

Power-cycle the card's firmware by reloading the driver:

```sh
sudo modprobe -r iwlmvm iwlwifi
sudo modprobe iwlmvm
```

`wlp58s0` disappears and reappears; wpa_supplicant/NetworkManager pick it up
automatically (observed 2026-10-30; if a scan doesn't start,
`sudo systemctl restart wpa_supplicant`). A plain reboot does the same thing.

## If it starts recurring on every cold boot

In increasing order of invasiveness:

1. **BIOS update** — check <https://www.dell.com/support> for a newer XPS 13
   9360 BIOS; CNVi power-sequencing fixes land there.
2. **Linux-firmware** — keep nixpkgs updated so the AX210 firmware tracks the
   latest Intel release.
3. **`iommu=pt` instead of `iommu=force`** in
   `hardware-configuration.nix` (drop/replace the kernel option): VT-d stays
   on for KVM usage, but unassigned devices get identity mapping, so the
   strict DMA enforcement that tripped the firmware goes away. Trade-off:
   loses the DMA isolation the `iommu=force` comment describes.
4. **Replace the card** — if the pattern is chronic, the AX210 M.2 2230
   module may be intermittently failing; a new AX210/AX201 is a cheap part
   (the 9360 has a replaceable Wi-Fi M.2 slot).
