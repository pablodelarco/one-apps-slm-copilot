# Build 1: Generate cloud-init seed ISO
source "null" "context" {
  communicator = "none"
}

build {
  name    = "context"
  sources = ["source.null.context"]

  provisioner "shell-local" {
    inline = [
      "cloud-localds ${var.appliance_name}-cloud-init.iso cloud-init.yml",
    ]
  }
}

# Build 2: Provision the SLM-Copilot QCOW2 image
source "qemu" "slm_copilot" {
  accelerator = "kvm"

  cpus      = 4
  memory    = 16384
  disk_size = "50G"

  iso_url      = "${var.input_dir}/ubuntu2404.qcow2"
  iso_checksum = "none"
  disk_image   = true

  output_directory = "${var.output_dir}"
  vm_name          = "${var.appliance_name}.qcow2"
  format           = "qcow2"

  headless = var.headless

  net_device     = "virtio-net"
  disk_interface = "virtio"

  qemuargs = [
    ["-cdrom", "${var.appliance_name}-cloud-init.iso"],
    ["-serial", "mon:stdio"],
    ["-cpu", "host"],
  ]

  boot_wait = "30s"

  communicator     = "ssh"
  ssh_username     = "root"
  ssh_password     = "opennebula"
  ssh_timeout      = "30m"
  ssh_wait_timeout = "1800s"

  shutdown_command = "poweroff"
}

build {
  name    = "slm-copilot"
  sources = ["source.qemu.slm_copilot"]

  # Step 1: SSH hardening
  provisioner "shell" {
    script = "scripts/81-configure-ssh.sh"
  }

  # Step 2: Install one-context package
  provisioner "shell" {
    inline = ["mkdir -p /context"]
  }

  provisioner "file" {
    source      = "${var.one_apps_dir}/context-linux/out/"
    destination = "/context"
  }

  provisioner "shell" {
    script = "scripts/80-install-context.sh"
  }

  # Step 3: Create one-appliance directory structure
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "install -o 0 -g 0 -m u=rwx,g=rx,o=   -d /etc/one-appliance/{,service.d/,lib/}",
      "install -o 0 -g 0 -m u=rwx,g=rx,o=rx -d /opt/one-appliance/{,bin/}",
    ]
  }

  # Step 4: Install one-apps framework files
  provisioner "file" {
    sources = [
      "${var.one_apps_dir}/appliances/scripts/net-90-service-appliance",
      "${var.one_apps_dir}/appliances/scripts/net-99-report-ready",
    ]
    destination = "/etc/one-appliance/"
  }

  provisioner "file" {
    source      = "${var.one_apps_dir}/appliances/service.sh"
    destination = "/etc/one-appliance/service"
  }

  provisioner "shell" {
    inline = ["chmod 0755 /etc/one-appliance/service"]
  }

  provisioner "file" {
    source      = "${var.one_apps_dir}/appliances/lib/common.sh"
    destination = "/etc/one-appliance/lib/common.sh"
  }

  provisioner "file" {
    source      = "${var.one_apps_dir}/appliances/lib/functions.sh"
    destination = "/etc/one-appliance/lib/functions.sh"
  }

  # Step 5: Install SLM-Copilot appliance script
  provisioner "file" {
    source      = "../../appliances/slm-copilot/appliance.sh"
    destination = "/etc/one-appliance/service.d/appliance.sh"
  }

  # Step 6: Move context hooks into place
  provisioner "shell" {
    script = "scripts/82-configure-context.sh"
  }

  # Step 7: Run service_install (downloads binary, model, pre-warms)
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline         = ["/etc/one-appliance/service install && sync"]
  }

  # Step 8: Cleanup for cloud reuse
  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get purge -y cloud-init snapd fwupd || true",
      "apt-get autoremove -y --purge || true",
      "apt-get clean -y",
      "rm -rf /var/lib/apt/lists/*",
      "rm -f /etc/sysctl.d/99-cloudimg-ipv6.conf",
      "rm -rf /context/",
      "truncate -s 0 /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",
      "rm -rf /tmp/* /var/tmp/*",
      "sync",
    ]
  }
}
