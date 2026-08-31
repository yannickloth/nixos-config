{ config
, lib
, pkgs
, ...
}:
{
  imports = [
    ./shell-aliases.nix
  ];

  # Whether to enable the shared developer-tools programs/services
  # (neovim, vscode, direnv, chromium, ssh, starship, etc.).
  # Nicky and aeiuno enable these; sven keeps a minimal environment.
  options.commonHm.enableDeveloperTools = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable shared developer tools common to nicky and aeiuno.";
  };

  # Whether psd (browser profiles in RAM) should be active. Set per-host based
  # on the host having >= 48 GiB RAM (see roles/psd.nix). When disabled, the
  # profile-sync-daemon package is not installed and profiles stay on disk.
  options.commonHm.enablePsd = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable profile-sync-daemon (browser profiles in RAM) on >= 48 GiB hosts.";
  };

  # Host this home-manager config is built for. Used to gate host-specific
  # config (e.g. Unsloth on laptop-p16). Set by the standalone flake
  # (users/flake.nix, used on CachyOS) and by the NixOS host
  # (hosts/laptop-p16/laptop-p16.nix). config.networking.hostName is NOT
  # reachable inside home-manager modules, so this option is the mechanism.
  options.commonHm.hostName = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Host this home-manager config is built for.";
  };

  config = {
    home.stateVersion = "26.05";

    # Symlink ~/sync to the shared syncthing data directory (/sync is created by the
    # system services.syncthing module, so create the symlink at activation time).
    home.activation.linkSyncDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -d /sync ]; then
        $DRY_RUN_CMD ln -sfn /sync "$HOME/sync"
      else
        echo "warning: /sync does not exist; not creating ~/sync symlink"
      fi
    '';

    # Shared by all users
    services = {
      kdeconnect = {
        enable = true;
        indicator = true;
      };
      # psd (profiles in RAM) is enabled per-host via commonHm.enablePsd, which
      # is determined at build time from the host's actual RAM (>= 48 GiB).
      psd = lib.mkIf config.commonHm.enablePsd {
        enable = true;
      };
    };

    programs = lib.mkMerge [
      {
        # Shared by all users
        zsh = {
          enable = true;
          enableCompletion = true;
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
          historySubstringSearch.enable = true;
          history = {
            size = 10000;
            save = 20000;
            ignoreAllDups = true;
            ignoreSpace = true;
          };
        };
        command-not-found.enable = true;
      }
      # Shared developer tools (nicky + aeiuno)
      (lib.mkIf config.commonHm.enableDeveloperTools {
        direnv = {
          enable = true;
          enableZshIntegration = true;
          nix-direnv.enable = true;
        };
        chromium = {
          enable = true;
          commandLineArgs = [
            "--enable-features=VaapiVideoDecodeLinuxGL"
            "--ignore-gpu-blocklist"
            "--enable-zero-copy"
          ];
        };
        gitui = {
          enable = true;
        };
        man.enable = true;
        neovim = {
          coc = {
            # code completion
            enable = true;
          };
          enable = true;
          withPython3 = false; # use cached neovim; avoid building a wrapped python3 provider
          withRuby = false; # use cached neovim; avoid building a wrapped ruby provider
          plugins = with pkgs.vimPlugins; [
            vim-airline
            vim-nix
            {
              plugin = vim-startify;
              config = "let g:startify_change_to_vcs_root = 0";
              type = "viml";
            }
            YankRing-vim
          ];
          extraConfig = ''
            set mouse=a
          '';
          viAlias = true;
          vimAlias = true;
        };
        ssh = {
          enable = true;
          enableDefaultConfig = false; # module defaults will be removed in the future
        };
        starship = {
          enable = true;
          enableZshIntegration = true;
        };
        vscode = {
          enable = true;
          mutableExtensionsDir = true;
          profiles = {
            default = {
              enableExtensionUpdateCheck = true;
              enableUpdateCheck = true;
              userSettings = { };
            };
          };
        };
      })
    ];
  };
}
