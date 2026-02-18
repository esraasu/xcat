#!/usr/bin/env bash

# xCAT Install Script (CentOS 7) - non-interactive, "normal bash"
# - Fix CentOS7 repos to Vault (mirrorlist is unreliable on EOL)
# - Add the working xCAT repos (core latest + dep rh7)
# - Install xCAT and required base services
# - Define provisioning network in xCAT
# - Start xcatd + dhcpd

set -e

# =======================
# Settings (edit if needed)
# =======================
DOMAIN="xcat.local"
PROV_IF="eth1"
PROV_NETOBJ="192_168_100_0-255_255_255_0"
PROV_NET="192.168.100.0"
PROV_MASK="255.255.255.0"
PROV_GW="192.168.100.1"
MASTER_IP="192.168.100.155"
# =======================

log() { echo -e "\n[INFO] $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Run as root."
  exit 1
fi

log "1) Show resolver config"
cat /etc/resolv.conf || true

log "2) Switch CentOS 7 repos to Vault (avoid mirrorlist failures)"
mkdir -p /etc/yum.repos.d/backup
cp -a /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/ 2>/dev/null || true
rm -f /etc/yum.repos.d/CentOS-*.repo

cat >/etc/yum.repos.d/CentOS-Vault.repo <<'EOF'
[base]
name=CentOS-7 - Base (vault)
baseurl=http://vault.centos.org/7.9.2009/os/x86_64/
enabled=1
gpgcheck=0

[updates]
name=CentOS-7 - Updates (vault)
baseurl=http://vault.centos.org/7.9.2009/updates/x86_64/
enabled=1
gpgcheck=0

[extras]
name=CentOS-7 - Extras (vault)
baseurl=http://vault.centos.org/7.9.2009/extras/x86_64/
enabled=1
gpgcheck=0
EOF

yum clean all
yum makecache -y

log "3) Install base dependencies (DHCP/TFTP/DNS tools)"
yum -y install wget yum-utils net-tools bind bind-utils dhcp tftp-server syslinux xinetd rsync curl

log "4) Add xCAT repos (the same working URLs we used)"
wget -qO /etc/yum.repos.d/xcat-core.repo \
  https://xcat.org/files/xcat/repos/yum/latest/xcat-core/xcat-core.repo

wget -qO /etc/yum.repos.d/xcat-dep.repo \
  https://xcat.org/files/xcat/repos/yum/xcat-dep/rh7/x86_64/xcat-dep.repo

yum clean all
yum makecache -y

log "5) Install xCAT"
yum -y install xCAT

log "6) Load xCAT environment safely (avoid MANPATH unbound issues)"
# xCAT profile script may reference MANPATH without defining it.
export MANPATH="${MANPATH:-}"
# shellcheck disable=SC1091
source /etc/profile.d/xcat.sh

command -v lsdef >/dev/null 2>&1 || { echo "[ERROR] xCAT commands not in PATH"; exit 1; }
echo "[OK] xCAT commands available"

log "7) Ensure xcat-head FQDN resolves locally (needed for genesis/clients)"
grep -q "${MASTER_IP}  xcat-head.${DOMAIN}" /etc/hosts || \
  echo "${MASTER_IP}  xcat-head.${DOMAIN} xcat-head" >> /etc/hosts

getent hosts "xcat-head.${DOMAIN}" || true

log "8) Configure xCAT site domain (prevents makedhcp domain errors)"
chdef -t site domain="${DOMAIN}"

log "9) Start xcatd (must listen on 3001/3002)"
systemctl enable xcatd
systemctl restart xcatd
ss -lntp | egrep '3001|3002' || true

log "10) Define provisioning network in xCAT"
if lsdef -t network 2>/dev/null | grep -q "${PROV_NETOBJ}"; then
  chdef -t network "${PROV_NETOBJ}" \
    net="${PROV_NET}" mask="${PROV_MASK}" gateway="${PROV_GW}" \
    mgtifname="${PROV_IF}" tftpserver="<xcatmaster>"
else
  mkdef -t network "${PROV_NETOBJ}" \
    net="${PROV_NET}" mask="${PROV_MASK}" gateway="${PROV_GW}" \
    mgtifname="${PROV_IF}" tftpserver="<xcatmaster>"
fi

lsdef -t network "${PROV_NETOBJ}" || true

log "11) Generate DHCP config and start dhcpd (dynamic range will be set in config script)"
makedhcp -n || true
systemctl enable dhcpd
systemctl restart dhcpd

log "DONE: xCAT installed and core services are running."
log "Next: run your config script (ISO/copycds + genimage/packimage + node + PXE)."

