{
  description = "extended fork of wasi libc";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      fenix,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            fenix.overlays.default
          ];
        };

        fenixPkgs = fenix.packages.${system};
        rustToolchain = fenixPkgs.combine [
          fenixPkgs.complete.toolchain
          fenixPkgs.targets.wasm32-unknown-unknown.stable.completeToolchain
          fenixPkgs.targets.wasm32-unknown-unknown.latest.rust-std
          (fenixPkgs.complete.withComponents [
            "cargo"
            "clippy"
            "rust-src"
            "rustc"
            "rustfmt"
          ])
        ];

        crossPkgs = pkgs.pkgsCross.wasi32;

      in
      rec {
        name = "wasix-libc";
        # TODO: All the code here is a mess, clean it up

        # Build the sysroot in this repo
        packages.build-sys-root = pkgs.writeShellScriptBin "build-sys-root" ''
          nix develop . --command bash build32.sh
        '';

        # Environment for building the sysroot
        devShells.default =
          # crossPkgs.callPackage (
          #   {
          #     stdenvNoCC,
          #     cmake,
          #     llvmPackages_14,
          #     python3,
          #   }:
          pkgs.stdenvNoCC.mkDerivation {
            name = "foo";
            nativeBuildInputs = [
              (pkgs.wrapCCWith {
                cc = pkgs.llvmPackages_14.clang.cc;
                bintools = pkgs.llvmPackages_14.bintools.override {
                  defaultHardeningFlags = [ ];
                };
                libcxx = pkgs.llvmPackages_14.libcxx;
                extraBuildCommands = ''
                  # tr '\n' ' ' < $out/nix-support/cc-cflags > cc-cflags.tmp
                  # mv cc-cflags.tmp $out/nix-support/cc-cflags
                  echo "-isystem ${pkgs.llvmPackages_14.libclang.lib}/lib/clang/14.0.6/include -I/home/lennart/Documents/wasix-libc/build/libcxx/../../sysroot/include" >> $out/nix-support/cc-cflags
                  echo "" > $out/nix-support/libcxx-cxxflags
                '';
              })
              pkgs.clang
              pkgs.cmake
              pkgs.llvmPackages_14.llvm
              pkgs.llvmPackages_14.lld
              pkgs.llvmPackages_14.clang-tools
              pkgs.python3

              rustToolchain
            ];
            shellHook = ''
              export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -Wno-error=unused-command-line-argument"
              unset NM
              unset AR
            '';
          };

        # Environment with a clang compiler that can target wasm32-wasi
        # _works on my machine_
        devShells.usable-environment = pkgs.callPackage (
          {
            stdenvNoCC,
            llvmPackages_14,
          }:
          (stdenvNoCC).mkDerivation {
            name = "foo";
            nativeBuildInputs = [
              packages.wasix-clang
            ];
          }
        ) { };

        packages.compiler-rt-prebuilt = pkgs.runCommand "compiler-rt-prebuilt" { } ''
          mkdir -p $out/lib/wasi
          cp ${./libclang_rt.builtins-wasm32.a} $out/lib/wasi/libclang_rt.builtins-wasm32.a
        '';

        packages.libclang-include =
          cc:
          pkgs.runCommand "libclang-include" { } ''
            mkdir -p $out
            cp -ar ${cc.lib}/lib/clang/${cc.version}/include $out
          '';

        packages.wasix-clang-no-rt = (
          pkgs.wrapCCWith rec {
            cc = pkgs.llvmPackages_14.clang.cc;
            bintools = pkgs.llvmPackages_14.bintoolsNoLibc.override {
              defaultHardeningFlags = [ ];
            };
            # libcxx = null;
            libcxx = pkgs.llvmPackages_14.libcxx;
            extraBuildCommands =
              ''
                # Otherwise llvm wont built, because nix specifies some unused args
                echo "-Wno-error=unused-command-line-argument" >> $out/nix-support/cc-cflags
                echo "-I/home/lennart/Documents/wasix-libc/build/libcxx/../../sysroot/include" >> $out/nix-support/cc-cflags
                # Dont even try to link the system libcxx
                echo "" > $out/nix-support/libcxx-cxxflags
              ''
              + ''
                mkdir -p "$out"
                rsrc="$out/resource-root"
                ln -sT ${
                  pkgs.symlinkJoin {
                    name = "libclang";
                    paths = [
                      (packages.libclang-include cc)
                    ];
                  }
                } "$rsrc"

                echo "-resource-dir=$rsrc" >> $out/nix-support/cc-cflags
              '';
            libc = null;
          }
        );

        packages.wasix-clang = (
          pkgs.wrapCCWith rec {
            cc = pkgs.llvmPackages_14.clang.cc;
            bintools = pkgs.llvmPackages_14.bintoolsNoLibc.override {
              defaultHardeningFlags = [ ];
            };
            # libcxx = null;
            libcxx = pkgs.llvmPackages_14.libcxx;
            extraBuildCommands =
              ''
                # Otherwise llvm wont built, because nix specifies some unused args
                echo "-Wno-error=unused-command-line-argument" >> $out/nix-support/cc-cflags
                echo "-I/home/lennart/Documents/wasix-libc/build/libcxx/../../sysroot/include" >> $out/nix-support/cc-cflags
                # Dont even try to link the system libcxx
                echo "" > $out/nix-support/libcxx-cxxflags
              ''
              + ''
                mkdir -p "$out"
                rsrc="$out/resource-root"
                ln -sT ${
                  pkgs.symlinkJoin {
                    name = "libclang";
                    paths = [
                      packages.compiler-rt-prebuilt
                      (packages.libclang-include cc)
                    ];
                  }
                } "$rsrc"

                echo "-resource-dir=$rsrc" >> $out/nix-support/cc-cflags
              '';
            libc = null;
          }
        );

        # # Unfinished attempt to build the compiler rt
        # packages.compiler-rt = crossPkgs.callPackage (
        #   {
        #     stdenvNoCC,
        #     llvmPackages_14,
        #     rust-bindgen,
        #     glibc_multi,
        #     cmake,
        #     python3,
        #   }:
        #   (stdenvNoCC.override {
        #     # bintools = (
        #     #   llvmPackages_14.bintools.override {
        #     #     defaultHardeningFlags = [ ];
        #     #   }
        #     # );
        #   }).mkDerivation
        #     {
        #       name = "foo";
        #       src = ./tools/llvm-project/compiler-rt/lib/builtins;
        #       nativeBuildInputs = [
        #         packages.wasix-clang
        #         cmake

        #         llvmPackages_14.llvm
        #         llvmPackages_14.lld
        #         llvmPackages_14.clang-tools
        #         python3
        #       ];
        #       shellHook = ''
        #         export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -Wno-error=unused-command-line-argument"
        #         unset NM
        #         unset AR
        #       '';
        #     }
        # ) { };

        # # Leaving this here in case I need this later on
        # devShells.second = crossPkgs.callPackage (
        #   {
        #     stdenvNoCC,
        #     llvmPackages_14,
        #     llvmPackages_15,
        #     llvmPackages_19,
        #     rust-bindgen,
        #     glibc_multi,
        #     glibc,
        #     cmake,
        #     python3,
        #     clang_14,
        #     clang14Stdenv,
        #   }:
        #   (stdenvNoCC.override {
        #     # bintools = (
        #     #   llvmPackages_14.bintools.override {
        #     #     defaultHardeningFlags = [ ];
        #     #   }
        #     # );
        #   }).mkDerivation
        #     {
        #       name = "foo";
        #       buildInputs = [
        #         # pkgs.llvmPackages_14.clang
        #         # clang_14.

        #         # llvmPackages_14.libcxx
        #         # llvmPackages_14.compiler-rt
        #         # pkgs.llvmPackages_14.clang-unwrapped.lib
        #         llvmPackages_14.libcxx
        #         # llvmPackages_19.clang-unwrapped.lib
        #         pkgs.llvmPackages_14.libclang

        #       ];

        #       CPATH = builtins.concatStringsSep ":" [
        #         (pkgs.lib.makeSearchPathOutput "dev" "include" [ pkgs.llvmPackages_14.libcxx ])
        #         # (pkgs.lib.makeSearchPath "resource-root/include" [ pkgs.llvmPackages_14.clang ])
        #       ];

        #       nativeBuildInputs = [
        #         # (llvmPackages_14.clang.override {
        #         #   bintools = (
        #         #     llvmPackages_14.bintools.override {
        #         #       defaultHardeningFlags = [ ];
        #         #     }
        #         #   );
        #         # }).cc
        #         # pkgs.llvmPackages_14.clang-unwrapped
        #         # llvmPackages_14.libclang
        #         # llvmPackages_14.libcxx
        #         # clang_14
        #         pkgs.llvmPackages_14.clang
        #         # llvmPackages_14.clang-tools

        #         # clang_nolibc
        #         # crossPkgs.llvmPackages_14.clang.cc

        #         # llvmPackages_14.llvm
        #         # llvmPackages_14.llvm
        #         # llvmPackages_14.lld
        #         # llvmPackages_14.clang-tools
        #         # pkgs.llvmPackages_14.clang.cc
        #         # pkgs.clang-tools_14
        #         # pkgs.clang_14.cc
        #         # pkgs.cargo
        #         # pkgs.rustc
        #         # # pkgs.glibc_multi
        #         # # pkgs.glibc_multi.dev
        #         # pkgs.coreutils
        #         # pkgs.nodejs
        #         # pkgs.wget
        #         # pkgs.git
        #         # pkgs.clang_14.cc
        #         cmake
        #         # pkgs.ninja
        #         # pkgs.rsync
        #         # pkgs.gnumake
        #         # pkgs.llvmPackages_14.libllvm.dev
        #         # pkgs.llvmPackages_14.libllvm
        #         # pkgs.llvmPackages_14.lld
        #         # pkgs.wasmer
        #         # pkgs.python3
        #         python3

        #         # rustToolchain
        #       ];
        #       shellHook = ''
        #         # export CC="clang"
        #         # export CXX="clang++"

        #         export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -Wno-error=unused-command-line-argument"
        #         # unset NM
        #         # unset AR
        #         # export LLVM_DIR="{pkgs.llvmPackages_14.libllvm.dev}/lib/cmake/llvm";
        #         # export CLANG_DIR="{pkgs.llvmPackages_14.clang}/";

        #       '';
        #     }
        # ) { };

        # Environment where I can built libc
        # Works, but has a lot of useless settings
        devShells.build-libc-shell = crossPkgs.callPackage (
          {
            stdenvNoCC,
            llvmPackages_14,
            rust-bindgen,
            glibc_multi,
            cmake,
          }:
          (stdenvNoCC.override {
            # bintools = (
            #   llvmPackages_14.bintools.override {
            #     defaultHardeningFlags = [ ];
            #   }
            # );
          }).mkDerivation
            {
              name = "foo";
              nativeBuildInputs = [
                (pkgs.llvmPackages_14.clang.override {
                  bintools = (
                    pkgs.llvmPackages_14.bintools.override {
                      defaultHardeningFlags = [ ];
                    }
                  );
                })
                llvmPackages_14.llvm
                llvmPackages_14.lld
                llvmPackages_14.clang-tools
                cmake
                rustToolchain
              ];
              shellHook = ''
                export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -Wno-error=unused-command-line-argument"
                unset NM
                unset AR
              '';
            }
        ) { };

        # Environment where I can built libcxx
        # Works, but has a lot of useless settings
        devShells.build-libcxx-shell =
          (pkgs.mkShell.override {
            stdenv = pkgs.stdenvNoCC;
            # stdenv = pkgs.llvmPackages_14.stdenv;
            # stdenv = pkgs.pkgsCross.wasi32.llvmPackages_14.stdenv;
            # stdenv = clang_nolibc.stdenv;
            # stdenv =
            #   (pkgs.llvmPackages_14.override {
            #     bintools = (
            #       pkgs.llvmPackages_14.bintools.override {
            #         defaultHardeningFlags = [ ];
            #       }
            #     );
            #   }).stdenv;
            # stdenv =
            #   (pkgs.clang_14.override {
            #     bintools = (
            #       pkgs.llvmPackages_14.bintools.override {
            #         defaultHardeningFlags = [ ];
            #       }
            #     );
            #   }).stdenv;
          })
            {
              buildInputs = [
                (pkgs.wrapCCWith {
                  cc = pkgs.llvmPackages_14.clang.cc;
                  bintools = (
                    pkgs.llvmPackages_14.bintoolsNoLibc.override {
                      defaultHardeningFlags = [ ];
                    }
                  );
                  libcxx = pkgs.llvmPackages_14.libcxx;
                  extraBuildCommands = ''
                    # tr '\n' ' ' < $out/nix-support/cc-cflags > cc-cflags.tmp
                    # mv cc-cflags.tmp $out/nix-support/cc-cflags
                    echo "-isystem ${pkgs.llvmPackages_14.libclang.lib}/lib/clang/14.0.6/include -I/home/lennart/Documents/wasix-libc/build/libcxx/../../sysroot/include" >> $out/nix-support/cc-cflags
                    echo "" > $out/nix-support/libcxx-cxxflags
                  '';
                  libc = null;
                })
                pkgs.cmake
                pkgs.python3
              ];
              shellHook = ''
                export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -Wno-error=unused-command-line-argument -I/home/lennart/Documents/wasix-libc/build/libcxx/../../sysroot/include"
                # unset NM
                # unset AR
              '';
              CPATH = builtins.concatStringsSep ":" [
                (pkgs.lib.makeSearchPathOutput "dev" "include" [ pkgs.llvmPackages_14.libclang.lib ])
                "-isystem ${pkgs.llvmPackages_14.libclang.lib}/lib/clang/14.0.6/include"
                # (pkgs.lib.makeSearchPath "resource-root/include" [ pkgs.llvmPackages_14.clang ])
              ];
              CFLAGS = "-isystem ${pkgs.llvmPackages_14.libclang.lib}/lib/clang/14.0.6/include";
              # LLVM_DIR = "${pkgs.llvmPackages_14.libllvm.dev}/lib/cmake/llvm";
              # STUFF="-isystem /nix/store/c9q5790qgzxxkbcdkmbd67icq1gqija2-libcxx-12.0.1-dev/include -isystem /nix/store/cp0m6qj9xysasirxixyfglcr1122x3ss-libcxxabi-12.0.1-dev/include -isystem /nix/store/jf5j1vybrzjr5fz6pv315m6w9qmbvi9f-compiler-rt-libc-12.0.1-dev/include -iframework /nix/store/48w7px4bh6bjhgfz3w74ij5s24j4mxxn-apple-framework-CoreFoundation-11.0.0/Library/Frameworks -isystem /nix/store/cirjwpbnqsnj0600x3k2643vll58aqf7-libobjc-11.0.0/include -isystem /nix/store/c9q5790qgzxxkbcdkmbd67icq1gqija2-libcxx-12.0.1-dev/include -isystem /nix/store/cp0m6qj9xysasirxixyfglcr1122x3ss-libcxxabi-12.0.1-dev/include -isystem /nix/store/jf5j1vybrzjr5fz6pv315m6w9qmbvi9f-compiler-rt-libc-12.0.1-dev/include -iframework /nix/store/48w7px4bh6bjhgfz3w74ij5s24j4mxxn-apple-framework-CoreFoundation-11.0.0/Library/Frameworks -isystem /nix/store/cirjwpbnqsnj0600x3k2643vll58aqf7-libobjc-11.0.0/include"
            };

        formatter = pkgs.nixfmt-rfc-style;

      }
    );
}
