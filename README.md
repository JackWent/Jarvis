# Jarvis

An always-on [Claude Code](https://claude.com/claude-code) session that looks after a homelab. It patches servers, takes snapshots first, checks fleet health every morning, talks to Home Assistant, and tells me on Discord what it did.

This repo is a cleaned-up copy of the scripts, systemd units and runbooks it runs on. The full story, with photos and the voice side, is in the post [Jarvis, the AI that runs my homelab](https://jackwent.co.uk/jarvis-ai-assistant-runs-my-homelab/).

Hostnames, addresses and personal details have been replaced with generic names, so treat everything here as a starting point to adapt, not something to run as it is.

## How it fits together

- **The session:** `jarvis-session` starts Claude Code inside tmux on a small Ubuntu VM. A systemd service keeps it running, and Claude's Remote Control makes it reachable from the Claude app on a phone or PC.
- **The tools:** small scripts the session calls instead of typing raw commands, so each action has guardrails (see below).
- **The runbooks:** `skills/` holds step-by-step instructions the assistant follows for patching, rebooting and fleet checks.
- **The timers:** systemd timers run the daily health check, the reminders and the pre-patch preparation.

## What's here

| Path | What it does |
| --- | --- |
| `bin/notify` | Sends a message to a Discord channel through a webhook |
| `bin/jarvis-fleet-status` | Read-only health check of every server: pending updates, reboots needed, disk, failed units, Proxmox VMs, Home Assistant |
| `bin/jarvis-patch` | Updates one known server over SSH, forces phased updates and installs kept-back packages |
| `bin/jarvis-snapshot` | Proxmox snapshots per server; only ever deletes snapshots it created itself |
| `bin/jarvis-ci-wait` | Waits for a GitLab pipeline and retries a job once if it failed on a one-off network error |
| `bin/jarvis-autopatch-prep`, `bin/jarvis-pre-reboot` | Save state and take a snapshot before the nightly patch run, and leave a note if a reboot happens |
| `bin/jarvis-remind` | Dated one-off reminders sent to Discord |
| `skills/` | Runbooks: `fleet-status`, `patch-servers`, `safe-reboot` |
| `systemd/` | Services and timers for the session, health check, reminders and pre-patch preparation |
| `hardening/cis-ubuntu-safe.sh` | A cautious subset of CIS Ubuntu hardening that won't lock you out |

## Guardrails that make it safe to leave running

- Always snapshot or back up before patching anything.
- Never reboot the hypervisor, Home Assistant, the router or the NAS without explicit confirmation.
- Locks, alarms and garage doors always need a yes.
- If a reboot would take the assistant itself offline, it writes down what to check first and reports back when it returns.
- Every maintenance job posts its outcome, successes and failures alike.
- Secrets live outside the repo.

## Adapting it

Edit the host lists at the top of `jarvis-fleet-status`, `jarvis-patch` and `jarvis-snapshot`, add your Discord webhook for `notify`, and point the runbooks in `skills/` at your own servers. The scripts assume SSH key access to each server and the Proxmox API for snapshots.

No licence is attached yet, so all rights are reserved until one is added. If you'd like to reuse something, get in touch via [jackwent.co.uk](https://jackwent.co.uk/get-in-touch/).
