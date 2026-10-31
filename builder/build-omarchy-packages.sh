#!/bin/bash
# Build Omarchy packages from mounted source (/omarchy-source + /omarchy-pkgs)
# and place the resulting .pkg.tar.zst files in the offline mirror.

set -e

offline_mirror_dir="$1"
if [[ -z $offline_mirror_dir ]]; then
  echo "Usage: build-omarchy-packages.sh <offline-mirror-dir>" >&2
  exit 1
fi

if [[ ! -d /omarchy-source ]]; then
  echo "ERROR: /omarchy-source not mounted (pass --local-source or set OMARCHY_SOURCE_PATH)" >&2
  exit 1
fi
if [[ ! -d /omarchy-pkgs ]]; then
  echo "ERROR: /omarchy-pkgs not mounted (set OMARCHY_PKGS_PATH or place ../omarchy-pkgs)" >&2
  exit 1
fi

work_dir=/var/cache/omarchy-pkg-build
rm -rf "$work_dir"
mkdir -p "$work_dir"

if ! id builder &>/dev/null; then
  useradd -m -s /bin/bash builder
fi
echo 'builder ALL=(ALL) NOPASSWD: /usr/bin/pacman' > /etc/sudoers.d/99-omarchy-pkg-builder
chmod 440 /etc/sudoers.d/99-omarchy-pkg-builder
chown builder:builder "$work_dir"

pacman -Sy --noconfirm

: "${OMARCHY_RUNTIME_PACKAGE:=omarchy-dev}"
: "${OMARCHY_SETTINGS_PACKAGE:=omarchy-settings-dev}"
: "${OMARCHY_NVIM_PACKAGE:=omarchy-nvim}"

# Collect packages to build: the three core packages plus any package from the
# source package lists that has a corresponding pkgbuild in /omarchy-pkgs/pkgbuilds/
declare -A packages_to_build=()
packages_to_build["$OMARCHY_SETTINGS_PACKAGE"]=1
packages_to_build["$OMARCHY_RUNTIME_PACKAGE"]=1
packages_to_build["$OMARCHY_NVIM_PACKAGE"]=1

# Read package lists from the source checkout (supports both unbloarchy- and omarchy- prefixed lists)
for pkg_list in /omarchy-source/install/unbloarchy-base.packages /omarchy-source/install/unbloarchy-other.packages /omarchy-source/install/omarchy-base.packages /omarchy-source/install/omarchy-other.packages; do
  [[ -f $pkg_list ]] || continue
  while IFS= read -r pkg; do
    [[ -z $pkg ]] && continue
    [[ $pkg == \#* ]] && continue
    pkg=$(echo "$pkg" | xargs)  # trim whitespace
    [[ -z $pkg ]] && continue
    if [[ -d "/omarchy-pkgs/pkgbuilds/$pkg" ]]; then
      packages_to_build["$pkg"]=1
    fi
  done < "$pkg_list"
done

# Skip localsend - its PKGBUILD has a bug (double path in cp command) that causes build failure
# This is a known issue in the omarchy-pkgs repo that we can't fix here
unset packages_to_build["localsend"]

# Convert associative array to regular array
packages=()
for pkg in "${!packages_to_build[@]}"; do
  packages+=("$pkg")
done

# Filter packages to only those supporting x86_64 (or 'any')
host_arch=$(uname -m)
filtered_packages=()
for pkg in "${packages[@]}"; do
  pkgbuild="/omarchy-pkgs/pkgbuilds/$pkg/PKGBUILD"
  if [[ ! -f $pkgbuild ]]; then
    echo "WARNING: PKGBUILD not found for $pkg, skipping" >&2
    continue
  fi
  # Extract arch=() from PKGBUILD
  if grep -qE "^arch=\(.*\)" "$pkgbuild"; then
    arch_line=$(grep -E "^arch=\(.*\)" "$pkgbuild" | head -1)
    # Check if arch includes x86_64, any, or the host arch
    if [[ $arch_line == *'x86_64'* ]] || [[ $arch_line == *'any'* ]] || [[ $arch_line == *"$host_arch"* ]]; then
      filtered_packages+=("$pkg")
    else
      echo "Skipping $pkg: not available for $host_arch (arch=$arch_line)" >&2
    fi
  else
    # No arch specified, assume it's compatible
    filtered_packages+=("$pkg")
  fi
done
packages=("${filtered_packages[@]}")

# Local-source packages must replace every cached build of the same package,
# even when the checkout's generated pkgver sorts below a published build.
# Otherwise the later generic cache pruning can silently keep edge instead.
for pkg in "${packages[@]}"; do
  rm -f "$offline_mirror_dir/$pkg-"*.pkg.tar.*
done

# Install build dependencies (makedepends + depends) for all packages upfront
# Since we use --nodeps, we need to manually install all build-time deps
echo "Installing build dependencies..."

host_arch=$(uname -m)

# Helper function to extract array values from PKGBUILD (handles multi-line arrays)
extract_pkgbuild_array() {
  local pkgbuild="$1"
  local array_name="$2"
  local in_array=0
  local content=""

  while IFS= read -r line; do
    # Start of array
    if [[ $line =~ ^${array_name}=\( ]]; then
      in_array=1
      # Remove the array_name=( part
      line="${line#${array_name}=}"
    fi

    if [[ $in_array -eq 1 ]]; then
      content+=" $line"
      # Check for closing parenthesis
      if [[ $line == *\)* ]]; then
        break
      fi
    fi
  done < "$pkgbuild"

  # Clean up: remove parentheses, quotes, and extra whitespace
  content="${content//\(/ }"
  content="${content//\)/ }"
  content="${content//\'/ }"
  content="${content//\"/ }"
  echo "$content"
}

for pkg in "${packages[@]}"; do
  pkgbuild="/omarchy-pkgs/pkgbuilds/$pkg/PKGBUILD"
  if [[ -f $pkgbuild ]]; then
    # Extract standard arrays
    makedeps=$(extract_pkgbuild_array "$pkgbuild" "makedepends")
    deps=$(extract_pkgbuild_array "$pkgbuild" "depends")
    checkdeps=$(extract_pkgbuild_array "$pkgbuild" "checkdepends")
    
    # Extract architecture-specific arrays
    arch_makedeps=$(extract_pkgbuild_array "$pkgbuild" "makedepends_${host_arch}")
    arch_deps=$(extract_pkgbuild_array "$pkgbuild" "depends_${host_arch}")
    arch_checkdeps=$(extract_pkgbuild_array "$pkgbuild" "checkdepends_${host_arch}")
    
    # Combine and install - strip version constraints (>=, <=, =, etc.)
    all_deps="$makedeps $deps $checkdeps $arch_makedeps $arch_deps $arch_checkdeps"
    if [[ -n $all_deps ]]; then
      for dep in $all_deps; do
        # Strip version constraints like >=, <=, =, >, <
        clean_dep=$(echo "$dep" | sed -E 's/[<>=].*$//')
        pacman -S --noconfirm --needed "$clean_dep" 2>/dev/null || true
      done
    fi
  fi
done

for pkg in "${packages[@]}"; do
  echo "----------------------------------------"
  echo "Building $pkg"
  echo "----------------------------------------"
  pkg_work="$work_dir/$pkg"
  if [[ ! -d "/omarchy-pkgs/pkgbuilds/$pkg" ]]; then
    echo "ERROR: package source not found: /omarchy-pkgs/pkgbuilds/$pkg" >&2
    exit 1
  fi
  cp -a "/omarchy-pkgs/pkgbuilds/$pkg" "$pkg_work"
  chown -R builder:builder "$pkg_work"

  su builder -c "
    cd '$pkg_work' &&
    export CARGO_TARGET_DIR='$pkg_work/target' &&
    export TMPDIR='$pkg_work/tmp' &&
    mkdir -p '\$CARGO_TARGET_DIR' '\$TMPDIR' &&
    PKGDEST='$work_dir' \
    OMARCHY_SRC=/omarchy-source \
    makepkg --noconfirm --skippgpcheck --skipchecksums --nodeps --nocheck -f
  "
done

mkdir -p "$offline_mirror_dir"
for package_file in "$work_dir"/*.pkg.tar.zst; do
  destination="$offline_mirror_dir/$(basename "$package_file")"

  # A cached signature belongs to the previously downloaded or locally built
  # package. Keeping it beside a newly built package makes pacman reject the
  # otherwise valid local-source build.
  rm -f "$destination" "$destination.sig"
  mv "$package_file" "$destination"
done

echo
echo "Built Omarchy packages, placed in $offline_mirror_dir:"
ls "$offline_mirror_dir"/*.pkg.tar.zst | sed 's|^|  |'