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


