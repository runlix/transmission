#!/bin/bash
#
# update-versions.sh - Update Transmission version and package URLs in VERSION.json
#
# This script queries the Transmission GitHub releases API for the latest release
# and updates the version, sbranch, and package_url fields in VERSION.json.
# When the version changes, build_date is also updated.
#
# Usage:
#   ./update-versions.sh
#
# Requirements:
#   - jq: JSON processor
#   - curl: HTTP client
#   - VERSION.json: Must exist in the same directory
#
# Exit Codes:
#   0: Success
#   1: Error (missing tools, API failure, etc.)

set -euo pipefail

# Fetch Transmission release information from GitHub releases API
release_json=$(curl -fsSL "https://api.github.com/repos/transmission/transmission/releases/latest") || exit 1

# Extract version and tag
tag_name=$(jq -re '.tag_name' <<< "${release_json}")
version="${tag_name#v}"  # Remove 'v' prefix if present
sbranch="main"  # Transmission uses 'main' branch for stable releases

# Find source tarball asset from release assets
# Pattern: transmission-*.tar.xz or *.tar.xz
package_url=$(jq -re '.assets[] | select(.name | endswith(".tar.xz")) | .browser_download_url' <<< "${release_json}" | head -n 1)

# Verify source tarball was found
if [ -z "${package_url}" ]; then
    echo "Error: Could not find source tarball (.tar.xz) in release assets" >&2
    exit 1
fi

# Read current VERSION.json
json=$(cat VERSION.json)
current_version=$(jq -r '.version' <<< "${json}")
changed=false

# Check if version changed
if [ "$current_version" != "$version" ]; then
    changed=true
    echo "Version changed: ${current_version} -> ${version}"
fi

# Update root-level version and sbranch
json=$(jq --arg version "$version" \
          --arg sbranch "$sbranch" \
          '.version = $version | .sbranch = $sbranch' <<< "${json}")

# Get the number of targets
target_count=$(jq '.targets | length' <<< "${json}")

# Update package_url for each target (same URL for all architectures - source build)
for i in $(seq 0 $((target_count - 1))); do
    # Update package_url for this target
    json=$(jq --arg idx "$i" --arg url "$package_url" \
        '.targets[$idx | tonumber].package_url = $url' <<< "${json}")
    
    arch=$(jq -re ".targets[${i}].arch" <<< "${json}")
    echo "Updated package_url for ${arch} target"
done

# Update build_date if version changed
if [ "$changed" = true ]; then
    json=$(jq --arg build_date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
              '.build_date = $build_date' <<< "${json}")
    echo "Updated build_date"
fi

# Write updated VERSION.json
jq --sort-keys . <<< "${json}" | tee VERSION.json

