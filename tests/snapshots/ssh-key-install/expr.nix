(import ../../../lib).sshKeyInstallScript {
  installBin = "install";
  keys = [ { user = "nicky"; home = "/home/nicky"; secret = "/run/agenix/ssh-user-nicky"; } ];
}
