#!/bin/sh
# Installs Ultraman for this user: the app and the `ultraman` command. No sudo needed.
#   curl -fsSL https://ultraman-app.github.io/install.sh | sh
# Only the command, for CI:
#   curl -fsSL https://ultraman-app.github.io/install.sh | sh -s -- --cli
# A given version: ... | sh -s -- --version 0.1.0   (or ULTRAMAN_VERSION=0.1.0)
set -eu

releases=https://github.com/ultraman-app/ultraman-app.github.io/releases
cli_only=${ULTRAMAN_CLI_ONLY:-}
version=${ULTRAMAN_VERSION:-}

say() { printf '%s\n' "$*"; }
fail() { printf 'ultraman: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case $1 in
    --cli) cli_only=1 ;;
    --version) [ $# -gt 1 ] || fail "--version needs a version, like 0.1.0"; shift; version=$1 ;;
    *) fail "unknown option: $1 (use --cli or --version X)" ;;
  esac
  shift
done

os=${ULTRAMAN_OS:-$(uname -s)}
arch=${ULTRAMAN_ARCH:-$(uname -m)}
case $os in
  Darwin | darwin | macos) os=macos ;;
  Linux | linux) os=linux ;;
  *) fail "$os is not supported yet by install.sh (macOS and Linux; on Windows use install.ps1)" ;;
esac
case $arch in
  x86_64 | amd64 | x64) arch=x64 ;;
  arm64 | aarch64) arch=arm64 ;;
esac
# A terminal running under Rosetta says x86_64 on an Apple Silicon Mac: the native build is the right one there.
if [ -z "${ULTRAMAN_ARCH:-}" ] && [ "$os-$arch" = macos-x64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" = 1 ]; then
  arch=arm64
fi
case $os-$arch in
  macos-x64 | macos-arm64 | linux-x64) ;;
  *) fail "$os on $arch is not supported yet" ;;
esac

if [ -n "${ULTRAMAN_BASE_URL:-}" ]; then base=$ULTRAMAN_BASE_URL
elif [ -n "$version" ]; then base=$releases/download/v${version#v}
else base=$releases/latest/download
fi
root=${ULTRAMAN_INSTALL_ROOT:-$HOME}
share=$root/.local/share/ultraman
cli_dir=$share/cli
bin_dir=$root/.local/bin
cli_asset=ultraman-cli-$os-$arch.tar.gz
if [ $os = macos ]; then app_asset=Ultraman-macos-$arch.dmg; else app_asset=Ultraman-linux-x64.AppImage; fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ultraman.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

fetch() { # url file [what to say if it can't]
  if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 2 -o "$2" "$1" || fail "${3:-couldn't download $1}"
  elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1" || fail "${3:-couldn't download $1}"
  else fail "curl or wget is needed"
  fi
}
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f 1
  else shasum -a 256 "$1" | cut -d ' ' -f 1
  fi
}
# Downloads an asset and checks it against SHA256SUMS; prints its path.
checked() { # name
  fetch "$base/$1" "$tmp/$1"
  want=$(awk -v n="$1" '$2 == n || $2 == "*" n { print $1 }' "$tmp/SHA256SUMS")
  [ -n "$want" ] || fail "$1 isn't in SHA256SUMS"
  [ "$(sha256 "$tmp/$1")" = "$want" ] || fail "$1: the checksum doesn't match; nothing was changed"
  printf '%s\n' "$tmp/$1"
}

# Everything is downloaded and checked before anything is touched: a failure leaves the previous install as it was.
fetch "$base/SHA256SUMS" "$tmp/SHA256SUMS"

# The release's signature: with a release key (scripts/release-key.sh writes it between the KEY lines below; a test or
# a fork can pass ULTRAMAN_RELEASE_KEY), SHA256SUMS must come signed by its private key. Someone who replaces a release
# and its checksums without that key can't get it installed.
release_key=${ULTRAMAN_RELEASE_KEY:-}
[ -n "$release_key" ] || release_key=$(cat <<'KEY'
-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEApgC1Yv14KqDbjGS7St81
bq2NQhxJpGqJOXOfjKDmeQRfUWqbHo3y+HDF5rtIrtT9WX7IA+j4IYPUsj77mHyE
NBXFHjRZDgeqIyFvnRrhFL6XDPdkZGLahWhk20Oz5NWmacWFoO0tKb0t5Eu/wuin
cBpPsdoFjGM1f23/TIH3BUVQe9hyPtzXM+lGCpUEfACHNW8NWHru6K5REQ6KnFdJ
dfq6zfEaaplbS3Xq8HGzZhehdRIM7AeWwT6LwGUThjzM0jYpt/Cc4KyKye10upGx
jtc5qKs9HXjO5PyMKfVHdPGJKD7WURAXU8nUUWKllmr3osInRSVyQOWts+FfXlKY
KGrGFmd09A+Zxj0FN1v9ksBITYlhUvAr0yWyVYDOyKG4eWhIQ3eR9HQsrjIOEnRK
KDX6LG2Ujd8uJCIssL1PJ/NKgR+ClbOk4jkVu1ymL6yRk/3ECMAB/qcKFS0LY7Io
b1wV8RJcrW18DnEU/eRnXIUwZQKJOWrIpQdTl7Cvv6mxAgMBAAE=
-----END PUBLIC KEY-----
KEY
)
if [ -n "$release_key" ]; then
  command -v openssl >/dev/null 2>&1 || fail "openssl is needed to check the release's signature"
  fetch "$base/SHA256SUMS.sig" "$tmp/SHA256SUMS.sig" "the release has no signature (SHA256SUMS.sig); nothing was changed"
  printf '%s\n' "$release_key" > "$tmp/release-key.pem"
  openssl dgst -sha256 -verify "$tmp/release-key.pem" -signature "$tmp/SHA256SUMS.sig" "$tmp/SHA256SUMS" >/dev/null 2>&1 ||
    fail "SHA256SUMS doesn't carry a valid signature from Ultraman's release key; nothing was changed"
fi
cli_tgz=$(checked "$cli_asset")
app_file=
[ -n "$cli_only" ] || app_file=$(checked "$app_asset")

say "Installing Ultraman..."
# The CLI: unpacked next to the old one, then swapped.
mkdir -p "$share" "$bin_dir"
rm -rf "$cli_dir.new" "$cli_dir.old"
mkdir "$cli_dir.new"
tar -xzf "$cli_tgz" -C "$cli_dir.new" || fail "couldn't unpack $cli_asset"
[ ! -e "$cli_dir" ] || mv "$cli_dir" "$cli_dir.old"
mv "$cli_dir.new" "$cli_dir"
rm -rf "$cli_dir.old"
cat > "$bin_dir/ultraman" <<EOF
#!/bin/sh
exec "$cli_dir/ultraman" "\$@"
EOF
chmod 755 "$bin_dir/ultraman"

app_where=
if [ -n "$app_file" ] && [ $os = macos ]; then
  mnt=$tmp/mnt
  mkdir "$mnt"
  hdiutil attach -nobrowse -quiet -mountpoint "$mnt" "$app_file" || fail "couldn't open $app_asset"
  mkdir -p "$root/Applications"
  rm -rf "$root/Applications/Ultraman.app"
  ditto "$mnt/Ultraman.app" "$root/Applications/Ultraman.app"
  hdiutil detach -quiet "$mnt" || true
  app_where="$root/Applications/Ultraman.app"
elif [ -n "$app_file" ]; then
  cp "$app_file" "$share/Ultraman.AppImage"
  chmod 755 "$share/Ultraman.AppImage"
  # The icon the AppImage carries, if it lets us take it out; without it the menu entry just has no icon.
  icon=
  if (cd "$tmp" && "$share/Ultraman.AppImage" --appimage-extract .DirIcon >/dev/null 2>&1) && [ -e "$tmp/squashfs-root/.DirIcon" ]; then
    cp -L "$tmp/squashfs-root/.DirIcon" "$share/icon.png" && icon=$share/icon.png
  fi
  mkdir -p "$root/.local/share/applications"
  cat > "$root/.local/share/applications/ultraman.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Ultraman
Comment=Visible API pipelines
Exec="$share/Ultraman.AppImage"
Icon=$icon
Categories=Development;
EOF
  app_where="$share/Ultraman.AppImage (and in your applications menu)"
fi

installed=$("$bin_dir/ultraman" --version) || fail "the installed command doesn't run"
say "Ultraman ${installed#ultraman } installed."
[ -z "$app_where" ] || say "  app:     $app_where"
say "  command: $bin_dir/ultraman"

if [ -n "${GITHUB_PATH:-}" ]; then
  printf '%s\n' "$cli_dir" >> "$GITHUB_PATH"
else
  case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) say "" "$bin_dir isn't on your PATH. Add this line to your ~/.zshrc or ~/.bashrc:" "  export PATH=\"$bin_dir:\$PATH\"" ;;
  esac
fi
if [ $os = linux ] && [ -n "$app_file" ] && ! command -v fusermount >/dev/null 2>&1 && ! command -v fusermount3 >/dev/null 2>&1; then
  say "" "The app is an AppImage and needs FUSE: if it doesn't open, install libfuse2 (sudo apt install libfuse2)."
fi
