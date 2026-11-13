{ flake }: builtins.filter
  (n: builtins.match "kid-.*" n != null)
  (builtins.attrNames flake.nixosConfigurations.laptop-xps.config.security.apparmor.policies)
