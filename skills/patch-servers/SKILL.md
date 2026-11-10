---
name: patch-servers
description: Use when patching/updating Ubuntu servers in the homelab - snapshot first, install everything pending (phased and kept-back included), verify health, notify the result, then remove the snapshot.
---

# Patch servers

Guardrails: always snapshot or back up before patching. Never reboot Proxmox, Home Assistant,
the router or the NAS without explicit confirmation. Report every outcome with `notify -c patching` (#server-patching), failures included.

## For each server

1. **Check what's pending:** `jarvis-fleet-status <server>` (or the full fleet to choose servers).
2. **Snapshot:** `snap=$(jarvis-snapshot create <server> pre-patch)`. If it fails (disk type, not a
   Proxmox VM: immich isn't), stop and ask the owner how he wants that server backed up before patching.
3. **Patch:** `jarvis-patch --force-phased <server>`. The owner wants everything installed: phased updates
   forced, kept-back packages installed by name (the script does both). Log: /var/log/jarvis-patch/.
4. **Verify:** `jarvis-fleet-status <server>`: 0 updates pending, no failed units, SSH still answering.
   If the patch broke something, don't delete the snapshot; tell the owner, and offer a rollback
   (`qm rollback` on Proxmox needs his explicit OK).
5. **Reboot needed?** Don't reboot on your own. Tell the owner which servers need one and offer `safe-reboot`.
6. **Clean up:** once verified, `jarvis-snapshot delete <server> "$snap"`.

## Report

One `notify -c patching -l ok|warn|fail -t "Patching: <servers>"` (goes to #server-patching) with what was installed per server, reboot
needs and anything that failed, then the same summary in chat. Leftover old Jarvis snapshots can be
cleared with `jarvis-snapshot prune <server> 3`.

Order: do non-critical servers first; Bitwarden (password manager) and the App server `app` (customers) last
and one at a time. Never patch Home Assistant's OS this way; it updates through HA.
