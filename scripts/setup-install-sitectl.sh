#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
as_root=()
if [ "$(id -u)" -ne 0 ]; then
  as_root=(sudo)
fi

"${as_root[@]}" apt-get update
"${as_root[@]}" apt-get install --yes --no-install-recommends \
  ca-certificates \
  curl \
  gnupg

key_source="${RUNNER_TEMP}/sitectl-archive-keyring.asc"
keyring="${RUNNER_TEMP}/sitectl-archive-keyring.gpg"
curl --proto '=https' --tlsv1.2 --fail --show-error --silent --location \
  https://packages.libops.io/sitectl/sitectl-archive-keyring.asc \
  --output "$key_source"
gpg --batch --yes --dearmor --output "$keyring" "$key_source"
"${as_root[@]}" install --mode 0644 "$keyring" \
  /usr/share/keyrings/sitectl-archive-keyring.gpg
printf '%s\n' \
  'deb [signed-by=/usr/share/keyrings/sitectl-archive-keyring.gpg] https://packages.libops.io/sitectl ./' |
  "${as_root[@]}" tee /etc/apt/sources.list.d/sitectl.list >/dev/null

"${as_root[@]}" apt-get update
"${as_root[@]}" apt-get install --yes --no-install-recommends sitectl-isle

for package in sitectl sitectl-drupal sitectl-isle; do
  version=$(dpkg-query --show --showformat='${Version}' "$package")
  if ! dpkg --compare-versions "$version" ge 1.0.0; then
    echo "::error::${package} ${version} is older than the required 1.0.0 release line."
    exit 1
  fi
done
sitectl --version
sitectl-drupal --version
sitectl-isle --version
sitectl create list
