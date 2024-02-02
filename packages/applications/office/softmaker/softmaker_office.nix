{ callPackage
, fetchurl

  # This is a bit unusual, but makes version and hash easily
  # overridable. This is useful when people have an older version of
  # Softmaker Office or when the upstream archive was replaced and
  # nixpkgs is not in sync yet.
, officeVersion ? {
  version = "1032";
  edition = "2021";
  hash = "sha256-LchSqLVBdkmWJQ8hCEvtwRPgIUSDE0URKPzCkEexGbc=";
  #         # 2018
  #         edition = "2018";
  #         version = "982";
  #         hash = "sha256-A45q/irWxKTLszyd7Rv56WeqkwHtWg4zY9YVxqA/KmQ=";
  #         # 2021
  #         edition = "2021";
  #         version = "1064";
  #         hash = "sha256-UyA/Bl4K9lsvZsDsPPiy31unBnxOG8PVFH/qisQ85NM=";
  #         # 2024         
  #         edition = "2024";
  #         version = "1204";
  #         hash = "sha256-E58yjlrFe9uFiWY0nXoncIxDgvwXD+REfmmdSZvgTTU=";
  #         # 2024
  #         edition = "2024";
  #         version = "1208";
  #         hash = "sha256-qe5I2fGjpANVqd5KIDIUGzqFVgv+3gBoY7ndp0ByvPs=";
}

, ... } @ args:

callPackage ./generic.nix (args // rec {
  inherit (officeVersion) version edition;

  pname = "softmaker-office";
  suiteName = "SoftMaker Office";

  src = fetchurl {
    inherit (officeVersion) hash;
    url = "https://www.softmaker.net/down/softmaker-office-${edition}-${version}-amd64.tgz";
  };

  archive = "office${edition}.tar.lzma";
})
