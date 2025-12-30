#!/bin/bash
#
# update-digests.sh - Update base image digests in VERSION.json
#
# This script queries the container registry for the latest digests of builder
# and base images specified in VERSION.json, and updates the digests if they
# have changed. When any digest changes, the build_date is updated, but the
# semantic version is preserved (e.g., "4.0.16.2944").
#
# Usage:
#   ./update-digests.sh
#
# Requirements:
#   - jq: JSON processor
#   - skopeo: Container image inspection tool
#   - VERSION.json: Must exist in the same directory
#
# Version Format:
#   The version field uses semantic versioning (e.g., "4.0.16.2944") and is
#   preserved unchanged. Only digests and build_date are updated when base
#   images change.
#
# Exit Codes:
#   0: Success
#   1: Error (missing tools, registry failure, etc.)

set -euo pipefail

json=$(cat VERSION.json)
changed=false

# Get the number of targets
target_count=$(jq '.targets | length' <<< "${json}")

# Process each target
for i in $(seq 0 $((target_count - 1))); do
    # Extract builder info
    builder_image=$(jq -re ".targets[${i}].builder.image" <<< "${json}")
    builder_tag=$(jq -re ".targets[${i}].builder.tag" <<< "${json}")
    arch=$(jq -re ".targets[${i}].arch" <<< "${json}")
    arch_short=$(echo "$arch" | sed 's/^linux-//')
    
    # Get current builder digest
    current_builder_digest=$(jq -re ".targets[${i}].builder.digest" <<< "${json}")
    
    # Get builder digest (multi-arch image)
    builder_ref="${builder_image}:${builder_tag}"
    builder_manifest=$(skopeo inspect --raw "docker://${builder_ref}") || exit 1
    builder_digest=$(jq -re ".manifests[] | select(.platform.architecture == \"${arch_short}\" and .platform.os == \"linux\").digest" <<< "${builder_manifest}")
    
    # Update builder digest if changed
    if [ "$current_builder_digest" != "$builder_digest" ]; then
        json=$(jq --arg idx "$i" --arg digest "$builder_digest" \
            '.targets[$idx | tonumber].builder.digest = $digest' <<< "${json}")
        echo "Updated builder ${builder_ref} (${arch_short}): ${current_builder_digest} -> ${builder_digest}"
        changed=true
    fi
    
    # Extract base info
    base_image=$(jq -re ".targets[${i}].base.image" <<< "${json}")
    base_tag=$(jq -re ".targets[${i}].base.tag" <<< "${json}")
    
    # Get current base digest
    current_base_digest=$(jq -re ".targets[${i}].base.digest" <<< "${json}")
    
    # Get base digest (platform-specific tag)
    base_ref="${base_image}:${base_tag}"
    base_digest=$(skopeo inspect --format "{{.Digest}}" "docker://${base_ref}") || exit 1
    
    # Update base digest if changed
    if [ "$current_base_digest" != "$base_digest" ]; then
        json=$(jq --arg idx "$i" --arg digest "$base_digest" \
            '.targets[$idx | tonumber].base.digest = $digest' <<< "${json}")
        echo "Updated base ${base_ref}: ${current_base_digest} -> ${base_digest}"
        changed=true
    fi
done

# Update build_date if any digest changed
if [ "$changed" = true ]; then
    json=$(jq --arg build_date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
              '.build_date = $build_date' <<< "${json}")
    echo "Updated build_date"
fi

# Write updated VERSION.json
jq --sort-keys . <<< "${json}" | tee VERSION.json

