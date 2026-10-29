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

  # True when this config is built by the standalone flake (users/flake.nix,
  # used on CachyOS) rather than the NixOS host. CachyOS-specific behaviour
  # (host tuning in /etc, which no NixOS system module provides) must be gated
  # on it, so a future NixOS install of this laptop is unaffected. The NixOS
  # host never sets it, so it stays false there.
  options.commonHm.isCachyOS = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "True when built by the standalone CachyOS home-manager flake.";
  };

  config = {
    home.stateVersion = "26.05";

    # shell-aliases.nix runs `eval "$(zoxide init zsh)"` unconditionally, so
    # zoxide must exist in every user's PATH. On NixOS hosts it also comes
    # from roles/system.nix; listing it here keeps the standalone
    # home-manager deployment (users/flake.nix, CachyOS hosts) working.
    #
    # The ArtCraft "Crafting Apps" (packages/craft-apps — PhotoCraft,
    # VectorCraft, FilmCraft, LightCraft, PdfCraft, EffectCraft, DesignCraft,
    # FigCraft, WordCraft, SoundCraft, DeckCraft, CADCraft, GridCraft) are installed for
    # all users. They are imported directly (not callPackage: that would wrap
    # the returned attrset with lib.makeOverridable and leak `override` /
    # `overrideDerivation` functions into home.packages below) so they land for
    # everyone regardless of whether the ai-unstable overlay is applied to this
    # user's pkgs; attrValues expands the attribute set into home.packages.
    #
    # cachyos gates the host-specific GPU/audio stack bundled into the wrapper
    # (Mesa, VA-API, PipeWire/PulseAudio ALSA config): the CachyOS laptop-p16
    # deployment has no /run/opengl-driver, the NixOS hosts do and keep the
    # plain build.
    # Calculator trio for every user: `qalc` (units, currency, diff/solve/
    # factor, statistics, dates, number bases — no integration, that needs
    # maxima/sympy), `numbat` (dimension-checked science — unit errors are type
    # errors) and `bc` (POSIX arithmetic in scripts; ships `dc` too). The
    # harness rule is "compute, never in your head" (llm-harness-plugins
    # general-skills), so the engines must be on PATH for the agents running as
    # these users.
    # `qalc` comes from `libqalculate`. The `qalculate-qt`/`qalculate-gtk`
    # packages installed for the desktop (users/hyprland.nix, nicky-hm.nix,
    # aeiuno-hm.nix) are the GUIs: their output contains only `qalculate-qt`/
    # `qalculate-gtk`, so libqalculate sits in the closure but the CLI never
    # reaches PATH.
    home.packages =
      [ pkgs.zoxide pkgs.libqalculate pkgs.numbat pkgs.bc ]
      ++ builtins.attrValues (import ../packages/craft-apps {
        inherit (pkgs) lib appimageTools fetchurl;
        cachyos = config.commonHm.isCachyOS;
      })
      # Ioskeley Mono, CachyOS only. roles/fonts.nix installs it system-wide via
      # the NixOS `fonts.packages` option, which does not exist here: the
      # standalone flake (users/flake.nix) builds only home-manager modules, so
      # that option never runs. Linking the faces into ~/.nix-profile/share/fonts
      # instead works because the CachyOS system fontconfig scans the XDG data
      # dirs. Gated on isCachyOS so the NixOS hosts do not install a second copy.
      # The user-level fontconfig module is NOT a usable lever here (see
      # sven-hm.nix: config.fonts.fontconfig.enable is false off-NixOS).
      #
      # Same six variants as roles/fonts.nix. The *-unhinted builds are left
      # out: they reuse both the file names and the family name of the hinted
      # ones, so buildEnv rejects the pair and fontconfig could not tell them
      # apart anyway.
      ++ lib.optionals config.commonHm.isCachyOS (with pkgs; [
        ioskeley-mono.normal
        ioskeley-mono.normal-NL
        ioskeley-mono.normal-NF
        ioskeley-mono.normal-term
        ioskeley-mono.normal-NL-NF
        ioskeley-mono.normal-term-NF
      ]);

    # Let home-manager take over an existing plain ~/.zshrc (e.g. one created
    # by zsh-newuser-install); otherwise the zsh module's .zshrc would be a
    # clobber and never get written (leaving starship etc. inactive).
    # Note: the zsh module writes ~/.zshrc under the home-relative key
    # "./.zshrc" (dotDir defaults to the home directory), so force must be set
    # on that exact key to merge with it.
    home.file."./.zshrc" = lib.mkIf config.programs.zsh.enable {
      force = true;
    };

    # GTK apps on this machine rewrite their config files in place (a real
    # ~/.gtkrc-2.0 reappears after a switch), so home-manager would try to back
    # them up on every switch — and a leftover *.backup then blocks activation:
    # "Existing file '~/.gtkrc-2.0.backup' would be clobbered by backing up
    # '~/.gtkrc-2.0'". Overwrite without a backup, like ./.zshrc above.
    gtk.gtk2.force = true;
    # The gtk module only defines these xdg.configFile entries when gtk is
    # enabled (its condition is `gtk.enable && gtk.gtkN.enable`). Setting force
    # on an entry with no source/text fails eval for users without a gtk
    # profile (e.g. sven, aaron), so disable the entry under the same condition:
    # home-manager filters disabled files out before it reads their source.
    xdg.configFile."gtk-3.0/settings.ini" = {
      force = true;
      enable = config.gtk.enable && config.gtk.gtk3.enable;
    };
    xdg.configFile."gtk-4.0/settings.ini" = {
      force = true;
      enable = config.gtk.enable && config.gtk.gtk4.enable;
    };

    # ~/.ssh/config must be a real file owned by the user. ssh refuses one it does
    # not own ("Bad owner or permissions"), and home-manager can only deploy its
    # generated config as a symlink into /nix/store — where files are owned by
    # `nobody` on the CachyOS deployment, so every ssh invocation fails. (A NixOS
    # host keeps root-owned store files, which ssh does accept, but a real file
    # works there too and keeps one code path for both.)
    #
    # So home-manager's own deployment of the file is disabled and the same
    # generated content is installed as a real 0600 file at activation instead:
    # the content stays declared through programs.ssh (settings), only the
    # deployment step differs. `enable = false` is a plain boolean — `lib.mkIf
    # false` would drop the definition and leave the default `true` — and it is
    # harmless for sven/aaron, who have no ssh module and so no source to read
    # (home-manager filters disabled entries out before it reads one, like the
    # gtk entries above). It also keeps home-manager from ever moving a real
    # ~/.ssh/config aside to ~/.ssh/config.backup, so a hand-written config that
    # predates this stays where it is.
    home.file.".ssh/config".enable = false;
    # Gate on the same condition that produces the source (programs.ssh with
    # settings), not on the developer-tools flag: otherwise a user with ssh
    # enabled but without developer tools gets no ~/.ssh/config at all.
    home.activation.sshConfigRealFile = lib.mkIf
      (config.programs.ssh.enable && config.home.file.".ssh/config".source != null)
      (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m 700 "$HOME/.ssh"
          # Never clobber a hand-written config: keep a backup when the file on
          # disk differs from the generated one.
          if [ -f "$HOME/.ssh/config" ] && [ ! -L "$HOME/.ssh/config" ] \
            && ! ${pkgs.diffutils}/bin/cmp -s ${config.home.file.".ssh/config".source} "$HOME/.ssh/config"; then
            $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv -f "$HOME/.ssh/config" "$HOME/.ssh/config.bak"
            echo "sshConfigRealFile: existing ~/.ssh/config backed up to ~/.ssh/config.bak" >&2
          fi
          # install (not cp) replaces the destination with the wanted mode; the
          # source is home-manager's generated text file, which stays in the store.
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 600 ${config.home.file.".ssh/config".source} "$HOME/.ssh/config"
        ''
      );

    # Standalone home-manager only (this CachyOS host): NixOS hosts get the key
    # from the system unit (services/ssh-user-keys.nix) at boot/switch, so HM
    # must not touch keys there. On CachyOS there is no system agenix, so decrypt
    # the identity with the machine's host key (root-only -> sudo; prompts once
    # if sudo is not passwordless) and install it. Existing keys are never
    # touched; no sudo -> a warning with the manual one-liner.
    home.activation.installFamilySshKey = lib.mkIf
      (config.commonHm.isCachyOS && builtins.elem config.home.username [ "nicky" "aeiuno" "sven" "aaron" ])
      (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        key="$HOME/.ssh/agenix_${config.home.username}"
        secret=${../secrets/ssh-user-${config.home.username}.key.age}
        if [ ! -f "$key" ]; then
          if [ -z "''${DRY_RUN_CMD:-}" ]; then
            mkdir -p -m 700 "$HOME/.ssh"
            # Plain sudo: silent when wheel is passwordless, otherwise it asks
            # once (the key is then present and this never runs again). No tty
            # -> sudo fails fast and the warning below prints the manual command.
            if ( umask 077; sudo ${pkgs.age}/bin/age --decrypt \
                   -i /etc/ssh/ssh_host_ed25519_key "$secret" > "$key" ) \
               && [ -s "$key" ]; then
              chmod 600 "$key"
              echo "installFamilySshKey: installed $key using the host key" >&2
            else
              rm -f "$key"
              echo "installFamilySshKey: could not decrypt $secret with the host key" >&2
            fi
          else
            echo "installFamilySshKey: $key missing; run once: sudo ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key $secret > ~/.ssh/agenix_${config.home.username}" >&2
          fi
        fi
      '');

    # Symlink ~/sync to the shared syncthing data directory (/sync is created by the
    # system services.syncthing module, so create the symlink at activation time).
    home.activation.linkSyncDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -L "$HOME/sync" ]; then
        $DRY_RUN_CMD ln -sfn /sync "$HOME/sync"
      elif [ -e "$HOME/sync" ]; then
        # A real directory/file here means the pre-migration layout (or a
        # user-created dir); `ln -sfn` would nest a link inside it or delete
        # a file, so leave it alone.
        echo "warning: $HOME/sync exists and is not a symlink; leaving it alone" >&2
      elif [ -d /sync ]; then
        $DRY_RUN_CMD ln -s /sync "$HOME/sync"
      else
        echo "warning: /sync does not exist; not creating ~/sync symlink"
      fi
    '';

    # British English by default for every user session. The OS/console locale
    # is already en_GB (roles/i18n/fr_BE.nix / /etc/locale.conf), but KDE
    # Plasma caches its own per-user language and formats in
    # ~/.config/plasma-localerc and can pin an old en_US choice that shadows
    # the system default. LANG is exported so shells/new processes pick up
    # British English too, while the fr_BE LC_* categories (time, numbers,
    # EUR, ...) keep coming from the system locale.
    home.sessionVariables = lib.mkMerge [
      { LANG = "en_GB.UTF-8"; }
      # zsh reads its locale before ~/.zshenv runs, so the LOCALE_ARCHIVE that
      # home-manager exports (in hm-session-vars.sh, sourced from .zshenv) lands
      # too late on CachyOS: nix's glibc then finds no locale archive and the
      # shell comes up in the C locale. There zsh measures starship's multibyte
      # prompt (the "❯" and git-branch glyphs) in bytes, and ALWAYS_LAST_PROMPT's
      # redraw lands ~2 columns off, so the first two characters of the command
      # look duplicated when Tab completion redraws the line. Assigning LC_CTYPE
      # to glibc's built-in C.UTF-8 (no archive needed) makes zsh re-read the
      # locale as UTF-8. CachyOS-only: NixOS ships its archive session-wide.
      (lib.mkIf config.commonHm.isCachyOS { LC_CTYPE = "C.UTF-8"; })
    ];

    xdg.configFile."plasma-localerc" = {
      force = true; # Plasma may have written a real file; HM installs a symlink.
      text = ''
        [Formats]
        LANG=en_GB.UTF-8

        [Translations]
        Language=en_GB
      '';
    };

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
          # The CachyOS SDDM Wayland (KWin) greeter leaves WAYLAND_DISPLAY in
          # the session environment. Plasma's launcher (startplasma-wayland)
          # unsets it so KWin takes DRM, but Hyprland's start-hyprland does not,
          # and aquamarine then runs nested (black screen). SDDM starts the
          # session via `$SHELL --login`, which sources ~/.zprofile, so clearing
          # it here makes the Hyprland session behave like Plasma. Only needed
          # on CachyOS (the NixOS config does not leak the variable).
          profileExtra = lib.mkIf config.commonHm.isCachyOS ''
            unset WAYLAND_DISPLAY
          '';
        };
        command-not-found.enable = true;
        # Client side of the family identities: the key installed by
        # services/ssh-user-keys.nix is ~/.ssh/agenix_<user>, not the default
        # id_ed25519 (which may be a personal key, e.g. nicky's GitHub
        # identity). Point ssh at it for the family hosts.
        ssh = lib.mkIf
          (builtins.elem config.home.username [ "nicky" "aeiuno" "sven" "aaron" ])
          {
            enable = true;
            settings = {
              "laptop-hera laptop-p16 laptop-xps nestor" = {
                IdentityFile = [ "~/.ssh/agenix_${config.home.username}" ];
              };
            };
          };
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
        tmux = {
          enable = true;
          mouse = true;
          clock24 = true;
          escapeTime = 0;
          keyMode = "vi";
          historyLimit = 10000;
          baseIndex = 1;
          sensibleOnTop = true;
          secureSocket = true;
          extraConfig = ''
            set -g renumber-windows on
            set -g focus-events on
            set -as terminal-overrides ',xterm-256color:RGB'
          '';
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
