set -euo pipefail

# ç”¨æ³•: ./modify_duration.sh NEW_DURATION [ROOT_DIR]
# ä¾‹å­: ./modify_duration.sh 08:00:00 .

NEW_DURATION="${1:-}"
ROOT_DIR="${2:-.}"

if [[ -z "${NEW_DURATION}" ]]; then
  echo "ç”¨æ³•: $0 NEW_DURATION [ROOT_DIR]" >&2
  echo "ä¾‹å­: $0 08:00:00 ." >&2
  exit 1
fi

# æ ¡é©—æ™‚é–“æ ¼å¼ HH:MM:SS
if [[ ! "${NEW_DURATION}" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
  echo "âŒ NEW_DURATION å¿…é ˆæ˜¯ HH:MM:SS æ ¼å¼ï¼Œä¾‹å¦‚ 08:00:00" >&2
  exit 1
fi

NEW="duration = \"${NEW_DURATION}\""

echo "ðŸ”Ž åœ¨ ${ROOT_DIR} è£¡æŸ¥æ‰¾ä¸¦æ›¿æ›æ‰€æœ‰ duration = \"??:??:??\""
echo "   â†’ ${NEW}"
echo

# éžè¿´éæ­·æª”æ¡ˆï¼Œç›´æŽ¥æ›¿æ›
grep -RIl --exclude-dir='.git' -- 'duration = "' "${ROOT_DIR}" | while read -r f; do
  echo "âœï¸  ä¿®æ”¹ $f"
  # åŒ¹é… duration = "HH:MM:SS" ä¸¦æ•´è¡Œæ›¿æ›æˆæ–°å€¼
  sed -i -E "s/duration = \"[0-9]{2}:[0-9]{2}:[0-9]{2}\"/${NEW}/g" "$f"
done

echo
echo "âœ… æ›¿æ›å®Œæˆ"