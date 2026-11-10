---
name: fleet-status
description: Use when the owner asks how the servers/homelab are doing, what needs updates or attention, or after maintenance to confirm health - runs the read-only fleet check across every server, Proxmox, Home Assistant and the App backups and explains what needs doing.
---

# Fleet status

Run `jarvis-fleet-status` (add a server name, e.g. `jarvis-fleet-status wazuh`, for just one).
It's read-only and takes a few seconds. Exit code 1 means something needs attention.

It checks: every server reachable over SSH, pending apt updates, reboot required, root disk use
(>= 85% flagged), failed systemd units; Proxmox VMs that should be running (Ubuntu-Desktop and
Win10 are normally off) and storage; Home Assistant core/OS/supervisor/app updates; App
platform backup result and age, and failed workspace backups; Jarvis's own memory backup.

A timer runs it daily at 07:30 with `--notify`, posting to `#jarvis` only when something needs attention.

## Turning results into action

- Updates pending: offer the `patch-servers` skill.
- Reboot required: offer `safe-reboot` (always asks first; Proxmox/HA/router/NAS need explicit confirmation).
- Failed units: read `journalctl -u <unit> -n 20` on that server before proposing anything.
- Unreachable: check whether it's SSH (key/permissions) or the host is down (Proxmox `qm list`, HA "<Name> Agent Online" sensor).
- Home Assistant updates: tell the owner; update from HA unless he asks.
- Backup problems: App admin portal, Backups page.

Explain in plain words what each finding means and what you'd do. Don't fix things unasked.
