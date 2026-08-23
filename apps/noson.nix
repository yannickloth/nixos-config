{ config, lib, pkgs, ... }:

with lib;
{
  # Noson: SONOS controller for Linux (Qt5). Speaker discovery relies on the
  # SSDP tracking in services/sonos.nix (nftables "upnp" set with a 3s
  # timeout), which must be imported by the same host — the firewall would
  # otherwise drop the unicast replies to the discovery probes. Audio output
  # goes through PulseAudio/PipeWire (desktop/pipewire.nix) and GStreamer
  # (apps/gstreamer.nix).
  environment.systemPackages = with pkgs; [
    noson
  ];
}
