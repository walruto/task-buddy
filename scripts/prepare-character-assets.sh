#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
STATE_SHEET="$ROOT/art/reference/animation-states-sheet.png"
HAPPY_SHEET="$ROOT/art/reference/animation-happy-sheet.png"
IDLE_WAVE_SHEET="$ROOT/art/reference/animation-idle-wave-sheet.png"
THINKING_ALERT_SHEET="$ROOT/art/reference/animation-thinking-alert-sheet.png"
ERROR_HAPPY_SHEET="$ROOT/art/reference/animation-error-happy-sheet.png"
FOCUS_SHEET="$ROOT/art/reference/animation-focus-sheet.png"
DANCE_SHEET="$ROOT/art/reference/animation-dance-sheet.png"
OUTPUT="$ROOT/Sources/TaskBuddyApp/Resources/Character"
MOBILE_OUTPUT="$ROOT/mobile"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

command -v magick >/dev/null || { echo "ImageMagick is required (brew install imagemagick)." >&2; exit 1; }
mkdir -p "$OUTPUT" "$MOBILE_OUTPUT"

extract() {
  local source="$1" crop="$2" output="$3"
  local width="${crop%%x*}"
  local remainder="${crop#*x}"
  local height="${remainder%%+*}"
  local max_x=$((width - 1)) max_y=$((height - 1))
  magick "$source" \
    -crop "$crop" +repage \
    -alpha on -fuzz 16% -fill none \
    -draw "alpha 0,0 floodfill alpha $max_x,0 floodfill alpha 0,$max_y floodfill alpha $max_x,$max_y floodfill" \
    -trim +repage \
    -filter point -resize '220x220>' \
    -gravity south -background none -extent 256x256 \
    \( +clone -alpha extract -threshold 0 \
       -define connected-components:area-threshold=20 \
       -define connected-components:mean-color=true -connected-components 8 \) \
    -alpha off -compose CopyOpacity -composite \
    "$OUTPUT/$output.png"
}

extract_mobile_character() {
  local source="$1" crop="$2" output="$3"
  local width="${crop%%x*}"
  local remainder="${crop#*x}"
  local height="${remainder%%+*}"
  local max_x=$((width - 1)) max_y=$((height - 1))
  local seed_x=$((width / 2)) seed_y=$((height / 2))
  local base="$WORK/$output-base.png" mask="$WORK/$output-mask.png"
  magick "$source" \
    -crop "$crop" +repage \
    -alpha on -fuzz 16% -fill none \
    -draw "alpha 0,0 floodfill alpha $max_x,0 floodfill alpha 0,$max_y floodfill alpha $max_x,$max_y floodfill" \
    "$base"
  magick "$base" \
    -alpha extract -threshold 0 \
    -fill '#808080' -draw "color $seed_x,$seed_y floodfill" \
    -fill black +opaque '#808080' -fill white -opaque '#808080' \
    -alpha copy "$mask"
  magick "$base" "$mask" -compose CopyAlpha -composite -compose Over \
    -trim +repage \
    -filter point -resize '220x220>' \
    -gravity south -background none -extent 256x256 \
    -dither None -colors 96 -define png:compression-level=9 \
    "PNG8:$MOBILE_OUTPUT/$output.png"
}

# Canonical two-frame states. Crops intentionally exclude sheet labels.
extract "$STATE_SHEET" '190x228+45+48' idle-1
extract "$STATE_SHEET" '235x212+278+64' idle-2
extract "$STATE_SHEET" '205x213+550+64' wave-1
extract "$STATE_SHEET" '205x213+800+64' wave-2
extract "$STATE_SHEET" '180x198+50+329' thinking-1
extract "$STATE_SHEET" '165x198+250+329' thinking-2
extract "$STATE_SHEET" '215x198+415+329' alert-1
cp "$OUTPUT/alert-1.png" "$OUTPUT/alert-2.png"
extract "$STATE_SHEET" '180x198+645+329' error-1
extract "$STATE_SHEET" '185x198+828+329' error-2

# The happy/talking loop lives on the second supplied sheet.
extract "$HAPPY_SHEET" '175x194+430+330' happy-1
extract "$HAPPY_SHEET" '200x185+630+330' happy-2

# Higher-frame mobile/web animations. Seeded masks keep only the selected
# character, excluding sheet labels, locks, notes, and punctuation.
find "$MOBILE_OUTPUT" -maxdepth 1 -type f \( -name 'idle-*.png' -o -name 'wave-*.png' -o -name 'happy-*.png' \
  -o -name 'thinking-*.png' -o -name 'error-*.png' -o -name 'locked-*.png' \
  -o -name 'look-*.png' -o -name 'dance-*.png' \) -delete
extract_mobile_character "$IDLE_WAVE_SHEET" '205x270+35+30' idle-1
extract_mobile_character "$IDLE_WAVE_SHEET" '165x245+215+55' idle-2
extract_mobile_character "$IDLE_WAVE_SHEET" '195x230+355+70' idle-3
extract_mobile_character "$IDLE_WAVE_SHEET" '165x245+530+55' idle-4
extract_mobile_character "$IDLE_WAVE_SHEET" '160x270+675+25' idle-5
extract_mobile_character "$IDLE_WAVE_SHEET" '205x270+810+30' idle-6
extract_mobile_character "$IDLE_WAVE_SHEET" '205x235+30+315' wave-1
extract_mobile_character "$IDLE_WAVE_SHEET" '205x235+215+315' wave-2
extract_mobile_character "$IDLE_WAVE_SHEET" '215x235+415+315' wave-3
extract_mobile_character "$IDLE_WAVE_SHEET" '210x235+625+315' wave-4
extract_mobile_character "$IDLE_WAVE_SHEET" '190x235+815+315' wave-5

extract_mobile_character "$THINKING_ALERT_SHEET" '160x240+45+55' thinking-1
extract_mobile_character "$THINKING_ALERT_SHEET" '165x240+210+55' thinking-2
extract_mobile_character "$THINKING_ALERT_SHEET" '170x240+365+55' thinking-3
extract_mobile_character "$THINKING_ALERT_SHEET" '170x240+520+55' thinking-4
extract_mobile_character "$THINKING_ALERT_SHEET" '165x240+675+55' thinking-5
extract_mobile_character "$THINKING_ALERT_SHEET" '170x240+825+55' thinking-6

extract_mobile_character "$ERROR_HAPPY_SHEET" '165x240+35+50' error-1
extract_mobile_character "$ERROR_HAPPY_SHEET" '165x240+190+50' error-2
extract_mobile_character "$ERROR_HAPPY_SHEET" '165x240+350+50' error-3
extract_mobile_character "$ERROR_HAPPY_SHEET" '165x240+665+50' error-4
extract_mobile_character "$ERROR_HAPPY_SHEET" '175x240+820+50' error-5
extract_mobile_character "$ERROR_HAPPY_SHEET" '185x250+35+300' happy-1
extract_mobile_character "$ERROR_HAPPY_SHEET" '180x250+205+300' happy-2
extract_mobile_character "$ERROR_HAPPY_SHEET" '175x250+655+315' happy-3
extract_mobile_character "$ERROR_HAPPY_SHEET" '180x250+820+315' happy-4

extract_mobile_character "$FOCUS_SHEET" '220x270+35+35' locked-1
extract_mobile_character "$FOCUS_SHEET" '255x250+270+45' locked-2
extract_mobile_character "$FOCUS_SHEET" '230x250+540+45' locked-3
extract_mobile_character "$FOCUS_SHEET" '210x270+790+35' locked-4
extract_mobile_character "$FOCUS_SHEET" '190x240+35+315' look-1
extract_mobile_character "$FOCUS_SHEET" '190x240+225+315' look-2
extract_mobile_character "$FOCUS_SHEET" '190x250+425+305' look-3
extract_mobile_character "$FOCUS_SHEET" '190x240+635+315' look-4
extract_mobile_character "$FOCUS_SHEET" '190x250+825+305' look-5

extract_mobile_character "$DANCE_SHEET" '220x260+30+40' dance-1
extract_mobile_character "$DANCE_SHEET" '220x250+280+50' dance-2
extract_mobile_character "$DANCE_SHEET" '220x260+530+40' dance-3
extract_mobile_character "$DANCE_SHEET" '220x275+785+25' dance-4
extract_mobile_character "$DANCE_SHEET" '220x235+30+315' dance-5
extract_mobile_character "$DANCE_SHEET" '195x235+230+315' dance-6
extract_mobile_character "$DANCE_SHEET" '210x250+410+300' dance-7
extract_mobile_character "$DANCE_SHEET" '210x260+615+290' dance-8
extract_mobile_character "$DANCE_SHEET" '190x235+815+315' dance-9

echo "Prepared macOS frames in $OUTPUT and mobile frames in $MOBILE_OUTPUT"
