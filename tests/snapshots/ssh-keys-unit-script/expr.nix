{ flake }:
(import ../../../lib).scrubStorePaths
  flake.nixosConfigurations.laptop-xps.config.systemd.services.ssh-user-keys.script
