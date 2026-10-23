{ self }: builtins.filter
  (n: builtins.match "kid-.*" n != null)
  (builtins.attrNames self.nixosConfigurations.laptop-xps.config.security.apparmor.policies)
