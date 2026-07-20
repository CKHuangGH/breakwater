#!/usr/bin/env bash

set -euo pipefail

NEW_DURATION="${1:-}"
ROOT_DIR="${2:-.}"

if [[ -z "${NEW_DURATION}" ]]; then
  echo "Usage: $0 NEW_DURATION [ROOT_DIR]" >&2
  echo "Example: $0 08:00:00 ." >&2
  exit 1
fi

# Validate that the duration uses the HH:MM:SS format
if [[ ! "${NEW_DURATION}" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
  echo "Error: NEW_DURATION must use the HH:MM:SS format, for example 08:00:00" >&2
  exit 1
fi

NEW="duration = \"${NEW_DURATION}\""

echo "Searching in ${ROOT_DIR} and replacing all duration = \"HH:MM:SS\" values"
echo "New value: ${NEW}"
echo

grep -RIl \
  --exclude-dir=".git" \
  --include="*.py" \
  -- 'duration = "' "${ROOT_DIR}" |
while IFS= read -r file; do
  echo "Updating: ${file}"

  sed -i -E \
    "s/duration = \"[0-9]{2}:[0-9]{2}:[0-9]{2}\"/${NEW}/g" \
    "${file}"
done

echo
echo "Replacement completed successfully"