# configuration for fonts

{ config, lib, pkgs, ... }:

with lib;

{
  config = {
    fonts = {
      enableDefaultPackages = true;
      fontconfig = {
        enable = mkForce true;
        defaultFonts = {
          monospace = ["Iosevka 11"];
          sansSerif = ["Inter 11"];
          serif = ["Roboto Slab 11"];
        };
      };
      fontDir = {
        enable = true;
      };
      packages = with pkgs; [
        adwaita-icon-theme # for apps like simple-scan
        caladea
        carlito
        charis-sil # Recommended by Matthew Butterick
        cooper-hewitt # Recommended by Matthew Butterick
        corefonts
        courier-prime
        dejavu_fonts
        dina-font
        encode-sans
        garamond-libre
        gelasio
        gentium #
        gentium-book-basic #
        gyre-fonts
        hasklig
        ibm-plex # Recommended by Matthew Butterick
        inconsolata-nerdfont
        intel-one-mono # Intel One Mono, an expressive monospaced font family that’s built with clarity, legibility, and the needs of developers in mind.
        inter
        iosevka
        iosevka-comfy.comfy
        liberation_ttf
        material-design-icons
        material-icons
        merriweather
        mplus-outline-fonts.githubRelease
        (nerdfonts.override { fonts = [ "FiraCode" "FiraMono" "DroidSansMono" "JetBrainsMono" "Noto" "ProFont" "RobotoMono" "Ubuntu" "UbuntuMono" "VictorMono" ]; })
        #noto-fonts-emoji
        office-code-pro # Customized version of Source Code Pro. The customizations were made specifically for text editors and coding environments.
        open-sans
        overpass # the open source typeface used by the Red Hat brand identity. 
        proggyfonts
        raleway
        redhat-official-fonts
        # roboto # no need for this, the inter font just looks better. https://mattwestcott.org/blog/an-ode-to-the-inter-typeface
        roboto-slab
        sn-pro # SN Pro Font Family (https://supernotes.app/open-source/sn-pro/). SN Pro is a friendly sans serif typeface optimized for use with Markdown.
        source-code-pro
        source-sans-pro
        terminus_font
        #twemoji-color-font
        #twitter-color-emoji
        #vistafonts
        # whatsapp-emoji-font
      ];
    };
  };
}
