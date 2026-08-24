# Kid-safe Firefox policies + uBlock Origin for sven and aaron.
#
# User-level policies written by home-manager into each kid's profile, in
# addition to the system-wide programs.firefox.policies (roles/system.nix).
{ ... }:

{
  programs.firefox.policies = {
    # Privacy / telemetry / Mozilla account
    DisableTelemetry = true;
    DisableFirefoxStudies = true;
    DisablePocket = true;
    DisableFeedbackCommands = true;
    DisableFirefoxAccounts = true;

    # No stored passwords / autofill for kids
    PasswordManagerEnabled = false;
    OfferToSaveLogins = false;
    DisablePasswordReveal = true;
    AutofillAddressEnabled = false;
    AutofillCreditCardEnabled = false;

    # Locked tracking protection
    TrackingProtection = {
      Locked = true;
      Cryptomining = true;
      Fingerprinting = true;
      EmailTracking = true;
    };

    # Tame the new-tab/home page (no promoted/suggested content)
    FirefoxHome = {
      Search = true;
      TopSites = false;
      Highlights = false;
      Pocket = false;
      Snippets = false;
    };

    # No about:config / devtools
    BlockAboutConfig = true;
    DisableDeveloperTools = true;

    # No update / first-run / default-browser noise (updates via NixOS)
    DisableAppUpdate = true;
    DontCheckDefaultBrowser = true;
    OverrideFirstRunPage = "";
    OverridePostUpdatePage = "";

    # Always ask where to save downloads (system policy already sends to temp)
    PromptForDownloadLocation = true;

    # uBlock Origin: force-installed and locked; block all other add-ons.
    ExtensionSettings = {
      "*" = {
        installation_mode = "blocked";
      };
      "uBlock0@raymondhill.net" = {
        installation_mode = "force_installed";
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        default_area = "navbar";
      };
    };
  };
}
