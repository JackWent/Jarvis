# CIS hardening (Ubuntu 26.04)

`cis-ubuntu-safe.sh` applies only the CIS items that don't change how a server is used. Run it on a
server as root, after a snapshot (`jarvis-snapshot create <host> cis-hardening`):

    scp hardening/cis-ubuntu-safe.sh <host>:/tmp/ && ssh <host> 'bash /tmp/cis-ubuntu-safe.sh; rm /tmp/cis-ubuntu-safe.sh'

Then check the server's own services, and `systemctl restart wazuh-agent` for a fresh SCA score
(policy `homelab_cis_ubuntu26-04`, see `wazuh/sca/`).

Applied 2026-10-24 to all Ubuntu servers (plex, gitlab-runner, unifi-server, immich, web-server, containers,
app, wazuh, bitwarden, gitlab-host with GITLAB_SSH=1, jarvis). Snapshots jarvis-cis-hardening-20261024-*;
immich is not a VM, so /root/etc-before-cis-20261024-2101.tgz there instead.
Proxmox (Debian 13) with PROXMOX=1 on 2026-10-24: score 43% -> 54%. /etc backup at
/root/etc-before-cis-20261024-2128.tgz on proxmox, copy in ~/jarvis/state/backups/ on Jarvis.

## Deliberately not done
| Item | Why |
| --- | --- |
| Root SSH login off, sshd AllowUsers, DisableForwarding | the owner keeps root login (Jarvis uses it); the owner's call |
| Firewall (ufw) | Needs a per-server port list; separate decision |
| Separate /home, /var, /var/log... partitions; /tmp noexec | Disk rebuild / breaks apt |
| Bootloader password, AppArmor enforce-all | Risk an unbootable or broken server |
| Password expiry, faillock lockout, shell timeout, root umask 027 | Change how the owner logs in and works; the owner's call |
| auditd, AIDE | Load and log volume; Wazuh FIM already covers files |
| `at` restricted to authorised users | The check only passes if the `at` package is installed (plus /etc/at.allow): adding a scheduler daemon to pass a check would make things worse |
| All log files 0640 (6.1.4.1) | Wazuh's regex also fails the login records (btmp/wtmp/lastlog are group utmp 0660/0664) and sysstat, apt and others recreate their files on rotation, so a one-off chmod reverts |
| Blocking NFS/FUSE/FAT modules | Plex media is NFS; /boot/efi is FAT |
| sudo `Defaults logfile`, sudo timeout check | sudo-rs has no logfile option and doesn't print its timeout; it logs to the journal |
| IPv6 halves of the network checks | IPv6 is disabled, so those sysctls don't exist (3 checks stay failed) |
| Password history: `required` vs `requisite` | Two CIS checks contradict each other; `requisite` used |

## Per-host behaviour built into the script
- Hosts that forward packets (Docker) keep `ip_forward` and their current `rp_filter`.
- `PROXMOX=1`: no /dev/shm noexec (QEMU/LXC), rp_filter left alone, /etc/issue kept (Proxmox puts the web UI address there), motd set, chrony user stated, IPv6 redirects/source routing off.
  Never on Proxmox: faillock (it would lock the web UI's root login), pve has its own firewall.
  Broken Debian 13 checks that can't pass: root L+P, ENCRYPT_METHOD SHA512+YESCRYPT, shadowed passwords (`[...]` regex), timesyncd vs chrony.
- `GITLAB_SSH=1` (gitlab-host): no SSH banner (it would print on every git command) and default MaxAuthTries.
- The `su` restriction sits after `pam_rootok`, so root can still `su`; the script tests this and backs out if not.
