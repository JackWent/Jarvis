#!/usr/bin/env bash
# CIS hardening for the homelab's Ubuntu 26.04 servers: only the items that don't change how a
# server is used. Runs ON the server as root (copied there by jarvis-harden). Safe to re-run.
#
# Deliberately NOT done (and why) - see hardening/README.md:
#   root SSH login (Jarvis uses it), firewall, separate partitions, /tmp noexec, bootloader password,
#   AppArmor enforce-all, password expiry/lockout, `at` (the check wants the package installed), log file modes, auditd, AIDE, root umask, shell timeout,
#   blocking NFS/FUSE/FAT modules, sudo logfile (sudo-rs has no such option).
set -uo pipefail
say() { printf '  %-34s %s\n' "$1" "$2"; }
changed=()

# --- packages -------------------------------------------------------------------------------
# telnet/ftp clients (CIS 2.3.x). ubuntu-standard is a metapackage that only pulls them in.
rm_pkgs=$(dpkg-query -W -f='${Status} ${Package}\n' telnet inetutils-telnet ftp tnftp 2>/dev/null | awk '/install ok installed/{print $4}' | tr '\n' ' ')
if [ -n "$rm_pkgs" ]; then
  DEBIAN_FRONTEND=noninteractive apt-get purge -y -q $rm_pkgs >/dev/null && say "telnet/ftp clients" "removed: $rm_pkgs"; changed+=(packages)
else say "telnet/ftp clients" "already absent"; fi
for p in apparmor-utils libpam-pwquality; do
  if ! dpkg-query -W -f='${Status}' $p 2>/dev/null | grep -q "install ok installed"; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q $p >/dev/null && say "$p" "installed"
  else say "$p" "already installed"; fi
done

# --- crash reports and core dumps (1.5.x) ------------------------------------------------------
if [ -f /etc/default/apport ]; then sed -i 's/^enabled=1/enabled=0/' /etc/default/apport; fi
systemctl unmask apport.service >/dev/null 2>&1; systemctl disable --now apport.service >/dev/null 2>&1   # CIS check wants 'disabled', not 'masked'
say "apport (crash reporter)" "disabled"
echo "* hard core 0" > /etc/security/limits.d/60-cis-core.conf
echo "fs.suid_dumpable = 0" > /etc/sysctl.d/60-cis-coredump.conf
say "core dumps" "restricted"

# --- network (3.3.x): IPv4 only, IPv6 is disabled on these hosts --------------------------------
cat > /etc/sysctl.d/60-cis-network.conf <<'EOF'
# CIS 3.3.x (Jarvis). These hosts route nothing and have one network interface.
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
EOF
if [ "$(sysctl -n net.ipv4.ip_forward)" = 1 ] || command -v docker >/dev/null || command -v containerd >/dev/null; then
  # Docker (or anything else routing) needs forwarding, and strict rp_filter can upset container networks.
  sed -i -E '/^net\.ipv4\.(ip_forward|conf\.(all|default)\.rp_filter) /d' /etc/sysctl.d/60-cis-network.conf
  note=" (forwarding host: ip_forward and rp_filter left as they were)"
fi
if [ "${PROXMOX:-0}" = 1 ]; then
  sed -i -E '/^net\.ipv4\.conf\.(all|default)\.rp_filter /d' /etc/sysctl.d/60-cis-network.conf
  note=" (hypervisor: rp_filter left as it was)"
fi
if [ -d /proc/sys/net/ipv6 ]; then
  printf '%s\n' "net.ipv6.conf.all.accept_redirects = 0" "net.ipv6.conf.default.accept_redirects = 0" \
    "net.ipv6.conf.all.accept_source_route = 0" "net.ipv6.conf.default.accept_source_route = 0" >> /etc/sysctl.d/60-cis-network.conf
fi
sysctl -q --system >/dev/null 2>&1; say "network sysctls" "applied${note:-}"

# --- unused network protocols (3.2.x) -------------------------------------------------------
: > /etc/modprobe.d/60-cis-net-protocols.conf
for m in dccp tipc rds sctp; do
  printf 'install %s /bin/false\nblacklist %s\n' $m $m >> /etc/modprobe.d/60-cis-net-protocols.conf
  modprobe -r $m 2>/dev/null
done
say "dccp/tipc/rds/sctp modules" "blocked"

# --- /dev/shm noexec (1.1.2.2.x) ----------------------------------------------------------------
if [ "${PROXMOX:-0}" = 1 ]; then say "/dev/shm" "skipped (QEMU/LXC use it)"
elif ! grep -qE '^\S+\s+/dev/shm\s' /etc/fstab; then
  echo "tmpfs /dev/shm tmpfs defaults,nodev,nosuid,noexec 0 0" >> /etc/fstab
fi
[ "${PROXMOX:-0}" = 1 ] || { mount -o remount,nodev,nosuid,noexec /dev/shm && say "/dev/shm" "nodev,nosuid,noexec"; }

# --- cron (2.4.1.x) --------------------------------------------------------------------------
chown root:root /etc/crontab && chmod 600 /etc/crontab
for d in /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d; do
  [ -d $d ] && chown root:root $d && chmod 700 $d
done
users=$(ls /var/spool/cron/crontabs 2>/dev/null | tr '\n' ' ')
{ echo root; for u in $users; do [ "$u" != root ] && echo "$u"; done; } > /etc/cron.allow
chown root:root /etc/cron.allow; chmod 640 /etc/cron.allow
say "cron" "permissions tightened; cron.allow: root ${users/root/}"

# --- banners (1.7.x) -------------------------------------------------------------------------
BANNER="Authorised access only. Activity on this system is monitored and logged."
files="/etc/issue /etc/issue.net"
# Proxmox writes the web UI address into /etc/issue for the console; keep that, set motd instead.
[ "${PROXMOX:-0}" = 1 ] && files="/etc/issue.net /etc/motd"
for f in $files; do echo "$BANNER" > $f; chown root:root $f; chmod 644 $f; done
say "login banners" "set ($files)"

# --- SSH (5.1.x); root login is left as it is ---------------------------------------------------
cp -p /etc/ssh/sshd_config /etc/ssh/sshd_config.bak-cis 2>/dev/null
cat > /etc/ssh/sshd_config.d/10-cis.conf <<'EOF'
# CIS 5.1.x (Jarvis). Loaded before 50-cloud-init.conf; the first value of a setting wins.
Banner /etc/issue.net
ClientAliveInterval 15
ClientAliveCountMax 3
LoginGraceTime 60
MaxAuthTries 4
MaxStartups 10:30:60
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
EOF
if [ "${GITLAB_SSH:-0}" = 1 ]; then
  # git over SSH: a banner prints on every git command; several offered keys can exceed MaxAuthTries.
  sed -i -E '/^(Banner|MaxAuthTries) /d' /etc/ssh/sshd_config.d/10-cis.conf
fi
chmod 600 /etc/ssh/sshd_config /etc/ssh/sshd_config.d/10-cis.conf
if sshd -t; then systemctl reload ssh 2>/dev/null || systemctl reload sshd; say "sshd" "hardened and reloaded"
else rm -f /etc/ssh/sshd_config.d/10-cis.conf; say "sshd" "CONFIG TEST FAILED - change removed"; fi

# --- sudo / su (5.2.x, 5.3.x) -------------------------------------------------------------------
printf 'Defaults timestamp_timeout=15\n' > /tmp/60-cis-timeout
if visudo -cf /tmp/60-cis-timeout >/dev/null 2>&1; then
  install -m 440 -o root -g root /tmp/60-cis-timeout /etc/sudoers.d/60-cis-timeout; say "sudo timeout" "15 minutes"
else say "sudo timeout" "skipped (not accepted by this sudo)"; fi
rm -f /tmp/60-cis-timeout
getent group sugroup >/dev/null || groupadd sugroup
# The pam_wheel line must come AFTER pam_rootok, so root itself can still su (scripts rely on it).
sed -i '/^auth\s\+required\s\+pam_wheel\.so use_uid group=sugroup/d' /etc/pam.d/su
sed -i '0,/^auth\s\+sufficient\s\+pam_rootok\.so.*/s//&\nauth       required   pam_wheel.so use_uid group=sugroup/' /etc/pam.d/su
# Test with root, not a system account: su to a system user raises Wazuh rule 40101 (level 12).
if timeout 5 su -s /bin/true root </dev/null >/dev/null 2>&1; then
  say "su" "restricted to empty group sugroup (use sudo); root su ok"
else
  sed -i '/^auth\s\+required\s\+pam_wheel\.so use_uid group=sugroup/d' /etc/pam.d/su
  say "su" "ROOT SU FAILED - restriction removed again"
fi

# --- PAM password rules (5.3.x): apply only when a password is changed -------------------------
# The CIS checks read only the main pwquality.conf, so the settings go there (and nowhere else).
rm -f /etc/security/pwquality.conf.d/60-cis.conf
setpw() { if grep -qE "^\s*#?\s*$1\b" /etc/security/pwquality.conf; then sed -i -E "s|^\s*#?\s*$1\b.*|$2|" /etc/security/pwquality.conf; else echo "$2" >> /etc/security/pwquality.conf; fi; }
setpw difok "difok = 2"; setpw minlen "minlen = 14"; setpw minclass "minclass = 4"; setpw maxrepeat "maxrepeat = 3"
setpw maxsequence "maxsequence = 3"; setpw enforcing "enforcing = 1"; setpw enforce_for_root "enforce_for_root"
if [ ! -f /usr/share/pam-configs/pwhistory ]; then
  cat > /usr/share/pam-configs/pwhistory <<'EOF'
Name: pwhistory password history checking
Default: yes
Priority: 1023
Password-Type: Primary
Password:
	requisite	pam_pwhistory.so remember=24 enforce_for_root try_first_pass use_authtok
EOF
fi
# nullok: no account here has an empty password, so this only closes the door.
sed -i 's/\s*nullok//' /usr/share/pam-configs/unix
DEBIAN_FRONTEND=noninteractive pam-auth-update --enable unix pwquality pwhistory --force >/dev/null 2>&1
grep -q pam_pwquality /etc/pam.d/common-password && grep -q pam_pwhistory /etc/pam.d/common-password &&
  ! grep -q nullok /etc/pam.d/common-auth && say "PAM password rules" "pwquality, history 24, no nullok" ||
  say "PAM password rules" "CHECK /etc/pam.d/common-*"
touch /etc/security/opasswd /etc/security/opasswd.old
chown root:root /etc/security/opasswd /etc/security/opasswd.old; chmod 600 /etc/security/opasswd /etc/security/opasswd.old

# --- logging (6.1.x, 6.2.x) -------------------------------------------------------------------
# Set in journald.conf itself: the CIS check requires each value there, not only in a drop-in.
rm -f /etc/systemd/journald.conf.d/60-cis.conf
for kv in SystemMaxUse=1G SystemKeepFree=2G RuntimeMaxUse=200M RuntimeKeepFree=50M MaxFileSec=1month; do
  k=${kv%%=*}
  if grep -qE "^#?$k=" /etc/systemd/journald.conf; then sed -i -E "s|^#?$k=.*|$kv|" /etc/systemd/journald.conf
  else sed -i "/^\[Journal\]/a $kv" /etc/systemd/journald.conf; fi
done
systemctl restart systemd-journald; say "journald" "size capped (1G)"
if [ -d /etc/rsyslog.d ]; then
  echo '$FileCreateMode 0640' > /etc/rsyslog.d/10-cis-filemode.conf
  rsyslogd -N1 >/dev/null 2>&1 && systemctl restart rsyslog && say "rsyslog" "new files 0640"
fi

# --- chrony (2.3.3.x): state the user explicitly (it already runs as _chrony) ---------------------
if [ -f /etc/chrony/chrony.conf ] && ! grep -qE '^\s*user\s+_chrony' /etc/chrony/chrony.conf; then
  echo "user _chrony" >> /etc/chrony/chrony.conf
  chronyd -p -f /etc/chrony/chrony.conf >/dev/null 2>&1 && systemctl restart chrony && say "chrony" "user _chrony" ||
    { sed -i '/^user _chrony$/d' /etc/chrony/chrony.conf; say "chrony" "config test failed - left as it was"; }
fi

# --- inactive password lock (5.4.1.5) --------------------------------------------------------------
# Only bites 45 days after a password has expired, and none expire here, so it changes nothing day to day.
useradd -D -f 45
awk -F: '$2 ~ /^\$/ {print $1}' /etc/shadow | while read -r u; do chage --inactive 45 "$u"; done
say "inactive password lock" "45 days (default and accounts with a password)"

# --- AppArmor stated in the bootloader (1.3.1.1) ------------------------------------------------------
# Ubuntu already boots with AppArmor on; this only writes it down where CIS looks. Takes effect at the next boot.
# Not on Proxmox (it may boot with systemd-boot, and the host is never rebooted casually).
if [ -z "${PROXMOX:-}" ] && [ -f /etc/default/grub ] && ! grep -q 'apparmor=1' /etc/default/grub; then
  cp -a /etc/default/grub /etc/default/grub.before-cis
  sed -i -E 's|^(GRUB_CMDLINE_LINUX=")([^"]*)"|\1\2 apparmor=1 security=apparmor"|; s|^(GRUB_CMDLINE_LINUX=") |\1|' /etc/default/grub
  if update-grub >/dev/null 2>&1; then say "AppArmor in grub" "apparmor=1 security=apparmor (next boot)"
  else cp -a /etc/default/grub.before-cis /etc/default/grub; update-grub >/dev/null 2>&1; say "AppArmor in grub" "update-grub failed - put back as it was"; fi
fi

# --- services ---------------------------------------------------------------------------------
systemctl mask rsync.service >/dev/null 2>&1; say "rsync daemon" "masked (rsync command still works)"
echo "done"
