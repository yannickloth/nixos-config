# home-manager wiring for the LibreOffice MCP extension (packages/libreoffice-mcp).
#
#   imports = [ ../../packages/libreoffice-mcp/home.nix ];
#   libreofficeMcp.enable = true;
#
# The extension runs an MCP server *inside* the already-running soffice process
# (streamable HTTP on https://127.0.0.1:<port>/mcp, loopback only), so an agent
# sees the same document the user sees. Tools appear as `libreoffice_*` in
# OpenCode/Claude once the endpoint is registered as a remote MCP server
# (users/opencode.nix), which reads the port from this module.
#
# Installation is deliberately not a wrapper around pkgs.libreoffice: the Nix
# store is read-only and LibreOffice resolves extensions from the user profile
# only, so the .oxt is registered with `unopkg` in an activation script — the
# same imperatively-populated profile a manual Tools > Extension Manager
# install would write. The stamp file makes it run once per artifact change;
# LibreOffice has to be restarted once for the new extension to load.
#
# Trust model, so the TLS plumbing below is not mistaken for security theatre:
# the server has NO authentication (upstream ships none), so any local process
# can drive the open documents. The self-signed TLS cert is what keeps a web
# page out: the server answers with Access-Control-Allow-Origin: * and browsers
# can reach loopback, but they cannot complete a handshake with an unknown cert
# without the user accepting it. That is why EnableSSL is left on (patching it
# off would be simpler for the client and strictly worse here), and why the cert
# is exported only to Node clients of this user.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.libreofficeMcp;

  oxt = "${cfg.package}/lib/libreoffice-mcp-extension.oxt";

  # LibreOffice generates a self-signed cert for the server it embeds (SAN
  # localhost + 127.0.0.1) here on first start. Node-based MCP clients reject it
  # unless it is a known CA, so it is exported as NODE_EXTRA_CA_CERTS. The path
  # is stable; until the first LibreOffice start the file does not exist yet and
  # Node ignores the variable.
  certFile = "${config.xdg.configHome}/libreoffice/mcp-certs/server.pem";
in
{
  options.libreofficeMcp = {
    enable = mkEnableOption "the LibreOffice MCP extension (MCP server inside the running soffice process)";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./default.nix { inherit (config.libreofficeMcp) port; };
      defaultText = literalExpression "pkgs.callPackage ./default.nix { inherit (config.libreofficeMcp) port; }";
      description = ''
        The extension artifact (packages/libreoffice-mcp/default.nix); must
        provide lib/libreoffice-mcp-extension.oxt. It is rebuilt with `port`
        patched in, so a custom package must honour the same option.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8765;
      description = ''
        Port the embedded MCP server listens on (loopback only, TLS). Must be
        unique per user on a shared host: the extension treats any healthy
        "LibreOffice MCP" answer on its port as its own server and then never
        starts one, so two users on the same port silently share the first
        user's documents. Users/opencode.nix points the MCP client at the same
        number.
      '';
    };

    libreoffice = mkOption {
      type = types.package;
      default = pkgs.libreoffice;
      defaultText = literalExpression "pkgs.libreoffice";
      description = "LibreOffice whose `unopkg` registers the extension. Keep the default so the extension and the app are the same build.";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      # `unopkg add` deploys into the LibreOffice user profile, so it wants a
      # writable HOME and either a running instance to hand the extension to or
      # none at all. A failure is reported but never aborts the switch (the user
      # may have a document open mid-save); the stamp is only written on
      # success, so the next switch retries.
      #
      # Activation scripts run under `set -eu -o pipefail`, so every command
      # whose status is ignored needs an explicit `|| true` — an unguarded
      # failing `grep` here would abort the whole switch.
      home.activation.libreofficeMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        oxt=${escapeShellArg oxt}
        stamp="$HOME/.local/state/home-manager/libreoffice-mcp.stamp"
        current=""
        if [ -f "$stamp" ]; then
          current=$(cat "$stamp")
        fi
        if [ "$current" != "$oxt" ]; then
          mkdir -p "$(dirname "$stamp")"
          # The .oxt ships a simple-license blob ('accept-by=admin'), so unopkg
          # prompts on stdin even when headless — feed it the acceptance. Output
          # is captured rather than discarded: when unopkg refuses (a locked
          # profile is the usual cause) the last line is what says why.
          if out=$(printf 'yes\n' | ${cfg.libreoffice}/bin/unopkg add --force "$oxt" 2>&1); then
            echo "$oxt" > "$stamp"
            echo "libreoffice-mcp: extension registered — restart LibreOffice to load it"
          else
            warnEcho "libreoffice-mcp: could not register the extension; close LibreOffice and re-run home-manager switch"
            msg=$(printf '%s\n' "$out" | grep -v '^warn:' | tail -n 2 || true)
            if [ -n "$msg" ]; then
              warnEcho "  $msg"
            fi
          fi
        fi
      '';

      # The generated cert has to reach Node-based MCP clients. Two variables, on
      # purpose: home.sessionVariables is what interactive shells source
      # (hm-session-vars.sh), while systemd.user.sessionVariables is what GUI and
      # systemd-launched apps see (it is written to environment.d) — without the
      # second, opencode-desktop launched from the Plasma session would still
      # reject the cert. mkDefault in both so a user can override.
      home.sessionVariables.NODE_EXTRA_CA_CERTS = mkDefault certFile;
      systemd.user.sessionVariables.NODE_EXTRA_CA_CERTS = mkDefault certFile;
    })

    # Turning the option off must actually stop the server: the extension is
    # registered in the LibreOffice profile, which home-manager does not own, so
    # without this the MCP endpoint would keep running (unauthenticated, on the
    # user's open documents) after `enable = false`. Guarded by the stamp so
    # accounts that never enabled it do nothing here.
    (mkIf (!cfg.enable) {
      home.activation.libreofficeMcpRemove = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        stamp="$HOME/.local/state/home-manager/libreoffice-mcp.stamp"
        if [ -f "$stamp" ]; then
          ${cfg.libreoffice}/bin/unopkg remove org.mcp.libreoffice.extension >/dev/null 2>&1 || true
          # Success is defined by what the profile says afterwards, not by
          # unopkg's exit status: removing an extension that is no longer
          # registered is not an error, while a still-registered one means
          # unopkg could not act (a locked profile).
          if ${cfg.libreoffice}/bin/unopkg list 2>/dev/null | grep -q 'Identifier: org.mcp.libreoffice.extension'; then
            warnEcho "libreoffice-mcp: could not remove the extension; close LibreOffice and re-run home-manager switch"
          else
            rm -f "$stamp"
            echo "libreoffice-mcp: extension removed (libreofficeMcp.enable = false) — restart LibreOffice"
          fi
        fi
      '';
    })
  ];
}
