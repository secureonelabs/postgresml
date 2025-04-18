#!/bin/bash
set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
package_version="$1"
target_ubuntu_version="$2"

if [[ -z "$package_version" ]]; then
  echo "postgresml package build and release script"
  echo "usage: $0 <package version, e.g. 2.10.0> [ubuntu version, e.g. 22.04]"
  exit 1
fi

# Active LTS Ubuntu versions and their codenames
declare -A ubuntu_codenames=(
  ["20.04"]="focal"
  ["22.04"]="jammy"
  ["24.04"]="noble"
)

# Install deb-s3 if not present
if ! which deb-s3; then
  curl -sLO https://github.com/deb-s3/deb-s3/releases/download/0.11.4/deb-s3-0.11.4.gem
  sudo gem install deb-s3-0.11.4.gem
  deb-s3
fi

function package_name() {
  local pg_version=$1
  local ubuntu_version=$2
  echo "postgresml-${pg_version}-${package_version}-ubuntu${ubuntu_version}-all.deb"
}

build_package() {
  local ubuntu_version=$1
  local codename=$2
  
  echo "Building packages for Ubuntu ${ubuntu_version} (${codename})"

  for pg in {11..17}; do
    echo "Building PostgreSQL ${pg} package..."
    bash ${SCRIPT_DIR}/build.sh ${package_version} ${pg} ${ubuntu_version}

    if [[ ! -f $(package_name ${pg} ${ubuntu_version}) ]]; then
      echo "File $(package_name ${pg} ${ubuntu_version}) doesn't exist"
      exit 1
    fi

    deb-s3 upload \
      --visibility=public \
      --bucket apt.postgresml.org \
      $(package_name ${pg} ${ubuntu_version}) \
      --codename ${codename}

    rm $(package_name ${pg} ${ubuntu_version})
  done
}

# If a specific Ubuntu version is provided, only build for that version
if [[ ! -z "$target_ubuntu_version" ]]; then
  if [[ -z "${ubuntu_codenames[$target_ubuntu_version]}" ]]; then
    echo "Error: Ubuntu version $target_ubuntu_version is not supported."
    echo "Supported versions: ${!ubuntu_codenames[@]}"
    exit 1
  fi
  
  build_package "$target_ubuntu_version" "${ubuntu_codenames[$target_ubuntu_version]}"
else
  # If no version specified, loop through all supported Ubuntu versions
  for ubuntu_version in "${!ubuntu_codenames[@]}"; do
    build_package "$ubuntu_version" "${ubuntu_codenames[$ubuntu_version]}"
  done
fi