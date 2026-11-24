{ flake }:
(import ../../../lib).scrubStorePaths
  flake.nixosConfigurations.laptop-xps.config.systemd.services.home-readmes.script
