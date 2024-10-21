{ config, pkgs, ... }:
let
  nestor_internal_ip = "192.168.190.100";
in
{
  networking = {
    firewall = {
      extraCommands = ''iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns'';
      enable = true;
      allowPing = true;
      allowedTCPPorts = [
        5357 # wsdd
      ];
      allowedUDPPorts = [
        3702 # wsdd
      ];
    };
  };

  services = {
    samba = {
      enable = true;
      nmbd.enable = true; # Whether to enable Samba’s nmbd, which replies to NetBIOS over IP name service requests. It also participates in the browsing protocols which make up the Windows “Network Neighborhood” view.
      winbindd.enable = true; # Whether to enable Samba’s winbindd, which provides a number of services to the Name Service Switch capability found in most modern C libraries, to arbitrary applications via PAM and ntlm_auth and to Samba itself.
      nsswins = true; # Whether to enable the WINS NSS (Name Service Switch) plug-in. Enabling it allows applications to resolve WINS/NetBIOS names (a.k.a. Windows machine names) by transparently querying the winbindd daemon.
      openFirewall = true;
      package = pkgs.samba4Full;
      settings = {
        global = {
          workgroup = "WORKGROUP";
          "server string" = "${config.networking.hostName}";
          "netbios name" = "${config.networking.hostName}";
          security = "user";
          "invalid users"=[ "root" ]; # List of users who are denied to login via Samba.
          #use sendfile = yes
          #max protocol = smb2
          # note: localhost is the ipv6 localhost ::1
          "hosts allow" = "192.168.190. 127.0.0.1 localhost";
          "hosts deny" = "0.0.0.0/0";
          "guest account" = "nobody";
          "map to guest" = "bad user";
  #         load printers = yes
  #         printing = CUPS
  #         printcap name = cups
        };
        homes = {
          comment = "Home Directories";
          browseable = "yes";
          # By default, \\server\username shares can be connected to by anyone
          # with access to the samba server. Un-comment the following parameter
          # to make sure that only "username" can connect to \\server\username
          "valid users" = "%S";
          # By default, the home directories are exported read-only. Change next
          # parameter to 'yes' if you want to be able to write to them.
          writable = "yes";
        };
      };
      #shares = {
  #       public = {
  #         path = "/mnt/Shares/Public";
  #         browseable = "yes";
  #         "read only" = "no";
  #         "guest ok" = "yes";
  #         "create mask" = "0644";
  #         "directory mask" = "0755";
  #         "force user" = "username";
  #         "force group" = "groupname";
  #       };
  #       private = {
  #         path = "/mnt/Shares/Private";
  #         browseable = "yes";
  #         "read only" = "no";
  #         "guest ok" = "no";
  #         "create mask" = "0644";
  #         "directory mask" = "0755";
  #         "force user" = "username";
  #         "force group" = "groupname";
  #       };
  #        printers = {
  #          comment = "All Printers";
  #          path = "/var/spool/samba";
  #          public = "yes";
  #          browseable = "yes";
  #          # to allow user 'guest account' to print.
  #          "guest ok" = "no";
  #          writable = "no";
  #          printable = "yes";
  #          "create mode" = 0700;
  #        };
      # };
    };
  #   systemd.tmpfiles.rules = [ # for samba printer sharing
  #     "d /var/spool/samba 1777 root root -"
  #   ];

    samba-wsdd = {
      enable = true; # make shares visible for windows 10 clients
      discovery = true;
      hostname = "${config.networking.hostName}";
      # openFirewall = true;
      workgroup = "WORKGROUP";
    };
  };
}
