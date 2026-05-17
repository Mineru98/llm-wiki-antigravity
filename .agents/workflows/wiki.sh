#!/usr/bin/env sh
set -eu

operation=${1:-}
if [ -z "$operation" ]; then
  echo "usage: $0 <operation> [--input JSON] [--json] [--root PATH]" >&2
  exit 2
fi
shift

input='{}'
json=0
root=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --input|-InputJson|-input)
      shift
      input=${1:-}
      ;;
    --json|-Json)
      json=1
      ;;
    --root|-Root)
      shift
      root=${1:-}
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
find_wiki_root() {
  current=$script_dir
  while :; do
    if [ -d "$current/.git" ] || [ -f "$current/AGENTS.md" ]; then
      printf '%s' "$current"
      return 0
    fi
    parent=$(dirname -- "$current")
    if [ "$parent" = "$current" ]; then
      break
    fi
    current=$parent
  done
  CDPATH= cd -- "$script_dir/.." && pwd
}

if [ -z "$root" ]; then
  root=$(find_wiki_root)
fi

wiki_dir="$root/.wiki"
categories='architecture decision pattern debugging environment session-log reference convention'

die() {
  echo "$*" >&2
  exit 1
}

ensure_wiki() {
  mkdir -p "$wiki_dir"
}

now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

is_category() {
  for category_item in $categories; do
    if [ "$category_item" = "$1" ]; then
      return 0
    fi
  done
  return 1
}

slugify() {
  slug=$(printf '%s' "$1" |
    tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz' |
    sed 's/[^[:alnum:]][^[:alnum:]]*/-/g; s/^-//; s/-$//')
  if [ -z "$slug" ]; then
    slug="page-$(date -u '+%s')"
  fi
  printf '%s' "$slug"
}

json_string() {
  key=$1
  printf '%s' "$input" | awk -v key="$key" '
    BEGIN { needle = "\"" key "\"" }
    { source = source $0 "\n" }
    END {
      start = index(source, needle)
      if (!start) exit
      source = substr(source, start + length(needle))
      colon = index(source, ":")
      if (!colon) exit
      source = substr(source, colon + 1)
      sub(/^[[:space:]]*/, "", source)
      if (substr(source, 1, 1) != "\"") exit
      source = substr(source, 2)
      escaped = 0
      out = ""
      for (i = 1; i <= length(source); i++) {
        char = substr(source, i, 1)
        if (escaped) {
          if (char == "n") out = out "\n"
          else if (char == "t") out = out "\t"
          else if (char == "r") out = out "\r"
          else out = out char
          escaped = 0
        } else if (char == "\\") {
          escaped = 1
        } else if (char == "\"") {
          print out
          exit
        } else {
          out = out char
        }
      }
    }
  '
}

json_array_strings() {
  key=$1
  printf '%s' "$input" | awk -v key="$key" '
    BEGIN { needle = "\"" key "\"" }
    { source = source $0 "\n" }
    END {
      start = index(source, needle)
      if (!start) exit
      source = substr(source, start + length(needle))
      colon = index(source, ":")
      if (!colon) exit
      source = substr(source, colon + 1)
      bracket = index(source, "[")
      if (!bracket) exit
      source = substr(source, bracket + 1)
      in_string = 0
      escaped = 0
      out = ""
      for (i = 1; i <= length(source); i++) {
        char = substr(source, i, 1)
        if (in_string) {
          if (escaped) {
            if (char == "n") out = out "\n"
            else if (char == "t") out = out "\t"
            else if (char == "r") out = out "\r"
            else out = out char
            escaped = 0
          } else if (char == "\\") {
            escaped = 1
          } else if (char == "\"") {
            print out
            out = ""
            in_string = 0
          } else {
            out = out char
          }
        } else if (char == "\"") {
          in_string = 1
        } else if (char == "]") {
          exit
        }
      }
    }
  '
}

escape_json() {
  awk '
    BEGIN { ORS = "" }
    {
      if (NR > 1) printf "\\n"
      for (i = 1; i <= length($0); i++) {
        char = substr($0, i, 1)
        if (char == "\\") printf "\\\\"
        else if (char == "\"") printf "\\\""
        else if (char == "\t") printf "\\t"
        else printf "%s", char
      }
    }
  '
}

json_quote() {
  printf '"'
  printf '%s' "$1" | escape_json
  printf '"'
}

tags_json_from_lines() {
  awk '
    BEGIN { printf "["; first = 1 }
    {
      if ($0 == "") next
      if (!first) printf ","
      first = 0
      gsub(/\\/,"\\\\")
      gsub(/"/,"\\\"")
      printf "\"" $0 "\""
    }
    END { printf "]" }
  '
}

tags_csv_from_lines() {
  awk '
    $0 != "" {
      if (out != "") out = out ", "
      out = out $0
    }
    END { print out }
  '
}

page_files() {
  if [ -d "$wiki_dir" ]; then
    find "$wiki_dir" -maxdepth 1 -type f -name '*.md' ! -name 'index.md' ! -name 'log.md' | sort
  fi
}

meta_value() {
  file=$1
  key=$2
  awk -v key="$key" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      sub(/^[[:space:]]*/, "", value)
      print value
      exit
    }
  ' "$file"
}

meta_tags() {
  file=$1
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && $0 ~ /^tags:[[:space:]]*$/ { tags = 1; next }
    fm && tags && $0 ~ /^[[:space:]]*-[[:space:]]*/ {
      value = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", value)
      print value
      next
    }
    fm && tags && $0 !~ /^[[:space:]]/ { exit }
  ' "$file"
}

page_content() {
  file=$1
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    !fm { print }
  ' "$file" | sed '1{/^$/d;}'
}

page_title() {
  file=$1
  value=$(meta_value "$file" title)
  if [ -n "$value" ]; then printf '%s' "$value"; else basename "$file" .md; fi
}

page_slug() {
  file=$1
  value=$(meta_value "$file" slug)
  if [ -n "$value" ]; then printf '%s' "$value"; else basename "$file" .md; fi
}

page_category() {
  meta_value "$1" category
}

page_created() {
  meta_value "$1" created
}

page_updated() {
  meta_value "$1" updated
}

page_json() {
  file=$1
  title=$(page_title "$file")
  slug=$(page_slug "$file")
  category=$(page_category "$file")
  created=$(page_created "$file")
  updated=$(page_updated "$file")
  tags_json=$(meta_tags "$file" | tags_json_from_lines)
  content=$(page_content "$file")
  printf '{'
  printf '"title":%s,' "$(json_quote "$title")"
  printf '"slug":%s,' "$(json_quote "$slug")"
  printf '"category":%s,' "$(json_quote "$category")"
  printf '"tags":%s,' "$tags_json"
  printf '"created":%s,' "$(json_quote "$created")"
  printf '"updated":%s,' "$(json_quote "$updated")"
  printf '"content":%s,' "$(json_quote "$content")"
  printf '"path":%s' "$(json_quote "$file")"
  printf '}'
}

add_log() {
  ensure_wiki
  printf '%s\n' "- $(now_utc) $1" >> "$wiki_dir/log.md"
}

refresh_index() {
  ensure_wiki
  {
    printf '%s\n\n' '# Wiki Index'
    for category_item in $categories; do
      section=''
      while IFS= read -r file; do
        [ -n "$file" ] || continue
        if [ "$(page_category "$file")" = "$category_item" ]; then
          title=$(page_title "$file")
          slug=$(page_slug "$file")
          tag_text=$(meta_tags "$file" | tags_csv_from_lines)
          if [ -n "$tag_text" ]; then
            line="- [[$slug]] - $title [$tag_text]"
          else
            line="- [[$slug]] - $title"
          fi
          section="${section}${line}
"
        fi
      done <<EOF
$(page_files)
EOF
      if [ -n "$section" ]; then
        printf '## %s\n\n' "$category_item"
        printf '%s\n' "$section"
      fi
    done
  } > "$wiki_dir/index.md"
}

find_page_file() {
  wanted=$1
  wanted_slug=$(slugify "$wanted")
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    stem=$(basename "$file" .md)
    if [ "$stem" = "$wanted" ] || [ "$stem" = "$wanted_slug" ]; then
      printf '%s' "$file"
      return 0
    fi
  done <<EOF
$(page_files)
EOF
  return 1
}

write_page() {
  title=$(json_string title)
  content=$(json_string content)
  category=$(json_string category)
  slug=$(json_string slug)
  [ -n "$category" ] || category='reference'
  [ -n "$slug" ] || slug=$(slugify "$title")

  [ -n "$title" ] || die 'title is required'
  [ -n "$content" ] || die 'content is required'
  is_category "$category" || die "invalid category '$category'. Allowed: $categories"

  ensure_wiki
  path="$wiki_dir/$slug.md"
  now=$(now_utc)
  created=$now
  if [ -f "$path" ]; then
    existing_created=$(page_created "$path")
    [ -z "$existing_created" ] || created=$existing_created
  fi

  {
    printf '%s\n' '---'
    printf 'title: %s\n' "$title"
    printf 'slug: %s\n' "$slug"
    printf 'category: %s\n' "$category"
    printf '%s\n' 'tags:'
    json_array_strings tags | while IFS= read -r tag; do
      [ -n "$tag" ] && printf '  - %s\n' "$tag"
    done
    printf 'created: %s\n' "$created"
    printf 'updated: %s\n' "$now"
    printf '%s\n\n' '---'
    printf '%s\n' "$content"
  } > "$path"

  add_log "upsert $slug"
  refresh_index
  page_json "$path"
}

query_pages() {
  query=$(json_string query)
  category=$(json_string category)
  required_tags=$(json_array_strings tags)
  first=1
  printf '['
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    file_category=$(page_category "$file")
    if [ -n "$category" ] && [ "$file_category" != "$category" ]; then
      continue
    fi

    missing=0
    for tag in $required_tags; do
      if ! meta_tags "$file" | grep -Fx "$tag" >/dev/null 2>&1; then
        missing=1
        break
      fi
    done
    [ "$missing" -eq 0 ] || continue

    haystack=$(printf '%s %s %s %s %s' "$(page_title "$file")" "$(page_slug "$file")" "$file_category" "$(meta_tags "$file" | tr '\n' ' ')" "$(page_content "$file")" |
      tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
    score=0
    if [ -n "$query" ]; then
      for term in $query; do
        lower_term=$(printf '%s' "$term" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
        case "$haystack" in
          *"$lower_term"*) score=$((score + 1)) ;;
        esac
      done
      [ "$score" -gt 0 ] || continue
    fi
    for tag in $required_tags; do score=$((score + 2)); done
    [ -z "$category" ] || score=$((score + 1))

    title=$(page_title "$file")
    slug=$(page_slug "$file")
    tags_json=$(meta_tags "$file" | tags_json_from_lines)
    excerpt=$(page_content "$file" | awk 'BEGIN{ORS=""} { if (length(out) < 180) out = out (out == "" ? "" : "\n") $0 } END { print substr(out, 1, 180) }')
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '{'
    printf '"title":%s,' "$(json_quote "$title")"
    printf '"slug":%s,' "$(json_quote "$slug")"
    printf '"category":%s,' "$(json_quote "$file_category")"
    printf '"tags":%s,' "$tags_json"
    printf '"score":%s,' "$score"
    printf '"excerpt":%s' "$(json_quote "$excerpt")"
    printf '}'
  done <<EOF
$(page_files)
EOF
  printf ']'
}

lint_pages() {
  tmp_slugs="${TMPDIR:-/tmp}/wiki-slugs-$$"
  : > "$tmp_slugs"
  first=1
  issue_count=0
  errors=0
  issues=''

  add_issue() {
    issue_page=$1
    issue_severity=$2
    issue_message=$3
    issue_count=$((issue_count + 1))
    [ "$issue_severity" != "error" ] || errors=$((errors + 1))
    issue_json=$(printf '{"page":%s,"severity":%s,"message":%s}' "$(json_quote "$issue_page")" "$(json_quote "$issue_severity")" "$(json_quote "$issue_message")")
    if [ "$first" -eq 1 ]; then
      issues=$issue_json
      first=0
    else
      issues="${issues},${issue_json}"
    fi
  }

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    slug=$(page_slug "$file")
    title=$(page_title "$file")
    category=$(page_category "$file")
    [ -n "$title" ] || add_issue "$slug" error 'missing title'
    if [ -n "$category" ] && ! is_category "$category"; then
      add_issue "$slug" error "invalid category '$category'"
    fi
    if grep -Fx "$slug" "$tmp_slugs" >/dev/null 2>&1; then
      add_issue "$slug" error 'duplicate slug'
    fi
    printf '%s\n' "$slug" >> "$tmp_slugs"
  done <<EOF
$(page_files)
EOF

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    slug=$(page_slug "$file")
    page_content "$file" | awk '
      {
        line = $0
        while (match(line, /\[\[[^]]+\]\]/)) {
          target = substr(line, RSTART + 2, RLENGTH - 4)
          print target
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' | while IFS= read -r target; do
      target_slug=$(slugify "$target")
      if ! grep -Fx "$target_slug" "$tmp_slugs" >/dev/null 2>&1; then
        printf '%s\t%s\n' "$slug" "$target" >> "${tmp_slugs}.broken"
      fi
    done
  done <<EOF
$(page_files)
EOF

  if [ -f "${tmp_slugs}.broken" ]; then
    while IFS="$(printf '\t')" read -r slug target; do
      add_issue "$slug" warning "broken wiki link '$target'"
    done < "${tmp_slugs}.broken"
  fi
  rm -f "$tmp_slugs" "${tmp_slugs}.broken"

  if [ "$errors" -eq 0 ]; then ok=true; else ok=false; fi
  printf '{"ok":%s,"issue_count":%s,"issues":[%s]}' "$ok" "$issue_count" "$issues"
}

list_pages() {
  first=1
  printf '['
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    title=$(page_title "$file")
    slug=$(page_slug "$file")
    category=$(page_category "$file")
    updated=$(page_updated "$file")
    tags_json=$(meta_tags "$file" | tags_json_from_lines)
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '{'
    printf '"title":%s,' "$(json_quote "$title")"
    printf '"slug":%s,' "$(json_quote "$slug")"
    printf '"category":%s,' "$(json_quote "$category")"
    printf '"tags":%s,' "$tags_json"
    printf '"updated":%s' "$(json_quote "$updated")"
    printf '}'
  done <<EOF
$(page_files)
EOF
  printf ']'
}

case "$operation" in
  wiki_add|wiki_ingest)
    result=$(write_page)
    ;;
  wiki_query)
    result=$(query_pages)
    ;;
  wiki_lint)
    result=$(lint_pages)
    ;;
  wiki_list)
    result=$(list_pages)
    ;;
  wiki_read)
    page=$(json_string page)
    file=$(find_page_file "$page") || die "page not found: $page"
    result=$(page_json "$file")
    ;;
  wiki_delete)
    page=$(json_string page)
    file=$(find_page_file "$page") || die "page not found: $page"
    file_dir=$(CDPATH= cd -- "$(dirname -- "$file")" && pwd)
    canonical_dir=$(CDPATH= cd -- "$wiki_dir" && pwd)
    [ "$file_dir" = "$canonical_dir" ] || die 'refusing to delete page outside .wiki'
    slug=$(page_slug "$file")
    rm -f "$file"
    add_log "delete $slug"
    refresh_index
    result=$(printf '{"deleted":%s}' "$(json_quote "$slug")")
    ;;
  wiki_refresh)
    ensure_wiki
    refresh_index
    add_log 'refresh index'
    count=$(page_files | awk 'NF { c++ } END { print c + 0 }')
    result=$(printf '{"refreshed":true,"page_count":%s}' "$count")
    ;;
  *)
    die "unknown operation: $operation"
    ;;
esac

printf '%s\n' "$result"
