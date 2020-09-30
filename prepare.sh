#!/bin/sh

${VM_NAME:=centos-7}
${VM_RAM:=1024}
${VM_VCPU:=1}
${VM_IPADDR:=10.0.0.148}

${VM_SWAP_SIZE:=512}
${VM_VOLUME_SRC_PATH:=/data/volumes/cloud/CentOS-7-x86_64-GenericCloud.qcow2}
${VM_VOLUME_SRC_PART:=/dev/sda1}
${VM_VOLUME_PATH:=/var/lib/libvirt/images/centos-7.qcow2}
${VM_VOLUME_SIZE:=64G}




#### user-data
cat <<EOF > user-data
#cloud-config

output: { all: ">> /var/log/cloud-init-output.log" }

yum_repos:
  epel:
    name: Extra Packages for Enterprise Linux 7 - \$basearch
    baseurl: http://download.fedoraproject.org/pub/epel/7/\$basearch
    failovermethod: priority
    enabled: true
    gpgcheck: true
    gpgkey: http://download.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-7

package_upgrade: true
packages:
  - nano
  - git
  - tree
  - wget
  - jq

users:
  - name: centos
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash

ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
    root:passwd
    centos:passwd
  expire: false

runcmd:
  - |
    dd if=/dev/zero of=/swap bs=1M count=$VM_SWAP_SIZE
    chmod 600 /swap
    mkswap /swap
    swapon /swap
    echo "/swap none swap sw 0 0" >> /etc/fstab
  - |
    setenforce 0
    sed -i 's/^SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config
  - |
    wget https://github.com/prometheus/node_exporter/releases/download/v1.0.1/node_exporter-1.0.1.linux-amd64.tar.gz
    tar xvfz node_exporter-1.0.1.linux-amd64.tar.gz
    mv node_exporter-1.0.1.linux-amd64/node_exporter /usr/local/bin/
    cat <<EOF > /etc/systemd/system/node_exporter.service
    [Unit]
    Description=Prometheus Node Exporter Service
    After=network.target

    [Service]
    Type=simple
    ExecStart=/usr/local/bin/node_exporter

    [Install]
    WantedBy=multi-user.target
    EOF
    systemctl daemon-reload
    systemctl enable node_exporter --now
  - |
    echo "Hello World !"
EOF




#### meta-data
cat <<EOF > meta-data
instance-id: $VM_NAME
local-hostname: $VM_NAME
network-interfaces: | 
  auto eth0
  iface eth0 inet static
    address $VM_IPADDR
    netmask 255.255.255.0
    gateway 10.0.0.1
    dns-nameservers 10.0.0.10
EOF




virsh destroy $VM_NAME
virsh undefine $VM_NAME
rm -rf $VM_VOLUME_PATH

virt-filesystems -a $VM_VOLUME_SRC_PATH -l
qemu-img create -f qcow2 $VM_VOLUME_PATH $VM_VOLUME_SIZE
virt-resize --expand $VM_VOLUME_SRC_PART $VM_VOLUME_SRC_PATH $VM_VOLUME_PATH
virt-filesystems -a $VM_VOLUME_PATH -l

genisoimage -output seed.iso -volid cidata -joliet -rock user-data meta-data

virt-install \
   --name $VM_NAME \
   --ram $VM_RAM \
   --vcpus $VM_VCPU \
   --noautoconsole \
   --network=bridge:br0,model=virtio \
   --disk path=$VM_VOLUME_PATH,device=disk,bus=virtio,format=qcow2 \
   --disk path=seed.iso,device=cdrom,bus=sata,perms=ro \
   --graphics type=vnc,keymap=fr,listen=0.0.0.0,port=-1 \
   --boot hd,cdrom
