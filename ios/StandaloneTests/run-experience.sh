#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
swiftc -D STANDALONE_POLICY_TESTS "$root/ios/GlucoScope/Service/StandaloneExperiencePolicy.swift" "$root/ios/StandaloneTests/ExperiencePolicySmoke.swift" -o "$temporary/experience"
"$temporary/experience"
