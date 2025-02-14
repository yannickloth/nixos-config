{ config, lib, pkgs, ... }:

with lib;
{
  programs.obs-studio = {
    enable=true;
    enableVirtualCamera=true;
    plugins=with pkgs;[
      obs-studio-plugins.obs-pipewire-audio-capture
      obs-studio-plugins.obs-backgroundremoval
      obs-studio-plugins.advanced-scene-switcher
      obs-studio-plugins.obs-vertical-canvas
      obs-studio-plugins.obs-scale-to-sound
      obs-studio-plugins.obs-replay-source
      obs-studio-plugins.input-overlay
      obs-studio-plugins.obs-vkcapture
      obs-studio-plugins.obs-vaapi
      obs-studio-plugins.obs-tuna
      obs-studio-plugins.obs-3d-effect
    ];
  };

}
