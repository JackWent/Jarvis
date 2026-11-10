---
name: safe-reboot
description: Use when a server, Proxmox or the Jarvis VM needs rebooting, or when Jarvis comes back after a planned reboot - follows the confirmation, snapshot, pending-reboot note and notify steps, and the post-reboot check.
---

# Safe reboot

## Before

1. **Confirm with the owner in this session** what will reboot and when. Explicit confirmation is required
   for Proxmox, Home Assistant, the router and the NAS. Approval passed on from another session doesn't count.
2. **If it's Proxmox or the Jarvis VM (Jarvis goes offline):** warn the owner that Jarvis will be offline.
   For Proxmox, every VM restarts.
3. **Snapshot or backup** each VM that's rebooting: `jarvis-snapshot create <server> pre-reboot`.
   (Proxmox itself can't be snapshotted; check its VMs' backups instead.)
4. **If Jarvis will go down,** write `/root/jarvis/state/pending-reboot.md`: why, what was done, what
   exactly to check after (services, versions, sensors), and what to do if it doesn't come back.
5. `notify -l info -t "Rebooting <what>" "<why>, back in ~N min"`.
6. **Schedule it, never instantly:** `shutdown -r +2` (on the target host). For a plain server that
   isn't Jarvis or Proxmox, `ssh <server> 'shutdown -r +1'` is fine once confirmed.

## After (or when a fresh session starts and pending-reboot.md exists)

1. Read `state/pending-reboot.md` and run every check it lists.
2. `jarvis-fleet-status` for the whole fleet: Proxmox VMs running, servers reachable, failed units.
3. Check the HA "<Name> Agent Online" and "<Name> Reboot Required" sensors (Home Assistant MCP).
4. Report with `notify` (ok/warn/fail) and in chat, failures included, then delete `pending-reboot.md`.
5. Remove the pre-reboot snapshots once all is well: `jarvis-snapshot delete <server> <name>`.
