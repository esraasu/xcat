# xCAT PXE Provisioning Lab (Vagrant + KVM)

## Project Overview

This project automates the deployment of a complete xCAT provisioning
environment using:

-   Vagrant
-   KVM / libvirt
-   CentOS 7
-   PXE / DHCP / TFTP

The lab builds an xCAT head node, configures a provisioning network,
imports a CentOS ISO, generates a netboot image, and prepares a compute
node (node01) to boot from network.

------------------------------------------------------------------------

## Architecture

Host (Fedora + KVM)

Provisioning Network: xcat-net (192.168.100.0/24)

xcat-head VM: - IP: 192.168.100.155 - Services: xcatd, DHCP, TFTP, DNS

Compute Node: - Name: node01 - MAC: 52:54:00:19:05:04 

------------------------------------------------------------------------

## Prerequisites

Make sure the following are installed on the host:

-   KVM / libvirt
-   Vagrant
-   vagrant-libvirt plugin

------------------------------------------------------------------------

## Step 1 -- Create Provisioning Network

``` bash
virsh net-define xcat-net.xml
virsh net-start xcat-net
virsh net-autostart xcat-net
```

Verify:

``` bash
virsh net-list --all
```

Ensure xcat-net is active before continuing.

------------------------------------------------------------------------

## Step 2 -- Deploy xCAT Head Node

``` bash
vagrant up --provider=libvirt
```

This will:

-   Install xCAT
-   Configure static IP (192.168.100.155)
-   Configure DHCP and TFTP
-   Import ISO (copycds)
-   Build netboot image (genimage + packimage)
-   Create node01 definition
-   Run nodeset node01

------------------------------------------------------------------------

## Script Explanation

### install_xcat.sh

-   Switch CentOS repos to Vault
-   Install required packages
-   Install xCAT
-   Configure site domain
-   Define provisioning network
-   Generate DHCP config
-   Start xcatd and dhcpd

### config_xcat.sh

-   Configure provisioning NIC
-   Apply xCAT master settings
-   Create node01 definition
-   Fix DHCP next-server
-   Import ISO
-   Build netboot image
-   Copy kernel and initrd to TFTP
-   Perform TFTP self-test
-   Run nodeset node01

------------------------------------------------------------------------

## Step 3 -- Test PXE Boot (node01)

``` bash
virt-install   --name node01   --memory 2048   --vcpus 2   --disk size=20   --network network=xcat-net,model=virtio,mac=52:54:00:19:05:04   --boot network,hd   --os-variant centos7   --pxe
```

The compute node should:

-   Obtain IP from DHCP
-   Download kernel via TFTP
-   Boot using xCAT netboot image

------------------------------------------------------------------------

## Monitoring

``` bash
tail -f /var/log/messages
```

Look for DHCP, TFTP, and xCAT provisioning logs.

------------------------------------------------------------------------

# Troubleshooting & Issues Encountered

## 1️⃣ Wrong next-server Generated from Dynamic Range (Critical)

### Symptom

During PXE boot:

Next server: 192.168.100.150\
tftp://192.168.100.150/pxelinux.0 ... Connection timed out


### Root Cause

Dynamic DHCP range was:

192.168.100.150 - 192.168.100.200

xCAT network object did NOT explicitly define:

-   dhcpserver
-   tftpserver
-   nameservers

xCAT auto-selected the first IP in the range (192.168.100.150),
generating:

next-server 192.168.100.150;

### Fix

Explicitly define DHCP/TFTP server and regenerate config:

source /etc/profile.d/xcat.sh

chdef -t network 192_168_100_0-255_255_255_0 dhcpserver=192.168.100.155\
chdef -t network 192_168_100_0-255_255_255_0 tftpserver=192.168.100.155\
chdef -t network 192_168_100_0-255_255_255_0 nameservers=192.168.100.155

makedhcp -n\
systemctl restart dhcpd

Verify:

grep next-server /etc/dhcp/dhcpd.conf

Must show:

next-server 192.168.100.155;

------------------------------------------------------------------------

## 2️⃣ installstatus netbooting invalid (Port 3002 Error)

### Symptom

fatal: remote host and port information (3002, installstatus netbooting)
invalid

### Root Cause

Provisioning NIC was configured using:

ip addr add

NetworkManager removed the temporary IP after reboot.\
xcatd became unreachable.

### Fix

Always configure provisioning NIC using NetworkManager:

nmcli con mod "System eth1" ipv4.method manual ipv4.addresses
192.168.100.155/24 ipv6.method ignore

nmcli con up "System eth1"

Never use temporary ip addr add for provisioning networks.

------------------------------------------------------------------------

## 3️⃣ Node Definition Missing groups Attribute

### Symptom

Attribute 'groups' is not specified for node 'node01'

### Root Cause

node01 existed without:

groups=compute

xCAT provisioning requires node group membership.

### Fix

Ensure node is defined properly:

mkdef -t node node01 groups=compute ip=192.168.100.101
mac=52:54:00:19:05:04 netboot=pxe

------------------------------------------------------------------------

## 4️⃣ Kernel Blocked by TFTP Mapfile

### Problem

xCAT blocks file named "kernel" due to tftpmapfile4xcat.conf.

### Fix

Copy kernel as vmlinuz instead of using symlink:

cp kernel /tftpboot/xcat/vmlinuz\
cp initrd-stateless.gz /tftpboot/xcat/initrd-stateless.gz

Avoid symlinks.

------------------------------------------------------------------------

## 5️⃣ CentOS 7 Repository Failure (EOL)

### Symptom

Could not retrieve mirrorlist

### Root Cause

CentOS 7 is End-of-Life.

### Fix

Switch to CentOS Vault:

sed -i 's\|mirrorlist=\|#mirrorlist=\|g'
/etc/yum.repos.d/CentOS-Base.repo\
sed -i
's\|#baseurl=http://mirror.centos.org\|baseurl=http://vault.centos.org\|g'
/etc/yum.repos.d/CentOS-Base.repo\
yum clean all\
yum makecache



