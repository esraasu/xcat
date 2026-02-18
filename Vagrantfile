Vagrant.configure("2") do |config|
  config.vm.define "head" do |head|
    head.vm.box = "generic/centos7"
    head.vm.hostname = "xcat-head"

    head.vm.network "private_network",
      libvirt__network_name: "xcat-net"

    head.vm.provider :libvirt do |lv|
      lv.memory = 8192
      lv.cpus  = 4
    end

    # Avoid NFS (needs yum/dns). Use rsync instead.
    head.vm.synced_folder ".", "/vagrant",
      type: "rsync",
      rsync__auto: true,
      rsync__exclude: [".vagrant/"]

    head.vm.provision "shell", privileged: true, inline: <<-SHELL
      set -euo pipefail

      echo "==> Debug: list /vagrant"
      ls -lah /vagrant

      echo "==> Copy ISO to /root"
      cp -f /vagrant/CentOS-7-x86_64-DVD-2003.iso /root/
      ls -lh /root/CentOS-7-x86_64-DVD-2003.iso

      echo "==> Copy scripts directly into /root"
      cp -f /vagrant/scripts/*.sh /root/
      chmod +x /root/*.sh
      ls -lh /root/*.sh

      echo "==> Run scripts as root"
      cd /root
      ./install_xcat.sh
      ./config_xcat.sh

      echo "==> DONE"
    SHELL
  end
end

