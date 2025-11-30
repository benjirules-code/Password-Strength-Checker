#!/usr/bin/env bash

#======================================================================
# Author: Tony Carruthers
# Date: 30 November 2025
# Version: 1.5
# Password Strength Checker GUI
# Password strength checker with GUI and crack-time estimates
#======================================================================

set -euo pipefail

# Silence GTK/EGL warnings globally
export GTK_DEBUG=0
export LIBGL_DEBUG=quiet

APP_NAME="Password Strength Checker"
DESKTOP_FILE="$HOME/.local/share/applications/password-strength.desktop"

# --- Desktop integration setup ---
if [[ ! -f "$DESKTOP_FILE" ]]; then
  mkdir -p "$HOME/.local/share/applications"
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=$APP_NAME
Exec=$HOME/Documents/gui_password_strength.sh
Icon=security-high
Type=Application
Categories=Utility;Security;
Terminal=false
EOF
fi

# --- Password prompt ---
password=$(zenity --password --title="$APP_NAME" 2>/dev/null)
if [[ -z "$password" ]]; then
  zenity --error --text="No password entered. Exiting." 2>/dev/null
  exit 1
fi

len=${#password}

# Detect character classes
has_lower=0; has_upper=0; has_digit=0; has_space=0; has_symbol=0
for (( i=0; i<len; i++ )); do
  c="${password:i:1}"
  [[ "$c" =~ [a-z] ]] && has_lower=1
  [[ "$c" =~ [A-Z] ]] && has_upper=1
  [[ "$c" =~ [0-9] ]] && has_digit=1
  [[ "$c" == " " ]] && has_space=1
  [[ "$c" =~ [^a-zA-Z0-9\ ] ]] && has_symbol=1
done

alphabet=0
(( has_lower )) && alphabet=$((alphabet+26))
(( has_upper )) && alphabet=$((alphabet+26))
(( has_digit )) && alphabet=$((alphabet+10))
(( has_space )) && alphabet=$((alphabet+1))
if (( has_symbol )); then
  base_count=$(( (has_lower*26) + (has_upper*26) + (has_digit*10) + (has_space*1) ))
  sym_count=$((95 - base_count))
  (( sym_count < 0 )) && sym_count=0
  alphabet=$((alphabet + sym_count))
fi
(( alphabet <= 1 )) && alphabet=1

# Entropy calculation
entropy_bits=$(echo "scale=6; ${len} * (l($alphabet)/l(2))" | bc -l)

# Crack-time estimates
pow2() { echo "scale=10; e($1*l(2))" | bc -l; }
format_duration() {
  secs="$1"
  if [[ "$secs" == "0" || "$secs" == "0.0000000000" ]]; then echo "instant"; return; fi
  awk -v s="$secs" 'BEGIN{
    if (s < 1) { printf("%.6f s\n", s); exit }
    s=int(s+0.5)
    y=31557600; d=86400; h=3600; m=60
    yrs=int(s/y); s%=y
    days=int(s/d); s%=d
    hrs=int(s/h); s%=h
    mins=int(s/m); s%=m
    out=""
    if(yrs>0) out=out yrs "y "
    if(days>0) out=out days "d "
    if(hrs>0) out=out hrs "h "
    if(mins>0) out=out mins "m "
    out=out s "s"
    print out
  }'
}

half_space=$(pow2 "$(echo "$entropy_bits - 1" | bc -l)")

declare -A models=(
  ["Online throttled (~100/min)"]=1.6667
  ["Online fast (~10/s)"]=10
  ["Offline CPU (~10k/s)"]=10000
  ["GPU mid (~100M/s)"]=100000000
  ["GPU high (~10B/s)"]=10000000000
)

crack_times=""
for model in "${!models[@]}"; do
  gps="${models[$model]}"
  time_sec=$(echo "scale=10; $half_space / $gps" | bc -l)
  human=$(format_duration "$time_sec")
  crack_times+="$model: $human\n"
done

# Qualitative rating
qual="Weak"
if (( $(echo "$entropy_bits >= 60" | bc -l) )); then qual="Strong"
elif (( $(echo "$entropy_bits >= 40" | bc -l) )); then qual="Moderate"
fi

# Build message
message="Password length: $len
Alphabet size: $alphabet
Entropy: $entropy_bits bits
Rating: $qual

Estimated crack times:
$crack_times"

# Show results in a pop‑up info box
zenity --info --title="$APP_NAME Results" --text="$message" 2>/dev/null
