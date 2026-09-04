package devshell

import (
	devshell "github.com/tonky/enve/schema/v1:schema"
	"github.com/tonky/enve/schema/v1/env:env"
	"github.com/tonky/enve/pkgs:pkgs"
)

dev: devshell.#DevEnvironment & {
	name: "rustdesk-dev"

	tools: [
		// 1. Flutter Toolchain (for client GUI builds)
		pkgs.flutter,

		// 2. C/C++ Compilers, Assemblers & Build Systems
		pkgs.gcc,
		pkgs.clang,
		pkgs.gnumake,
		pkgs.cmake,
		pkgs.ninja,
		pkgs.pkg_config,
		pkgs.nasm,
		pkgs.yasm,

		// 3. Desktop GUI, Display, Audio & Streaming Libraries
		pkgs.gtk3,
		pkgs.libx11,
		pkgs.libxext,
		pkgs.libxi,
		pkgs.libxtst,
		pkgs.libxcursor,
		pkgs.libxrandr,
		pkgs.libxfixes,
		pkgs.libxdo,
		pkgs.libxkbcommon,
		pkgs.alsa_lib,
		pkgs.libpulseaudio,
		pkgs.pipewire,
		pkgs.gstreamer,
		pkgs.gst_plugins_base,

		// 4. Codecs & Media Libraries (enables --features linux-pkg-config)
		pkgs.libvpx,
		pkgs.libyuv,
		pkgs.libopus,
		pkgs.libaom,
		pkgs.ffmpeg,
		pkgs.openssl,
		pkgs.pam,
		pkgs.dbus,
		"libsodium",

		// 5. Archive & Fetch Utilities
		pkgs.git,
		pkgs.curl,
		pkgs.wget,
		pkgs.zip,
		pkgs.unzip,
		pkgs.vcpkg,
	]

	environment: env.#RustEnv & env.#PosixEnv & {
		RUST_BACKTRACE: 1
		VCPKG_ROOT: "$PWD/.vcpkg"
		VCPKG_FORCE_SYSTEM_BINARIES: 1
		OPENSSL_NO_VENDOR: 1
		SODIUM_SHARED: "1"
		SODIUM_LIB_DIR: "/nix/store/rbc496f0h04ddix6b05ya4w5csms1a9v-libsodium-1.0.22-unstable-2026-07-31/lib"
		SODIUM_INCLUDE_DIR: "/nix/store/rbc496f0h04ddix6b05ya4w5csms1a9v-libsodium-1.0.22-unstable-2026-07-31/include"
		LD_LIBRARY_PATH: "/nix/store/rbc496f0h04ddix6b05ya4w5csms1a9v-libsodium-1.0.22-unstable-2026-07-31/lib"
		LIBCLANG_PATH: "/nix/store/yc2a9854a2y2c8kci88piblc847iq1l4-clang-21.1.8-lib/lib"
		CXXFLAGS: "-include cstdint"
		RUSTFLAGS: ""
		PUB_CACHE: "$HOME/.cache/pub"
	}

	shellHook: """
		echo "========================================================================"
		echo " 🦀 Welcome to the RustDesk Developer Environment (enve)                "
		echo "========================================================================"

		# 1. Initialize git submodules (libs/hbb_common) if not present
		if [ ! -f "libs/hbb_common/Cargo.toml" ]; then
			echo "📦 Initializing submodules (libs/hbb_common)..."
			git submodule update --init --recursive
		fi

		# 2. Download Sciter dynamic library for classic desktop GUI
		for dir in target/debug target/release; do
			if [ ! -f "$dir/libsciter-gtk.so" ]; then
				mkdir -p "$dir"
				echo "📥 Fetching libsciter-gtk.so for $dir..."
				curl -fsSL -o "$dir/libsciter-gtk.so" "https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.lnx/x64/libsciter-gtk.so" 2>/dev/null || true
			fi
		done

		# 3. Setup hermetic vcpkg codecs (libvpx, libyuv, opus, aom) if needed
		if [ ! -f "$VCPKG_ROOT/installed/x64-linux/lib/libopus.a" ] && [ ! -f "$VCPKG_ROOT/installed/x64-linux/lib/libvpx.a" ]; then
			echo "⚙️  Tip: If using vcpkg codecs, run:"
			echo "     git clone --branch 2023.04.15 --depth=1 https://github.com/microsoft/vcpkg $VCPKG_ROOT"
			echo "     $VCPKG_ROOT/bootstrap-vcpkg.sh -disableMetrics"
			echo "     $VCPKG_ROOT/vcpkg --disable-metrics install libvpx libyuv opus aom"
			echo "   Alternatively, build with: cargo build --features linux-pkg-config"
		fi

		# 4. Ensure LIBCLANG_PATH is resolved from hermetic Nix store if not already set
		if [ -z "$LIBCLANG_PATH" ]; then
			for clang_lib in /nix/store/*-clang-*-lib/lib; do
				if [ -f "$clang_lib/libclang.so" ]; then
					export LIBCLANG_PATH="$clang_lib"
					break
				fi
			done
		fi

		# 5. Alias flutter_rust_bridge_codegen to automatically use the hermetic Nix LLVM
		if [ -n "$LIBCLANG_PATH" ]; then
			alias flutter_rust_bridge_codegen="flutter_rust_bridge_codegen --llvm-path $(dirname $LIBCLANG_PATH)"
		fi


		# 5. Export C++ runtime and desktop GUI libraries for dynamic test runners
		for gcc_lib in /nix/store/*-gcc-*-lib/lib; do
			if [ -f "$gcc_lib/libstdc++.so.6" ]; then
				export LD_LIBRARY_PATH="$gcc_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
				break
			fi
		done

		for env_lib in /nix/store/*-environment-develop/lib; do
			if [ -d "$env_lib" ]; then
				export LD_LIBRARY_PATH="$env_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
				break
			fi
		done

		for x_lib in /nix/store/*-libxtst-*/lib /nix/store/*-libxkbcommon-*/lib; do
			if [ -d "$x_lib" ]; then
				export LD_LIBRARY_PATH="$x_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
			fi
		done

		# 6. Ensure project target directory is linked for Flutter CMake runner
		mkdir -p target/debug target/release
		for mode in debug release; do
			if [ -f "$CARGO_TARGET_DIR/$mode/liblibrustdesk.so" ] && [ ! -e "target/$mode/liblibrustdesk.so" ]; then
				ln -sf "$CARGO_TARGET_DIR/$mode/liblibrustdesk.so" "target/$mode/liblibrustdesk.so"
			fi
		done

		echo "✅ RustDesk environment ready!"
		echo "   - Sciter GUI:      cargo run"
		echo "   - Flutter GUI:     cd flutter && flutter build linux --debug"
		echo "   - Service Daemon:  cargo check --bin service --features linux-pkg-config"
		echo "   - Core Tests:      cargo test -p hbb_common"
		echo "   - Full Workspace:  xvfb-run -a cargo test --workspace --features linux-pkg-config --no-fail-fast"
		"""
}
