{ config, pkgs, lib,... }:
{
  containers.postgres = { 
    config = { config, pkgs, ... }:
    { 
      services.postgresql.enable = true;
      services.postgresql.package = pkgs.postgresql_14;
      services.postgresql.enableTCPIP = true; # Whether PostgreSQL should listen on all network interfaces. If disabled, the database can only be accessed via its Unix domain socket or via TCP connections to localhost.
      services.postgresql.ensureDatabases = [
    "test"
  ];
  services.postgresql.ensureUsers = [
    {
      name = "test_user";
      ensurePermissions = {
        "DATABASE test" = "ALL PRIVILEGES";
      };
      
    }
    {
      name = "superuser";
      ensurePermissions = {
        "ALL TABLES IN SCHEMA public" = "ALL PRIVILEGES";
      };
    }
  ];
  system.stateVersion = "23.05";
    };
    privateNetwork = true;
    hostAddress = "192.168.105.1";
    localAddress = "192.168.105.10";
  };
  networking.networkmanager.unmanaged = [ "interface-name:ve-*" ]; # explicitly prevent NetworkManager from managing container interfaces.
}