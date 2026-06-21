#!/usr/bin/env sh

set -e

init_common() {
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

    if [ -n "$PROJECT_DIR" ]; then
        PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    else
        PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    fi

    if [ -n "$OUT_DIR" ]; then
        OUT_DIR="$(cd "$OUT_DIR" && pwd)"
    else
        OUT_DIR="$PROJECT_DIR/.release-artifacts"
    fi

    BIN_NAME="${BIN_NAME:-macvision}"
}

get_targets() {
    echo "arm64:darwin:arm64"
    echo "x86_64:darwin:x64"
}

get_current_arch() {
    uname -m
}

do_build() {
    local arch="$1"
    local os="$2"
    local arch_name="$3"
    local bin_name="${BIN_NAME:-macvision}"
    local out_subdir="${os}-${arch_name}/bin"

    echo "Building for $os-$arch_name ($arch)..."

    cd "$PROJECT_DIR"

    rm -rf ".build/$arch-apple-macosx"
    # Deterministic build env (see macli-mneme/issues/2)
    SOURCE_DATE_EPOCH=1700000000 \
    ZERO_AR_DATE=1 \
    TZ=UTC \
    LC_ALL=C \
    swift build -c release --arch "$arch" \
        -Xswiftc -gnone

    local src=".build/$arch-apple-macosx/release/${bin_name}"
    local dst="$OUT_DIR/$out_subdir/${bin_name}"

    if [ ! -f "$src" ]; then
        echo "  Warning: $src not found, skipping"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    chmod +x "$dst"

    # Order matters: all binary modifications BEFORE codesign (signing last).
    # Otherwise signature gets invalidated by subsequent edits.

    # 1. Strip local symbols
    strip -x "$dst" 2>/dev/null || true

    # 2. Remove build-machine-specific RPATH (privacy + reproducibility)
    otool -l "$dst" | grep -A2 "LC_RPATH" | grep "/Library/Developer" | \
        sed -E 's/.*path (.*) \(offset.*/\1/' | sort -u | \
        while read -r rpath; do
            install_name_tool -delete_rpath "$rpath" "$dst" 2>/dev/null || true
        done

    # 3. Clear provenance xattr (macOS 14+ tracks file history)
    xattr -c "$dst" 2>/dev/null || true

    # 4. Re-sign with ad-hoc (Apple Silicon requires at least ad-hoc signature).
    #    Must be LAST so signature covers the final binary state.
    codesign -f -s - "$dst" 2>/dev/null || true

    local size=$(stat -f%z "$dst" 2>/dev/null || stat -c%s "$dst" 2>/dev/null || echo "unknown")
    echo "  -> $dst ($size bytes)"
}

write_build_info() {
    local info_file="$OUT_DIR/BUILD_INFO.txt"
    {
        echo "# macvision build info"
        echo "built_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "swift_version=$(swift --version 2>&1 | head -1)"
        echo "sdk_version=$(xcrun --show-sdk-version 2>/dev/null)"
        echo "sdk_path=$(xcrun --show-sdk-path 2>/dev/null)"
        echo "sw_vers=$(sw_vers -productVersion 2>/dev/null)"
        echo "xcode_select=$(xcode-select -p 2>/dev/null)"
        echo "source_date_epoch=1700000000"
    } > "$info_file"
    echo "  -> $info_file"
}

build_all_targets() {
    rm -rf "$OUT_DIR"
    mkdir -p "$OUT_DIR"

    while IFS=: read -r arch os arch_name; do
        do_build "$arch" "$os" "$arch_name" || true
    done <<EOF
$(get_targets)
EOF

    # Build universal binary (arm64 + x86_64 in single Mach-O)
    build_universal

    write_build_info

    echo ""
    echo "Done! Artifacts in: $OUT_DIR"
    echo ""
    ls -la "$OUT_DIR"/*/bin/ 2>/dev/null || true
    ls -la "$OUT_DIR"/*universal*/bin/ 2>/dev/null || true
}

build_universal() {
    local bin_name="${BIN_NAME:-macvision}"
    local arm64_bin="$OUT_DIR/darwin-arm64/bin/${bin_name}"
    local x64_bin="$OUT_DIR/darwin-x64/bin/${bin_name}"
    local uni_dir="$OUT_DIR/darwin-universal/bin"
    local uni_bin="$uni_dir/${bin_name}"

    if [ ! -f "$arm64_bin" ] || [ ! -f "$x64_bin" ]; then
        echo "  Skipping universal (need both arches)"
        return 0
    fi

    mkdir -p "$uni_dir"

    # lipo merges two thin binaries into one fat Mach-O
    lipo -create "$arm64_bin" "$x64_bin" -output "$uni_bin"
    chmod +x "$uni_bin"

    # Re-sign (signature from thin binaries doesn't survive lipo)
    codesign -f -s - "$uni_bin" 2>/dev/null || true

    local size=$(stat -f%z "$uni_bin" 2>/dev/null || stat -c%s "$uni_bin" 2>/dev/null || echo "unknown")
    echo "  -> $uni_bin ($size bytes, universal)"
}

package_target() {
    local arch_name="$1"
    local bin_name="${BIN_NAME:-macvision}"
    local src_dir="$OUT_DIR/darwin-${arch_name}/bin"
    local pkg_dir="$OUT_DIR/darwin-${arch_name}.pkg"
    local tarball="$OUT_DIR/macvision-darwin-${arch_name}.tar.xz"

    if [ ! -f "$src_dir/${bin_name}" ]; then
        echo "  Warning: $src_dir/${bin_name} not found, skipping package"
        return 0
    fi

    rm -rf "$pkg_dir"
    mkdir -p "$pkg_dir/bin"
    cp "$src_dir/${bin_name}" "$pkg_dir/bin/${bin_name}"
    chmod +x "$pkg_dir/bin/${bin_name}"

    # Normalize mtimes (macOS bsdtar doesn't support --mtime=@N, so pre-touch)
    local mdate="202311140000.00"
    find "$pkg_dir" -exec touch -m -t "$mdate" {} +

    # Deterministic tarball (bsdtar on macOS). Internal layout: bin/macvision
    (cd "$pkg_dir" && \
        tar -cJf "$OUT_DIR/macvision-darwin-${arch_name}.tar.xz" \
            --format ustar \
            bin)

    rm -rf "$pkg_dir"

    local size=$(stat -f%z "$tarball" 2>/dev/null || stat -c%s "$tarball" 2>/dev/null || echo "unknown")
    echo "  -> $tarball ($size bytes)"
}

package_all_targets() {
    while IFS=: read -r arch os arch_name; do
        package_target "$arch_name" || true
    done <<EOF
$(get_targets)
EOF

    # Universal binary package
    package_target "universal"

    # SHA256SUMS
    (cd "$OUT_DIR" && shasum -a 256 macvision-*.tar.xz BUILD_INFO.txt > SHA256SUMS 2>/dev/null || true)
    echo "  -> $OUT_DIR/SHA256SUMS"
}

verify_reproducibility() {
    local target="${1:-darwin-arm64}"
    local arch=""
    case "$target" in
        darwin-arm64|arm64) arch="arm64" ;;
        darwin-x64|x86_64|x64) arch="x86_64" ;;
        *) echo "Unknown target: $target"; exit 1 ;;
    esac

    echo "Verifying reproducibility for $target..."

    do_build "$arch" "darwin" "${target#darwin-}"
    shasum -a 256 "$OUT_DIR/$target/bin/macvision" > /tmp/macvision-verify-h1.txt

    do_build "$arch" "darwin" "${target#darwin-}"
    shasum -a 256 "$OUT_DIR/$target/bin/macvision" > /tmp/macvision-verify-h2.txt

    if diff /tmp/macvision-verify-h1.txt /tmp/macvision-verify-h2.txt >/dev/null; then
        echo "✓ PASS: same sha256 across two consecutive builds"
        cat /tmp/macvision-verify-h1.txt
    else
        echo "✗ FAIL: sha256 differs"
        diff /tmp/macvision-verify-h1.txt /tmp/macvision-verify-h2.txt
        exit 1
    fi

    # RPATH leak check
    if otool -l "$OUT_DIR/$target/bin/macvision" | grep -A2 "LC_RPATH" | grep -q "/Library/Developer"; then
        echo "✗ FAIL: build-machine RPATH leaked"
        otool -l "$OUT_DIR/$target/bin/macvision" | grep -A2 "LC_RPATH" | grep "/Library/Developer"
        exit 1
    fi
    echo "✓ PASS: no build-machine RPATH"

    # User path leak check
    if strings "$OUT_DIR/$target/bin/macvision" | grep -qE "^/Users/|^/home/"; then
        echo "✗ FAIL: user path leaked in binary"
        exit 1
    fi
    echo "✓ PASS: no user path in binary"
}

show_usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Environment variables:"
    echo "  PROJECT_DIR       Project directory (default: script parent dir)"
    echo "  OUT_DIR           Output directory (default: PROJECT_DIR/.release-artifacts)"
    echo "  BIN_NAME          Binary name (default: macvision)"
    echo ""
    echo "Commands:"
    echo "  all               Build all targets (arm64 + x64)"
    echo "  <target>          Build specific target (see below)"
    echo "  package           Create tar.xz packages from .release-artifacts/"
    echo "  release           Build all + package (full release flow)"
    echo "  verify <target>   Build twice + compare sha256 + check no leaks"
    echo ""
    echo "Targets:"
    echo "  darwin-arm64      arm64 (Apple Silicon)"
    echo "  darwin-x64        x86_64 (Intel Mac)"
    echo "  arm64             Alias for darwin-arm64"
    echo "  x86_64            Alias for darwin-x64"
    echo ""
    echo "Examples:"
    echo "  $0 all                    # Build all targets"
    echo "  $0 darwin-arm64           # Build for Apple Silicon only"
    echo "  $0 release                # Full release: build + package + sha256sums"
    echo "  $0 verify darwin-arm64    # Verify reproducibility + no privacy leaks"
}
