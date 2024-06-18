{ config, lib, pkgs, ... }:

with lib;
{
  environment.systemPackages = with pkgs; [
    virt-manager-qt # Desktop user interface for managing virtual machines (QT)
  ];
  programs = {
    virt-manager = {
      enable = true; # Whether to enable virt-manager, an UI for managing virtual machines in libvirt.
    };
  };
  virtualisation = {
    libvirtd = {
      enable = true; # This option enables libvirtd, a daemon that manages virtual machines. Users in the “libvirtd” group can interact with the daemon (e.g. to start or stop VMs) using the virsh command line tool, among others.
    };
    spiceUSBRedirection.enable = true;
    kvmgt = {
      enable = true; # Whether to enable KVMGT (iGVT-g) VGPU support. Allows Qemu/KVM guests to share host’s Intel integrated graphics card. Currently only one graphical device can be shared. To allow users to access the device without root add them to the kvm group.
    };
  };
}
