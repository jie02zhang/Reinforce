# -*- mode: ruby -*-
# vi: set ft=ruby :

# 安全加固脚本 - 多发行版虚拟机测试环境
# 用法: vagrant up [vm-name]
# 文档: 参见 vm_testing_plan.md

Vagrant.configure("2") do |config|
  config.vagrant.plugins = ["vagrant-disksize"]
  
  # 全局 SSH 配置
  config.ssh.insert_key = false
  config.ssh.username = "vagrant"
  
  # ================= Ubuntu 22.04 =================
  config.vm.define "ubuntu2204" do |node|
    node.vm.hostname = "ubuntu2204"
    node.vm.box = "bento/ubuntu-22.04"
    # node.vm.network "private_network", type: "dhcp"  # 注释掉，避免 Host-only 冲突
    node.vm.post_up_message = "Ubuntu 22.04 已启动！\n测试命令:\n  vagrant ssh ubuntu2204\n  sudo bash /opt/security/security_hardening.sh --verbose"
    
    # 磁盘扩容
    node.disksize.size = "20GB"
    
    # VirtualBox 配置
    node.vm.provider "virtualbox" do |vb|
      vb.name = "ubuntu2204"
      vb.memory = 2048
      vb.cpus = 2
      vb.gui = false
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
    end
    
    # 自动配置
    node.vm.provision "shell", path: "provision.sh", args: "ubuntu2204"
  end

  # ================= Ubuntu 24.04 =================
  config.vm.define "ubuntu2404" do |node|
    node.vm.hostname = "ubuntu2404"
    node.vm.box = "bento/ubuntu-24.04"
    # node.vm.network "private_network", type: "dhcp"  # 注释掉，避免 Host-only 冲突
    node.vm.post_up_message = "Ubuntu 24.04 已启动！"
    
    node.disksize.size = "20GB"
    
    node.vm.provider "virtualbox" do |vb|
      vb.name = "ubuntu2404"
      vb.memory = 2048
      vb.cpus = 2
      vb.gui = false
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
    end
    
    node.vm.provision "shell", path: "provision.sh", args: "ubuntu2404"
  end

  # ================= Debian 12 =================
  config.vm.define "debian12" do |node|
    node.vm.hostname = "debian12"
    node.vm.box = "bento/debian-12"
    # node.vm.network "private_network", type: "dhcp"  # 注释掉，避免 Host-only 冲突
    
    node.disksize.size = "20GB"
    
    node.vm.provider "virtualbox" do |vb|
      vb.name = "debian12"
      vb.memory = 2048
      vb.cpus = 2
      vb.gui = false
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
    end
    
    node.vm.provision "shell", path: "provision.sh", args: "debian12"
  end

  # ================= AlmaLinux 9 =================
  config.vm.define "almalinux9" do |node|
    node.vm.hostname = "almalinux9"
    node.vm.box = "bento/almalinux-9"
    # node.vm.network "private_network", type: "dhcp"  # 注释掉，避免 Host-only 冲突
    
    node.disksize.size = "20GB"
    
    node.vm.provider "virtualbox" do |vb|
      vb.name = "almalinux9"
      vb.memory = 2048
      vb.cpus = 2
      vb.gui = false
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
    end
    
    node.vm.provision "shell", path: "provision.sh", args: "almalinux9"
  end

  # ================= SUSE 15 SP7 =================
  config.vm.define "suse15" do |node|
    node.vm.hostname = "suse15"
    node.vm.box = "opensuse/Leap-15.6.x86_64"
    # node.vm.network "private_network", type: "dhcp"  # 注释掉，避免 Host-only 冲突
    
    node.disksize.size = "20GB"
    
    node.vm.provider "virtualbox" do |vb|
      vb.name = "suse15"
      vb.memory = 2048
      vb.cpus = 2
      vb.gui = false
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
    end
    
    node.vm.provision "shell", path: "provision.sh", args: "suse15"
  end

  # ================= Oracle Linux 9 =================
  config.vm.define "oraclelinux9" do |node|
    node.vm.hostname = "oraclelinux9"
    node.vm.box = "bento/oraclelinux-9"
    # node.vm.network "private_network", type: "dhcp"  # 注释掉，避免 Host-only 冲突
    
    node.disksize.size = "20GB"
    
    node.vm.provider "virtualbox" do |vb|
      vb.name = "oraclelinux9"
      vb.memory = 2048
      vb.cpus = 2
      vb.gui = false
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
    end
    
    node.vm.provision "shell", path: "provision.sh", args: "oraclelinux9"
  end

  # ================= Rocky Linux 9 =================
  config.vm.define "rockylinux9" do |node|
    node.vm.hostname = "rockylinux9"
    node.vm.box = "bento/rockylinux-9"
    # node.vm.network "private_network", type: "dhcp"  # 注释掉，避免 Host-only 冲突
    
    node.disksize.size = "20GB"
    
    node.vm.provider "virtualbox" do |vb|
      vb.name = "rockylinux9"
      vb.memory = 2048
      vb.cpus = 2
      vb.gui = false
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
    end
    
    node.vm.provision "shell", path: "provision.sh", args: "rockylinux9"
  end

  # ================= CentOS 7 =================
  config.vm.define "centos7" do |node|
    node.vm.hostname = "centos7"
    node.vm.box = "bento/centos-7"
    # node.vm.network "private_network", type: "dhcp"  # 注释掉，避免 Host-only 冲突
    
    node.disksize.size = "20GB"
    
    node.vm.provider "virtualbox" do |vb|
      vb.name = "centos7"
      vb.memory = 2048
      vb.cpus = 2
      vb.gui = false
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
    end
    
    node.vm.provision "shell", path: "provision.sh", args: "centos7"
  end

  # ================= Amazon Linux 2023 =================
  config.vm.define "amazonlinux2023" do |node|
    node.vm.hostname = "amazonlinux2023"
    node.vm.box = "bento/amazonlinux-2023"
    # node.vm.network "private_network", type: "dhcp"  # 注释掉，避免 Host-only 冲突
    
    node.disksize.size = "20GB"
    
    node.vm.provider "virtualbox" do |vb|
      vb.name = "amazonlinux2023"
      vb.memory = 2048
      vb.cpus = 2
      vb.gui = false
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      vb.customize ["modifyvm", :id, "--audio", "none"]
    end
    
    node.vm.provision "shell", path: "provision.sh", args: "amazonlinux2023"
  end

end
