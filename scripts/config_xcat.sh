#!/usr/bin/env bash
set -e

# =======================
# EDIT IF NEEDED
# =======================
ISO_PATH="/root/CentOS-7-x86_64-DVD-2003.iso"

DOMAIN="xcat.local"
MASTER_IP="192.168.100.155"
PROV_IF="eth1"
PROV_NETOBJ="192_168_100_0-255_255_255_0"

NODE="node01"
NODE_MAC="52:54:00:19:05:04"
NODE_IP="192.168.100.101"

# MUST NOT include NODE_IP
DHCP_RANGE_START="192.168.100.150"
DHCP_RANGE_END="192.168.100.200"

# If you DON'T want xCAT to manage the 192.168.121.x network, keep this ON
REMOVE_121_NETOBJ=1

OSVER="centos7.8"
ARCH="x86_64"
PROFILE="compute"
# =======================

log(){ echo -e "\n[INFO] $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Run as root."
  exit 1
fi

# ---------- Fix NIC eth1 using NetworkManager ----------
log "1) Configure ${PROV_IF} static IP (exactly like history)"
nmcli con mod "System eth1" ipv4.method manual ipv4.addresses "${MASTER_IP}/24" ipv4.gateway 192.168.100.1 ipv4.dns "${MASTER_IP}" ipv6.method ignore
nmcli con up "System eth1"
ip -4 a show dev "${PROV_IF}"

# ---------- Restart services + check ports ----------
log "2) Restart xcatd/dhcpd and verify ports"
systemctl restart xcatd
systemctl restart dhcpd
ss -lntp | grep xcat || true

# ---------- xCAT environment ----------
log "3) Load xCAT environment safely"
export MANPATH="${MANPATH:-}"
# shellcheck disable=SC1091
source /etc/profile.d/xcat.sh

# ---------- Apply xCAT site settings ----------
log "4) Apply xCAT site settings"
chdef -t site master="${MASTER_IP}"
chdef -t site imageserver="${MASTER_IP}"
chdef -t site nameservers="${MASTER_IP}"
chdef -t site domain="${DOMAIN}"

# ---------- Ensure node exists with required attrs BEFORE makehosts/nodeset ----------
log "5) Ensure ${NODE} has groups/ip/mac/netboot (prevents 'groups not specified' error)"
if ! lsdef "${NODE}" >/dev/null 2>&1; then
  mkdef -t node "${NODE}" groups="${PROFILE}" ip="${NODE_IP}" mac="${NODE_MAC}" netboot=pxe
else
  chdef "${NODE}" groups="${PROFILE}" ip="${NODE_IP}" mac="${NODE_MAC}" netboot=pxe
fi

chdef "${NODE}" xcatmaster="${MASTER_IP}" nfsserver="${MASTER_IP}"

# ---------- Force correct servers on provisioning network (FIX next-server=.150) ----------
log "6) Force DHCP/TFTP/NAMESERVER to be ${MASTER_IP} on provisioning network (fix next-server bug)"
chdef -t network "${PROV_NETOBJ}" dhcpserver="${MASTER_IP}"
chdef -t network "${PROV_NETOBJ}" tftpserver="${MASTER_IP}"
chdef -t network "${PROV_NETOBJ}" nameservers="${MASTER_IP}"
chdef -t network "${PROV_NETOBJ}" dynamicrange="${DHCP_RANGE_START}-${DHCP_RANGE_END}" || true

# Optional: remove/disable the 192.168.121.* xCAT network object if present (prevents dhcpd.conf extra next-server lines)
if [[ "${REMOVE_121_NETOBJ}" == "1" ]]; then
  log "6.1) Remove xCAT network object for 192.168.121.0/24 if it exists (avoid wrong next-server on eth0)"
  NET121_OBJ="$(lsdef -t network 2>/dev/null | awk '{print $1}' | grep -E '^192_168_121_0-255_255_255_0$' || true)"
  if [[ -n "${NET121_OBJ}" ]]; then
    rmdef -t network "${NET121_OBJ}" || true
  fi
fi

# ---------- Rebuild DHCP config from xCAT (CRITICAL) ----------
log "7) Regenerate DHCP config from xCAT (CRITICAL) and restart dhcpd"
makedhcp -n
systemctl restart dhcpd

log "7.1) Verify next-server in dhcpd.conf (must be ${MASTER_IP} for 192.168.100.*)"
grep -E "next-server|filename" /etc/dhcp/dhcpd.conf | head -n 40 || true

# ---------- Update hosts after site/node defs ----------
log "8) makehosts"
makehosts

# ---------- Build netboot image ----------
log "9) Validate ISO exists"
[[ -f "${ISO_PATH}" ]] || { echo "[ERROR] ISO not found: ${ISO_PATH}"; exit 1; }

log "10) copycds from ISO (use ISO file path)"
copycds "${ISO_PATH}"

OSIMAGE="${OSVER}-${ARCH}-netboot-${PROFILE}"
log "11) Build image: ${OSIMAGE}"
genimage "${OSIMAGE}"
packimage "${OSIMAGE}"

BUILD_DIR="/install/netboot/${OSVER}/${ARCH}/${PROFILE}"
log "12) Validate build outputs"
ls -lh "${BUILD_DIR}" | egrep "kernel|initrd-stateless.gz|rootimg.cpio.gz" || true
[[ -s "${BUILD_DIR}/kernel" ]] || { echo "[ERROR] kernel missing/empty in ${BUILD_DIR}"; exit 1; }
[[ -s "${BUILD_DIR}/initrd-stateless.gz" ]] || { echo "[ERROR] initrd missing/empty in ${BUILD_DIR}"; exit 1; }

# ---------- TFTP: use vmlinuz (avoid tftpmapfile blocking 'kernel') ----------
log "13) Copy kernel/initrd to TFTP (no symlinks, use vmlinuz name)"
rm -f /tftpboot/xcat/vmlinuz /tftpboot/xcat/initrd-stateless.gz
cp -f "${BUILD_DIR}/kernel" /tftpboot/xcat/vmlinuz
cp -f "${BUILD_DIR}/initrd-stateless.gz" /tftpboot/xcat/initrd-stateless.gz
chmod 644 /tftpboot/xcat/vmlinuz /tftpboot/xcat/initrd-stateless.gz

log "14) Local TFTP self-test (must be non-zero)"
cd /tmp || exit 1
rm -f vmlinuz initrd-stateless.gz
tftp 127.0.0.1 -c get xcat/vmlinuz
tftp 127.0.0.1 -c get xcat/initrd-stateless.gz
[[ -s /tmp/vmlinuz ]] || { echo "[ERROR] TFTP xcat/vmlinuz downloaded 0 bytes"; exit 1; }
[[ -s /tmp/initrd-stateless.gz ]] || { echo "[ERROR] TFTP xcat/initrd-stateless.gz downloaded 0 bytes"; exit 1; }

# ---------- Regenerate MAC PXE file then nodeset + restart ----------
log "15) Regenerate PXE config (fix installstatus/3002 invalid)"
rm -f "/tftpboot/pxelinux.cfg/01-${NODE_MAC//:/-}" || true

nodeset "${NODE}" osimage="${OSIMAGE}"

systemctl restart xcatd
systemctl restart dhcpd

log "DONE ✅"
echo "Next:"
echo "  virsh reset ${NODE}"
echo "  virsh console ${NODE}"
echo "  tail -f /var/log/messages | egrep -i 'dhcp|tftp|xcat|3002|installstatus|${NODE}|${NODE_IP}'"

