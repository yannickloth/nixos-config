(import ../../../lib).privateNetRules {
  udp = [ "5353" ];
  v4 = (import ../../../lib).privateV4LinkLocal;
}
