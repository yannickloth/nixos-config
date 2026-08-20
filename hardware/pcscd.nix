{ config, lib, pkgs, ... }:

with lib;
with pkgs;
{
  services.pcscd = {
    enable = true;
    plugins = with pkgs; [ libacr38u acsccid scmccid ccid pcsc-scm-scl011 pcsc-cyberjack ];
};
  environment.systemPackages = with pkgs; [
    cfssl # Cloudflare's PKI and TLS toolkit
    pcsclite
    pcsctools # Tools used to test a PC/SC driver, card or reader
  ];
  environment.etc."pkcs11/modules/opensc-pkcs11".text = ''
    module: ${pkgs.opensc}/lib/opensc-pkcs11.so
  '';
  programs.firefox.policies.SecurityDevices.p11-kit-proxy = "${pkgs.p11-kit}/lib/p11-kit-proxy.so";
}
