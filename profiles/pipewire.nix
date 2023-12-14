# Cf. https://nixos.wiki/wiki/PipeWire
{ config, lib, pkgs,... }:

{
  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;

    wireplumber.enable = true;
  };
  environment.etc = let json = pkgs.formats.json {}; in {
	  "wireplumber/bluetooth.lua.d/51-bluez-config.lua".text = ''
		  bluez_monitor.properties = {
			  ["bluez5.enable-sbc-xq"] = true,
  			["bluez5.enable-msbc"] = true,
	  		["bluez5.enable-hw-volume"] = true,
		  	["bluez5.headset-roles"] = "[ hsp_hs hsp_ag hfp_hf hfp_ag ]"
  		}
	  '';
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
  };
  environment.systemPackages = with pkgs; [
    helvum
    jamesdsp
  ];
}
