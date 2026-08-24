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

    # DoH locked to the family filter (otherwise Firefox could bypass the
    # network DNS filtering via an unfiltered DoH resolver).
    DNSOverHTTPS = {
      Enabled = true;
      ProviderURL = "https://family.cloudflare-dns.com/dns-query";
      Locked = true;
    };

    # No private browsing / forget button: browsing stays visible to parents.
    DisablePrivateBrowsing = true;
    DisableForgetButton = true;

    # Force HTTPS everywhere.
    HttpsOnlyMode = "force_enabled";

    # Never grant sensitive permissions without an explicit parent decision.
    Permissions = {
      Camera = { BlockNewRequests = true; Locked = true; };
      Microphone = { BlockNewRequests = true; Locked = true; };
      Location = { BlockNewRequests = true; Locked = true; };
      Notifications = { BlockNewRequests = true; Locked = true; };
      ScreenShare = { BlockNewRequests = true; Locked = true; };
    };

    # No installing extra search engines; lock the remaining about: pages.
    SearchEngines.PreventInstalls = true;
    BlockAboutProfiles = true;
    BlockAboutSupport = true;
    DisableSafeMode = true;

    # Read-only family bookmarks.
    ManagedBookmarks = [
      { toplevel_name = "Family"; }
      { title = "Gmail"; url = "https://mail.google.com"; }
      { title = "Qwant"; url = "https://www.qwant.com"; }
      { title = "DuckDuckGo"; url = "https://duckduckgo.com"; }
      { title = "Typing (Dance Mat)"; url = "https://www.dancemattyping.org"; }
      { title = "Typing (TypingClub)"; url = "https://www.typingclub.com"; }
      { title = "Disney+"; url = "https://www.disneyplus.com"; }
      { title = "Prime Video"; url = "https://www.primevideo.com"; }
      { title = "Netflix"; url = "https://www.netflix.com"; }
    ];

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
