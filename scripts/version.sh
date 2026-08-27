#!/usr/bin/env bash
# Derive the current version from git tags.

current_version() {
    local tag
    tag="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname | head -n 1)"
    if [ -z "$tag" ]; then
        printf '0.0.0'
        return 0
    fi
    printf '%s' "${tag#v}"
}
