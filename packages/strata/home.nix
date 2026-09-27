# home-manager wrapper for the Strata package (see ./default.nix).
#
#   imports = [ ../../packages/strata/home.nix ];
#   strata.enable = true;   # gated on the host with the CUDA GPU (laptop-p16)
#
# Installs the `strata` and `strata-chat` commands on PATH. The first `strata`
# run asks the model/size/context questions and downloads the ~70-84 GB model
# into ~/.local/share/strata (override the directory with STRATA_HOME); every
# later run starts the model right away (API on http://127.0.0.1:8080).
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.strata;
in
{
  options.strata = {
    enable = mkEnableOption "Strata (local Qwen3.8-Flash-Next 125B MoE inference, OpenAI/Anthropic API on localhost)";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./default.nix { };
      defaultText = literalExpression "pkgs.callPackage ./default.nix { }";
      description = "The Strata package providing the engine and the setup/start wrappers.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
