{ config, lib, pkgs, ... }:

with lib;
{
  boot.binfmt.registrations.go = {
    wrapInterpreterInShell = false;
    interpreter = "${pkgs.go}/bin/go";
    recognitionType = "extension";
    offset = 0;
    #mask = ''\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff'';
    magicOrExtension = ''go'';
  };
  environment.systemPackages = with pkgs; [
    go
  ];
}
