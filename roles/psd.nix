{ config, lib, ... }:

{
  # Whether psd (browser profiles in RAM) should be enabled for home-manager
  # users on this host. Set explicitly per host based on known RAM:
  #   laptop-hera: 64 GiB  -> enabled
  #   laptop-p16:  128 GiB -> enabled
  #   laptop-xps:  16 GiB  -> disabled
  # When enabled, the profile-sync-daemon package is installed and browser
  # profiles are kept in RAM; when disabled, profiles remain on disk.
  options.roles.psd.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable psd (browser profiles in RAM) on >= 48 GiB RAM hosts.";
  };

  config = lib.mkIf config.roles.psd.enable {
    # Apply psd to every home-manager user on this host (no hardcoded user list).
    home-manager.sharedModules = [
      {
        commonHm.enablePsd = true;
      }
    ];
  };
}
