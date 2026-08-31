# Shared shell aliases + helper functions for all users.
#
# Curated safe subset of the classic cyberciti bash-aliases list
# (https://www.cyberciti.biz/tips/bash-aliases-mac-centos-linux-unix.html),
# adapted to this repo:
#   - no distro/server/host-specific aliases (iptables, nginx, backups, WOL, ...)
#   - no aliases pointing at tools that may be missing (colordiff, atop, netstat);
#     tools referenced here are installed system-wide in roles/system.nix.
#   - `ls`/`ll`/`l`/`la`/`..` and the nixos-rebuild `nrs*`/`myip` aliases live in
#     roles/shell.nix (system-wide, with `ls = lsd`); they are NOT redefined here
#     to avoid silently overriding the system set.
#
# Aliases are set via home-manager's `home.shellAliases`: each `name = "value"`
# defines a shell alias `alias name='value'` in ~/.zshrc. They are written into
# zsh (all users use zsh via programs.zsh.enable in common-hm.nix).
{ ... }:

{
  home.shellAliases = {
    # ---- Navigation ---------------------------------------------------------
    # `...`/`....`/`.....` are cd shortcuts (the single `..` is already defined
    # system-wide in roles/shell.nix). NOTE: levels here are *incremental*
    # (`...` = 2 levels up), unlike the page's inconsistent .. / ... definitions.
    "..." = "cd ../.."; # go up two directories
    "...." = "cd ../../.."; # go up three directories
    "....." = "cd ../../../.."; # go up four directories

    # ---- Safety nets (page #6 / #16) ----------------------------------------
    # `-i` prompts before overwriting a destination (cp/mv) or removing a file
    # (rm). `-I` (rm) prompts only once for 3+ files or recursive deletes —
    # less annoying than `-i`, which asks on every file. `--preserve-root`
    # refuses to act on `/` (chmod/chown/chgrp/rm). `-p` on mkdir creates all
    # parent dirs and is not an error if the dir already exists.
    cp = "cp -i"; # confirm before overwriting an existing file
    mv = "mv -i"; # confirm before overwriting an existing file
    ln = "ln -i"; # confirm before overwriting an existing link
    rm = "rm -I --preserve-root"; # confirm 3+ files/recursive; never delete "/"
    mkdir = "mkdir -p"; # create missing parent dirs; no error if it exists
    chown = "chown --preserve-root"; # never change ownership of "/" itself
    chmod = "chmod --preserve-root"; # never change perms of "/" itself
    chgrp = "chgrp --preserve-root"; # never change group of "/" itself

    # ---- Readability (page #1 / #3 / #30) ------------------------------------
    # `--color=auto` only colors when output is a terminal (not piped), so it
    # won't inject ANSI codes into scripts/files. `df/du/free -h` print sizes in
    # human-readable units; `du -c` adds a grand total line. `diff --color=auto`
    # colors additions/removals without needing an extra package (like colordiff).
    grep = "grep --color=auto"; # colorize matches in the terminal
    egrep = "egrep --color=auto"; # same, extended regexp variant
    fgrep = "fgrep --color=auto"; # same, fixed-string variant
    df = "df -h"; # human-readable filesystem usage
    du = "du -ch"; # directory size, human-readable, with grand total
    free = "free -h"; # memory usage in human-readable units
    bc = "bc -l"; # calculator with math library (trig, sqrt, ...)
    diff = "diff --color=auto"; # colored unified diff, no extra package

    # ---- System monitoring ----------------------------------------------------
    # `top` runs htop (already installed system-wide in roles/system.nix) — a
    # friendlier interactive process monitor than the plain `top`. `ports` shows
    # listening TCP/UDP sockets via `ss` (iproute2, always present); `-u` UDP,
    # `-l` only listening, `-n` numeric ports. No `-p` (pid) so it works without
    # root — process names need sudo.
    top = "htop"; # interactive process/memory/CPU monitor
    ports = "ss -tuln"; # list listening TCP+UDP sockets, numeric, no root needed

    # ---- Shortcuts (page #8 / #10 / #27) --------------------------------------
    # `path` prints the PATH entries one per line (`\n` literal, since echo -e);
    # `now`/`nowdate` format the current time/date. `vi` points vim at vim
    # (avoids the classic vi→vim confusion). `wget -c` continues a partial
    # download instead of restarting.
    h = "history"; # show shell command history
    j = "jobs -l"; # list background jobs with PID
    path = "echo -e \${PATH//:/\\n}"; # print each PATH entry on its own line
    now = "date +\"%T\""; # current time as HH:MM:SS
    nowdate = "date +\"%d-%m-%Y\""; # current date as DD-MM-YYYY
    vi = "vim"; # use vim when you type vi
    wget = "wget -c"; # resume interrupted downloads

    # ---- Tools already installed system-wide (roles/system.nix) ---------------
    # Quick entry points for tools that are otherwise verbose to invoke.
    sysinfo = "fastfetch"; # system summary (OS, kernel, hardware)
    stui = "s-tui"; # CPU temp/frequency/power dashboard
    prettyjson = "jq ."; # pretty-print JSON piped from stdin
    help = "cht.sh"; # cheat-sheet lookup for any command
  };

  # zsh helper *functions* and settings can't be plain aliases (they take
  # arguments / are env vars), so they go in programs.zsh.initContent, appended
  # to ~/.zshrc. Merges fine with each user's own initContent (home-manager
  # concatenates `lines`). History tuning is handled by the `programs.zsh.history`
  # options in common-hm.nix, not here.
  programs.zsh.initContent = ''
    # --- Fuzzy finder + smart cd (fzf/zoxide, installed in roles/system.nix) --
    # fzf: Ctrl-R searches history, Ctrl-T picks files, Alt-C cd's into a dir.
    # zoxide: `z <dir>` jumps to a directory you visit often; `zi` = interactive.
    eval "$(fzf --zsh)"
    eval "$(zoxide init zsh)"

    # --- mkcd: create a directory (with parents) and cd into it in one step ---
    # usage: mkcd path/to/dir
    mkcd() { mkdir -p -- "$1" && cd -- "$1"; }

    # --- zd / jc: convenience wrappers ---------------------------------------
    # jc: cd using fzf (interactive dir picker). zd: same but with zoxide's rank.
    jc() { cd "$(fd --type d | fzf)" ; }
    zd() { cd "$(zoxide query --list | fzf)" ; }
  '';
}
