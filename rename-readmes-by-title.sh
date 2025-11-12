#!/usr/bin/env bash
set -euo pipefail

# rename-readmes-by-title.sh
# Usage:
#   ./rename-readmes-by-title.sh [--dry-run]
#
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "MODE DRY-RUN : aucun déplacement/modification ne sera effectué."
fi

# Find README.md files (exclude .git)
mapfile -t readme_files < <(find . -type f -iname "README.md" -not -path "./.git/*" | sed 's|^\./||')

if [[ ${#readme_files[@]} -eq 0 ]]; then
  echo "Aucun README.md trouvé."
  exit 0
fi

echo "Fichiers README.md trouvés: "
printf ' - %s\n' "${readme_files[@]}"

# Function to extract title
extract_title() {
  local file="$1"
  local first
  first=$(head -n1 "$file" || echo "")
  if [[ "$first" == "---" ]]; then
    # Get title from YAML frontmatter
    local title_line
    title_line=$(awk 'BEGIN{p=0} /^---/{ if(p==0){p=1; next} else{exit}} p==1 && tolower($0) ~ /^title[[:space:]]*:/ {print; exit}' "$file" 2>/dev/null || true)
    if [[ -n "$title_line" ]]; then
      echo "$title_line" | sed -E 's/^[[:space:]]*title[[:space:]]*:[[:space:]]*//I'
      return
    fi
  fi

  # Otherwise look for first line starting with "title:" anywhere in file
  local t
  t=$(grep -m1 -i '^[[:space:]]*title[[:space:]]*:' "$file" 2>/dev/null || true)
  if [[ -n "$t" ]]; then
    echo "$t" | sed -E 's/^[[:space:]]*title[[:space:]]*:[[:space:]]*//I'
    return
  fi

  echo ""
}

# Plan moves
declare -a moves_src
declare -a moves_dst

for f in "${readme_files[@]}"; do
  dir=$(dirname "$f")
  parent=$(dirname "$dir")
  if [[ "$dir" == "." ]]; then
    parent="."
  fi

  title=$(extract_title "$f" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  if [[ -z "$title" ]]; then
    echo "AVERTISSEMENT: pas de metadata 'title' trouvée dans '$f' -> saut."
    continue
  fi

  # Replace path separators only (user asked to keep accents/spaces)
  title_sanitized="${title//\//-}"

  dst="$parent/$title_sanitized.md"
  src_norm="$f"
  dst_norm="$dst"

  if [[ -e "$dst_norm" && "$dst_norm" != "$src_norm" ]]; then
    i=1
    base_no_ext="${dst_norm%.md}"
    while [[ -e "${base_no_ext}-$i.md" ]]; do
      ((i++))
    done
    dst_norm="${base_no_ext}-$i.md"
  fi

  moves_src+=("$src_norm")
moves_dst+=("$dst_norm")
done

echo
echo "Plan de déplacement/rénomage proposé :"
for i in "${!moves_src[@]}"; do
  printf " - '%s' -> '%s'\n" "${moves_src[$i]}" "${moves_dst[$i]}"
done

if [[ ${#moves_src[@]} -eq 0 ]]; then
  echo "Aucun fichier à traiter."
  exit 0
fi

if $DRY_RUN; then
  echo
  echo "DRY-RUN terminé. Relance sans --dry-run pour exécuter."
  exit 0
fi

# Execute git mv for each
for i in "${!moves_src[@]}"; do
  src="${moves_src[$i]}"
  dst="${moves_dst[$i]}"
  dst_dir=$(dirname "$dst")
  if [[ ! -d "$dst_dir" ]]; then
    mkdir -p "$dst_dir"
  fi

  if [[ "$src" == "$dst" ]]; then
    echo "Ignoré (même chemin) : $src"
    continue
  fi

  echo "git mv '$src' '$dst'"
  git mv "$src" "$dst"
done

# Commit and push will be handled by the workflow runner
echo
echo "Renommages effectués."