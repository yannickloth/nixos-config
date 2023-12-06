{ lib, stdenv, fetchFromGitHub, kernel }:

stdenv.mkDerivation rec {
	pname = "xpad";
	version = "0.4";

	src = fetchFromGitHub {
		owner = "paroj";
		repo = "xpad";
		rev = "eddb513e04697348fd7ad6961c6d5cfaa7467998";
		#rev = "1821d2822783e8c24733b05138e06d9a9f4d309d";
		#hash = "sha256-+KSv+fDwfzsT/rqonCCbl451LzdtDzGvhP5MrMWpfZg=";
		hash = "sha256-7vqMj46yUZ17U13xbbcEnK2cO410tYO6y/t5DyPHp74=";
	};

	setSourceRoot = ''
		export sourceRoot=$(pwd)/source
	'';

	nativeBuildInputs = kernel.moduleBuildDependencies;

	makeFlags = kernel.makeFlags ++ [
		"-C"
		"${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
		"M=$(sourceRoot)"
	];

	buildFlags = [ "modules" ];
	installFlags = [ "INSTALL_MOD_PATH=${placeholder "out"}" ];
	installTargets = [ "modules_install" ];

	meta = with lib; {
		description = "xpad kernel module";
		homepage = "https://github.com/paroj/xpad";
		license = licenses.gpl2Plus;
		platforms = platforms.linux;
	};
}
