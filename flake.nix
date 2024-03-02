{
	description = "KLEE";

	inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-23.11";
	};

	outputs = { self, nixpkgs }:
	let
		system = "x86_64-linux";
		pkgs = import nixpkgs { inherit system; };
		llvm = pkgs.llvm;
		clang = pkgs.clang;
		localeSrcBase = "uClibc-locale-030818.tgz";
		localeSrc = builtins.fetchurl {
			url = "http://www.uclibc.org/downloads/${localeSrcBase}";
			sha256 = "xDYr4xijjxjZjcz0YtItlbq5LwVUi7k/ZSmP6a+uvVc=";
		};
		klee-uclibc = pkgs.stdenv.mkDerivation {
			pname = "klee-uclibc";
			version = "955d502cc1f0688e82348304b053ad787056c754";
			src = builtins.fetchGit {
				url = "https://github.com/klee/klee-uclibc";
				rev = "955d502cc1f0688e82348304b053ad787056c754";
			};

			nativeBuildInputs = [
				clang
				pkgs.curl
				llvm
				pkgs.python3
				pkgs.which
			];
			buildInputs = [
			];

			# Some uClibc sources depend on Linux headers.
			UCLIBC_KERNEL_HEADERS = "${self}/include";

			# HACK: needed for cross-compile.
			# See https://www.mail-archive.com/klee-dev@imperial.ac.uk/msg03141.html
			KLEE_CFLAGS = "-idirafter ${clang}/resource-root/include";

			prePatch = ''
				patchShebangs ./configure
				patchShebangs ./extra
			'';

			# klee-uclibc configure does not support --prefix, so we override configurePhase entirely
			configurePhase = ''
				CC=clang ./configure ${pkgs.lib.escapeShellArgs (
					["--make-llvm-lib"]
					#++ lib.optional (!debugRuntime) "--enable-release"
					#++ lib.optional runtimeAsserts "--enable-assertions"
				)}

				# Set all the configs we care about.
				configs=(
					PREFIX=$out
					"UCLIBC_DOWNLOAD_PREGENERATED_LOCALE_DATA=n"
					"RUNTIME_PREFIX=/"
					"DEVEL_PREFIX=/" 
				)

				for configFile in .config .config.cmd; do
					for config in "''${configs[@]}"; do
						prefix="''${config%%=*}="
						if grep -q "$prefix" "$configFile"; then
							sed -i "s"'\001'"''${prefix}"'\001'"#''${prefix}"'\001'"g" "$configFile"
						fi
						echo "$config" >> "$configFile"
					done
				done
			'';

			# Link the locale source into the correct place
			preBuild = ''
				ln -sf ${localeSrc} extra/locale/${localeSrcBase}
			'';

			makeFlags = ["HAVE_DOT_CONFIG=y"];
		};
		kleePythonEnv = (pkgs.python3.withPackages (ps: with ps; [ tabulate ]));
		klee = pkgs.stdenv.mkDerivation {
			pname = "KLEE";
			version = "3.2-pre";
			src = builtins.fetchGit {
				url = "https://github.com/danielschemmel/klee";
				ref = "pythonpath";
				rev = "31bcfaa8306903c4296d0b51e0e09e1fe6059498";
			};

			nativeBuildInputs = [
				clang
				pkgs.cmake
				pkgs.cryptominisat
				pkgs.gperftools
				pkgs.gtest
				llvm
				pkgs.mold
				pkgs.ninja
				pkgs.sqlite
				pkgs.stp
				pkgs.z3

				kleePythonEnv
				(pkgs.lit.override { python = kleePythonEnv; })
			];
			buildInputs = [
			];
			nativeCheckInputs = [
			];

			cmakeBuildType = "Release";
			cmakeFlags = [
				"-GNinja"
				"-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON"
				# "-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=mold"
				# KLEE will pick up LLVM from `llvm-config` (part of pkgs.llvm), but it will by default try to find clang
				# relative to that path, so we have to pass the clang paths explicitly.
				"-DLLVMCC=${clang}/bin/clang"
				"-DLLVMCXX=${clang}/bin/clang++"
				"-DENABLE_UNIT_TESTS=ON"
				"-DENABLE_SYSTEM_TESTS=ON"
				"-DGTEST_SRC_DIR=${pkgs.gtest.src}"
				"-DGTEST_INCLUDE_DIR=${pkgs.gtest.src}/googletest/include"
				"-DENABLE_POSIX_RUNTIME=ON"
				"-DKLEE_UCLIBC_PATH=${klee-uclibc}"
			];

			#buildPhase = "ninja -j $NIX_BUILD_CORES";

			prePatch = ''
				patchShebangs .
			'';

			checkPhase = ''
				ninja unittests systemtests
			'';
			doCheck = true;
		};
	in
	{
		devShells.${system} = {
			klee = klee;
			default = klee;
		};
		packages.${system} = {
			inherit clang klee;

			docker = pkgs.dockerTools.buildImage {
				name = "kleenix";
				tag = "latest";

				extraCommands = "mkdir -m 1777 tmp";

				copyToRoot = pkgs.buildEnv {
					name = "image-root";
					paths = [
						pkgs.bashInteractive
						pkgs.coreutils
						pkgs.gnugrep
						pkgs.which
						klee
						clang
						#pkgs.gllvm
						pkgs.wllvm

						pkgs.ncdu
					];
					pathsToLink = [ "/bin" ];
				};

				config = {
					Entrypoint = "/bin/sh";
				};
			};

			kleePythonEnv = kleePythonEnv;

			default = pkgs.symlinkJoin {
				name = "klee-full";
				paths = [
					klee
					clang
					#pkgs.gllvm
					pkgs.wllvm
				];
			};
		};
	};
}
