# Cf. https://nixos.wiki/wiki/PipeWire
{ config, lib, pkgs, ... }:

{
  # Enable sound with pipewire.
  #sound.enable = true; # used only for ALSA
  security.rtkit.enable = true; # rtkit is optional but recommended for pipewire
  services = {
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      # If you want to use JACK applications, uncomment this
      jack.enable = true;

      # use the example session manager (no others are packaged yet so this is enabled by default,
      # no need to redefine it in your config for now)
      #media-session.enable = true;

      wireplumber = {
        enable = true; # Modular session / policy manager for PipeWire.
        # extraConfig.bluetoothEnhancements = {
        #   "monitor.bluez.properties" = {
        #     "bluez5.enable-sbc-xq" = true;
        #     "bluez5.enable-msbc" = true;
        #     "bluez5.enable-hw-volume" = true;
        #     "bluez5.roles" = [ "hsp_hs" "hsp_ag" "hfp_hf" "hfp_ag" ];
        #   };
        # };
      };
    };
    pulseaudio = {
      enable = false;
    };
  };
  #environment.etc = let json = pkgs.formats.json {}; in {
  #"wireplumber/bluetooth.lua.d/51-bluez-config.lua".text = ''
  #  bluez_monitor.properties = {
  #	  ["bluez5.enable-sbc-xq"] = true,
  #		["bluez5.enable-msbc"] = true,
  #		["bluez5.enable-hw-volume"] = true,
  #  	["bluez5.headset-roles"] = "[ hsp_hs hsp_ag hfp_hf hfp_ag ]"
  #	}
  #'';

  # "pipewire/pipewire.conf.d/92-low-latency.conf".text = ''
  #   context.properties = {
  #     default.clock.rate = 48000
  #     default.clock.quantum = 128
  #     default.clock.min-quantum = 128
  #     default.clock.max-quantum = 256
  #   }
  # '';
  # "pipewire/pipewire-pulse.d/92-low-latency.conf".source = json.generate "92-low-latency.conf" {
  #   context.modules = [
  #     {
  #       name = "libpipewire-module-protocol-pulse";
  #       args = {
  #         pulse.min.req = "128/48000";
  #         pulse.default.req = "128/48000";
  #         pulse.max.req = "256/48000";
  #         pulse.min.quantum = "128/48000";
  #         pulse.max.quantum = "256/48000";
  #       };
  #     }
  #   ];
  #   stream.properties = {
  #     node.latency = "64/48000";
  #     resample.quality = 1;
  #   };
  # };
  #};
  # A PipeWire "Deep Voice" filter-chain device: a virtual audio source that
  # pitch-shifts its input down. It is NOT wired to anything by default -- patch
  # it with qpwgraph like any other node (e.g. mic capture -> Deep Voice input,
  # and Deep Voice output -> the app that wants the deep mic).
  #
  # Mechanism (all provided by the upstream NixOS module, see
  # nixos/modules/services/desktops/pipewire/pipewire.nix):
  #  * configPackages: a package whose share/pipewire/**conf files are linked
  #    into /etc/pipewire, so filter-chain.service picks up the drop-in.
  #  * passthru.requiredLadspaPackages: its lib/ladspa is added to the
  #    LADSPA_PATH that filter-chain.service runs with, so the bare
  #    `plugin` name below resolves without hardcoding store paths.
  #  * filter-chain.service is a normal PipeWire unit (WantedBy=default.target),
  #    so it starts with the session; no extra systemd config needed here.
  #
  # Plugin note: rubberband's LADSPA plugin exposes exactly "Cents",
  # "Semitones", "Octaves", "Formant Preserving" (an on/off toggle) and
  # "Wet-Dry Mix" -- there is no independent formant-shift control, so this is
  # a pure pitch shifter. Formant Preserving = 0 (default) lets formants follow
  # the pitch down, which reads as a genuinely bigger voice; = 1 sounds more
  # like a natural but slowed recording. Tune "Semitones": -1 subtle,
  # -2 noticeably deeper, -4 dramatic.
  services.pipewire = {
    configPackages = [
      (pkgs.writeTextDir "share/pipewire/filter-chain.conf.d/50-deep-voice.conf" ''
        context.modules = [
          { name = libpipewire-module-filter-chain
            flags = [ nofail ]
            args = {
              node.description = "Deep Voice"
              media.name       = "Deep Voice"
              filter.graph = {
                nodes = [
                  {
                    type   = ladspa
                    name   = pitch
                    plugin = "ladspa-rubberband"
                    label  = "rubberband-live-pitchshifter-mono"
                    control = {
                      "Semitones" = -2.0
                      "Wet-Dry Mix" = 1.0
                    }
                  }
                ]
              }
              capture.props = {
                node.name    = "deep_voice_input"
                node.passive = true
              }
              playback.props = {
                node.name        = "deep_voice_output"
                media.class      = "Audio/Source"
                node.description = "Deep Voice"
              }
            }
          }
        ]
      '')
    ];
    # Makes rubberband's lib/ladspa available to filter-chain.service via
    # LADSPA_PATH, so the bare `plugin = "ladspa-rubberband"` resolves.
    extraLadspaPackages = [ pkgs.rubberband ];
  };

  environment.systemPackages = with pkgs; [
    crosspipe # patchbay for pipewire
    qpwgraph # Qt patchbay for PipeWire (graph of nodes + ports)
    # jamesdsp # Audio effect processor for PipeWire clients
  ];
}
