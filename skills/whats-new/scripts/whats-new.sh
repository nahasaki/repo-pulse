#!/usr/bin/env bash
# whats-new.sh — summarize activity in the current git repository.
# See SPEC.md and openspec/changes/implement-whats-new/specs/whats-new/spec.md.

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Config: read from plugin userConfig via CLAUDE_PLUGIN_OPTION_* env vars.
# Dev-mode fallback: if env vars are unset AND a user-authored
# skills/whats-new/config.local.sh exists, source it. That file is not
# shipped by the plugin; it is a convenience for `claude --plugin-dir`
# sessions where the harness may not populate the env vars.
# ---------------------------------------------------------------------------
DEFAULT_SINCE="${CLAUDE_PLUGIN_OPTION_DEFAULT_SINCE:-7 days ago}"
RAW_EXTRA_EMAILS="${CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS:-}"

DEV_FALLBACK_USED=false
if [[ -z "${CLAUDE_PLUGIN_OPTION_DEFAULT_SINCE:-}" ]] \
   && [[ -z "${CLAUDE_PLUGIN_OPTION_EXTRA_EMAILS:-}" ]] \
   && [[ -f "${SKILL_DIR}/config.local.sh" ]]; then
  # shellcheck disable=SC1091
  . "${SKILL_DIR}/config.local.sh"
  DEV_FALLBACK_USED=true
fi

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SINCE_ARG=""
for arg in "$@"; do
  case "${arg}" in
    --since=*) SINCE_ARG="${arg#--since=}" ;;
    --help|-h)
      cat <<'EOF'
Usage: whats-new.sh [--since=<period>]

Options:
  --since=<period>  Any value git log --since accepts. Examples:
                    "3d", "1w", "2 weeks ago", "2026-04-20".
                    Default: start window at the committer date of your
                    most recent commit in this repo; else DEFAULT_SINCE.
EOF
      exit 0
      ;;
    *) echo "whats-new: unknown argument: ${arg}" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Warnings channel: buffered and printed at the top of the output
# ---------------------------------------------------------------------------
NOTES=()
note() { NOTES+=("> note: $*"); }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "whats-new: not inside a git work tree" >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
REPO_SLUG="$(basename "${REPO_ROOT}")"

ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"

# extract_hostname: pull the domain out of a git remote URL.
# Handles ssh (git@host:path), https (https://host/path), git (git://host/path).
extract_hostname() {
  local url="$1"
  [[ -z "${url}" ]] && return 0
  # Strip optional user@ prefix and scheme.
  local stripped="${url#*://}"
  stripped="${stripped#*@}"
  # Domain ends at first '/' or ':'.
  stripped="${stripped%%/*}"
  stripped="${stripped%%:*}"
  printf '%s' "${stripped}"
}

FORGE_HOSTNAME="$(extract_hostname "${ORIGIN_URL}")"
FORGE="unknown"

# auth_hostname_matches <cli> <hostname>
# Both gh and glab `auth status --hostname <h>` exit 0 regardless of auth state,
# so we grep stdout+stderr for "Logged in to <host>". Empty/unknown host never matches.
auth_hostname_matches() {
  local cli="$1" host="$2"
  [[ -z "${host}" ]] && return 1
  command -v "${cli}" >/dev/null 2>&1 || return 1
  "${cli}" auth status --hostname "${host}" 2>&1 \
    | grep -Fq "Logged in to ${host}"
}

# Fast-path: domain match on the two public forges.
case "${FORGE_HOSTNAME}" in
  github.com)  FORGE="github" ;;
  gitlab.com)  FORGE="gitlab" ;;
esac

# Probe fallback: GHE / self-hosted GitLab.
if [[ "${FORGE}" == "unknown" && -n "${FORGE_HOSTNAME}" ]]; then
  if auth_hostname_matches gh "${FORGE_HOSTNAME}"; then
    FORGE="github"
  elif auth_hostname_matches glab "${FORGE_HOSTNAME}"; then
    FORGE="gitlab"
  fi
fi

HAS_JQ=false
command -v jq >/dev/null 2>&1 && HAS_JQ=true

# Fatal: jq required if forge is known AND the forge's CLI is installed
# (we would use glab/gh + jq). On unknown forge, missing jq is non-fatal.
if [[ "${FORGE}" != "unknown" ]] && ! ${HAS_JQ}; then
  forge_cli="glab"; [[ "${FORGE}" == "github" ]] && forge_cli="gh"
  if command -v "${forge_cli}" >/dev/null 2>&1; then
    cat >&2 <<EOF
whats-new: jq is required to parse ${forge_cli} JSON output.
  macOS:   brew install jq
  Debian:  sudo apt install jq
  Fedora:  sudo dnf install jq
EOF
    exit 1
  fi
fi

# Install-hint helper for missing / unauthed CLIs.
emit_missing_cli_hint() {
  local forge="$1" host="$2" reason="$3"
  local cli="glab" install_url="https://gitlab.com/gitlab-org/cli"
  if [[ "${forge}" == "github" ]]; then
    cli="gh"; install_url="https://cli.github.com/"
  fi
  local login_cmd="${cli} auth login"
  # Host-specific login only for non-default hostnames (GHE / self-hosted GitLab).
  if [[ -n "${host}" && "${host}" != "github.com" && "${host}" != "gitlab.com" ]]; then
    login_cmd="${cli} auth login --hostname ${host}"
  fi
  local forge_label="GitLab"; [[ "${forge}" == "github" ]] && forge_label="GitHub"
  note "origin is on ${forge_label} but ${reason}. §3/§5/§6 will be empty."
  note "Install:"
  note "  macOS:    brew install ${cli}"
  note "  Debian:   sudo apt install ${cli}"
  note "  Fedora:   sudo dnf install ${cli}"
  note "  other:    ${install_url}"
  note "Then run:  ${login_cmd}"
}

# Per-forge CLI presence + auth.
HAS_GLAB=false
HAS_GH=false
case "${FORGE}" in
  gitlab)
    if ! command -v glab >/dev/null 2>&1; then
      emit_missing_cli_hint gitlab "${FORGE_HOSTNAME}" "\`glab\` is not installed"
    elif ! auth_hostname_matches glab "${FORGE_HOSTNAME}"; then
      emit_missing_cli_hint gitlab "${FORGE_HOSTNAME}" "\`glab\` is not authenticated for ${FORGE_HOSTNAME}"
    else
      HAS_GLAB=true
    fi
    ;;
  github)
    if ! command -v gh >/dev/null 2>&1; then
      emit_missing_cli_hint github "${FORGE_HOSTNAME}" "\`gh\` is not installed"
    elif ! auth_hostname_matches gh "${FORGE_HOSTNAME}"; then
      emit_missing_cli_hint github "${FORGE_HOSTNAME}" "\`gh\` is not authenticated for ${FORGE_HOSTNAME}"
    else
      HAS_GH=true
    fi
    ;;
  unknown)
    # Silent — we don't know which CLI to suggest. git-only sections only.
    :
    ;;
esac

# jq missing + forge CLI present = downgrade (shouldn't reach here because
# fatal path above would have exited, but defensive).
if ! ${HAS_JQ}; then
  ${HAS_GLAB} && { note "jq not found; skipping glab-dependent sections"; HAS_GLAB=false; }
  ${HAS_GH}   && { note "jq not found; skipping gh-dependent sections";   HAS_GH=false; }
fi

# ---------------------------------------------------------------------------
# Fetch — soft failure
# ---------------------------------------------------------------------------
if ! git fetch --all --prune --quiet 2>/dev/null; then
  note "git fetch failed (offline?); showing stale refs"
fi

# ---------------------------------------------------------------------------
# Default branch detection
# ---------------------------------------------------------------------------
detect_default_branch() {
  local ref
  if ref="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s\n' "${ref#refs/remotes/origin/}"
    return
  fi
  printf '%s\n' "main"
}
DEFAULT_BRANCH="$(detect_default_branch)"

# Does the default branch actually exist as a remote ref?
DEFAULT_REF="origin/${DEFAULT_BRANCH}"
HAS_DEFAULT_REF=false
if git rev-parse --verify --quiet "${DEFAULT_REF}" >/dev/null; then
  HAS_DEFAULT_REF=true
else
  note "no ${DEFAULT_REF} ref found; default-branch sections (1, 6) will be empty"
fi

# ---------------------------------------------------------------------------
# Effective email list: git config user.email  ∪  extra_emails from userConfig
# ---------------------------------------------------------------------------

# parse_extras: splits RAW_EXTRA_EMAILS (which may be JSON array, CSV,
# newline-separated, or a single value) into one email per line.
parse_extras() {
  local raw="$1"
  [[ -z "${raw}" ]] && return 0
  # JSON array form (likely what `multiple: true` produces): decode via jq.
  if [[ "${raw:0:1}" == "[" ]] && command -v jq >/dev/null 2>&1; then
    printf '%s' "${raw}" | jq -r '.[]? // empty' 2>/dev/null && return
  fi
  # Generic form: split on commas and newlines, trim whitespace, drop empties.
  printf '%s\n' "${raw}" | tr ',' '\n' | awk '
    { gsub(/^[ \t]+|[ \t]+$/, "", $0); if ($0 != "") print }
  '
}

# Dev-mode fallback (config.local.sh may declare a plain bash array
# EXTRA_EMAILS=(...)): if env var is empty and the array got populated,
# fold it into RAW_EXTRA_EMAILS as a newline-separated string.
if [[ -z "${RAW_EXTRA_EMAILS}" ]] \
   && declare -p EXTRA_EMAILS >/dev/null 2>&1 \
   && [[ "$(declare -p EXTRA_EMAILS 2>/dev/null)" == *"-a"* ]] \
   && [[ ${#EXTRA_EMAILS[@]} -gt 0 ]]; then
  RAW_EXTRA_EMAILS="$(printf '%s\n' "${EXTRA_EMAILS[@]}")"
fi

EXTRA_EMAILS_RESOLVED=()
while IFS= read -r __line; do
  [[ -z "${__line}" ]] && continue
  EXTRA_EMAILS_RESOLVED+=("${__line}")
done < <(parse_extras "${RAW_EXTRA_EMAILS}")

GIT_USER_EMAIL="$(git config user.email 2>/dev/null || true)"

# Case-insensitive dedup; preserve original casing in the stored form.
EFFECTIVE_EMAILS=()
add_email_unique() {
  local candidate="$1"
  [[ -z "${candidate}" ]] && return 0
  local candidate_lc
  candidate_lc="$(printf '%s' "${candidate}" | tr '[:upper:]' '[:lower:]')"
  local existing existing_lc
  for existing in ${EFFECTIVE_EMAILS[@]+"${EFFECTIVE_EMAILS[@]}"}; do
    existing_lc="$(printf '%s' "${existing}" | tr '[:upper:]' '[:lower:]')"
    [[ "${existing_lc}" == "${candidate_lc}" ]] && return 0
  done
  EFFECTIVE_EMAILS+=("${candidate}")
}

add_email_unique "${GIT_USER_EMAIL}"
for __e in ${EXTRA_EMAILS_RESOLVED[@]+"${EXTRA_EMAILS_RESOLVED[@]}"}; do
  add_email_unique "${__e}"
done

if [[ ${#EFFECTIVE_EMAILS[@]} -eq 0 ]]; then
  note "no git user.email set and extra_emails is empty — section 4 will be blank; window falls back to DEFAULT_SINCE"
fi

if ${DEV_FALLBACK_USED}; then
  note "dev-mode: loaded config from skills/whats-new/config.local.sh (no CLAUDE_PLUGIN_OPTION_* env vars present)"
fi

build_email_regex() {
  if [[ ${#EFFECTIVE_EMAILS[@]} -eq 0 ]]; then
    printf ''
    return
  fi
  local out="" sep="" e
  for e in "${EFFECTIVE_EMAILS[@]}"; do
    # Escape regex metachars minimally — emails normally only have dots.
    out+="${sep}${e//./\\.}"
    sep="|"
  done
  printf '%s' "${out}"
}
MY_EMAIL_REGEX="$(build_email_regex)"

# ---------------------------------------------------------------------------
# Date helpers (BSD + GNU)
# ---------------------------------------------------------------------------
NOW_UNIX="$(date -u +%s)"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# unix_to_iso <seconds>
unix_to_iso() {
  local ts="$1"
  # GNU
  if date -u -d "@${ts}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; then return; fi
  # BSD (macOS)
  if date -u -r "${ts}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; then return; fi
  printf '@%s\n' "${ts}"
}

# since_to_unix <git-since-value>
# Returns the window-start epoch. Handles "@<unix>" exactly; for arbitrary
# values, tries GNU `date -d`, then a best-effort set of BSD forms, then
# falls back to 0 (meaning "print raw"). Callers should still use SINCE
# directly when invoking git, not this epoch — it's for display only.
since_to_unix() {
  local spec="$1"
  case "${spec}" in
    @*)
      printf '%s\n' "${spec#@}"
      return
      ;;
  esac
  # GNU date understands "7 days ago", "3d", ISO dates, etc.
  if d="$(date -u -d "${spec}" +%s 2>/dev/null)"; then
    printf '%s\n' "$d"
    return
  fi
  # BSD date: try a few common forms.
  # Short git-style: "3d", "1w", "12h", "2m", "1y".
  if [[ "${spec}" =~ ^([0-9]+)([dwhmy])$ ]]; then
    local n="${BASH_REMATCH[1]}" u="${BASH_REMATCH[2]}"
    case "${u}" in
      h) date -u -v "-${n}H" +%s 2>/dev/null && return ;;
      d) date -u -v "-${n}d" +%s 2>/dev/null && return ;;
      w) date -u -v "-${n}w" +%s 2>/dev/null && return ;;
      m) date -u -v "-${n}m" +%s 2>/dev/null && return ;;
      y) date -u -v "-${n}y" +%s 2>/dev/null && return ;;
    esac
  fi
  # Long relative: "7 days ago", "2 weeks ago", "3 hours ago".
  case "${spec}" in
    *day*ago)
      local n="${spec%% *}"
      date -u -v "-${n}d" +%s 2>/dev/null && return
      ;;
    *week*ago)
      local n="${spec%% *}"
      date -u -v "-${n}w" +%s 2>/dev/null && return
      ;;
    *hour*ago)
      local n="${spec%% *}"
      date -u -v "-${n}H" +%s 2>/dev/null && return
      ;;
    *month*ago)
      local n="${spec%% *}"
      date -u -v "-${n}m" +%s 2>/dev/null && return
      ;;
    *year*ago)
      local n="${spec%% *}"
      date -u -v "-${n}y" +%s 2>/dev/null && return
      ;;
  esac
  # ISO date form YYYY-MM-DD
  if [[ "${spec}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    date -u -j -f '%Y-%m-%d' "${spec}" +%s 2>/dev/null && return
  fi
  # Give up — return 0 so callers know.
  printf '0\n'
}

# ---------------------------------------------------------------------------
# Window resolution
# ---------------------------------------------------------------------------
SINCE=""
REASON=""

if [[ -n "${SINCE_ARG}" ]]; then
  SINCE="${SINCE_ARG}"
  REASON="--since=${SINCE_ARG}"
else
  LAST_USER_CT=""
  LAST_USER_CI=""
  if [[ -n "${MY_EMAIL_REGEX}" ]]; then
    # Grab the single most recent user commit (by committer date).
    LINE="$(git log --all --extended-regexp --regexp-ignore-case --author="${MY_EMAIL_REGEX}" \
                    --format='%ct %cI' -1 2>/dev/null || true)"
    if [[ -n "${LINE}" ]]; then
      LAST_USER_CT="${LINE%% *}"
      LAST_USER_CI="${LINE#* }"
    fi
  fi
  if [[ -n "${LAST_USER_CT}" ]]; then
    SINCE="@$((LAST_USER_CT + 1))"
    REASON="from your last commit on ${LAST_USER_CI}"
  else
    SINCE="${DEFAULT_SINCE}"
    REASON="DEFAULT_SINCE fallback (${DEFAULT_SINCE})"
    # The "no identity at all" note is already emitted earlier when
    # EFFECTIVE_EMAILS is empty. Here we only land if identity is known but
    # produced no commits in this repo — so no additional note is needed.
  fi
fi

WINDOW_START_UNIX="$(since_to_unix "${SINCE}")"
if [[ "${WINDOW_START_UNIX}" != "0" ]]; then
  WINDOW_START_ISO="$(unix_to_iso "${WINDOW_START_UNIX}")"
  # Rewrite SINCE to the epoch form so git log gets an unambiguous cutoff.
  # git's approxidate misparses forms like "7d" (as "the 7th day of the month")
  # but handles "@<unix>" exactly.
  SINCE="@${WINDOW_START_UNIX}"
else
  WINDOW_START_ISO="${SINCE}"
fi

# ---------------------------------------------------------------------------
# Forge user identity (for section 3 "Open — mine" partitioning)
# ---------------------------------------------------------------------------
ME_USERNAME=""
if ${HAS_GLAB}; then
  ME_USERNAME="$(glab api /user 2>/dev/null | jq -r '.username // empty' 2>/dev/null || true)"
elif ${HAS_GH}; then
  ME_USERNAME="$(gh api user --jq .login 2>/dev/null || true)"
fi

# ---------------------------------------------------------------------------
# Section collectors — each writes markdown (no heading) to stdout
# ---------------------------------------------------------------------------

collect_section1() {
  ${HAS_DEFAULT_REF} || return 0
  git log "${DEFAULT_REF}" --since="${SINCE}" --no-merges \
        --format='%h%x09%cI%x09%ae%x09%an%x09%s' 2>/dev/null \
  | awk -F'\t' -v regex="${MY_EMAIL_REGEX}" '
      {
        email = $3
        if (regex != "" && email ~ regex) next
        date = substr($2, 1, 10)
        printf("- %s `%s` **%s** — %s\n", date, $1, $5, $4)
      }'
}

collect_section2() {
  local window_unix="${WINDOW_START_UNIX}"
  [[ "${window_unix}" == "0" ]] && return 0

  git for-each-ref --sort=-committerdate \
      --format='%(refname)|%(refname:short)|%(committerdate:unix)|%(committerdate:short)|%(authorname)' \
      refs/remotes/origin/ 2>/dev/null \
  | while IFS='|' read -r refname branch cunix cdate aname; do
      # Skip the origin/HEAD symbolic ref (refname:short can be just "origin"
      # on some git versions, so check the full refname).
      [[ "${refname}" == "refs/remotes/origin/HEAD" ]] && continue
      [[ "${branch}" == "${DEFAULT_REF}" ]] && continue
      [[ -z "${cunix}" ]] && continue
      if [[ "${cunix}" -lt "${window_unix}" ]]; then
        continue
      fi
      # Exclude branches where every in-window commit is by the user.
      if [[ -n "${MY_EMAIL_REGEX}" ]]; then
        local total user_count
        total="$(git log "${branch}" --since="${SINCE}" --format='%ae' 2>/dev/null | wc -l | tr -d ' ')"
        if [[ "${total}" -gt 0 ]]; then
          user_count="$(git log "${branch}" --since="${SINCE}" \
                                --extended-regexp --regexp-ignore-case --author="${MY_EMAIL_REGEX}" \
                                --format='%ae' 2>/dev/null | wc -l | tr -d ' ')"
          [[ "${user_count}" == "${total}" ]] && continue
        fi
      fi
      local ahead="0"
      if ${HAS_DEFAULT_REF}; then
        ahead="$(git rev-list --count "${DEFAULT_REF}..${branch}" 2>/dev/null || printf '0')"
      fi
      printf -- '- `%s` — last push %s by %s (%s commits ahead of %s)\n' \
        "${branch#origin/}" "${cdate}" "${aname}" "${ahead}" "${DEFAULT_BRANCH}"
    done
}

# Section 3 outputs three sub-files: s3a (others), s3b (merged), s3c (mine).
# The caller is responsible for creating ${S3A_FILE}, ${S3B_FILE}, ${S3C_FILE}.
collect_section3_gitlab() {
  ${HAS_GLAB} || return 0
  # glab mr list has no --updated-after flag; it does support --created-after
  # which is too strict (misses old MRs touched recently). So we fetch all
  # states with -A and filter by updated_at in jq.
  local mrs_json
  mrs_json="$(glab mr list -A -F json --per-page 100 2>/dev/null || printf '[]')"
  local me="${ME_USERNAME}"
  local start_iso="${WINDOW_START_ISO}"

  # Open — others
  printf '%s' "${mrs_json}" | jq -r --arg me "${me}" --arg start "${start_iso}" '
      [ .[] | select(.state == "opened") | select(.author.username != $me) ] | sort_by(.updated_at) | reverse
      | .[]
      | "- !\(.iid) **\(.title)** — \(.author.name // .author.username), \(.source_branch) → \(.target_branch), CI: \(
          (.pipeline // .head_pipeline // {}) | .status // "—"
        )"
    ' > "${S3A_FILE}"

  # Merged this period
  printf '%s' "${mrs_json}" | jq -r --arg start "${start_iso}" '
      [ .[] | select(.state == "merged") | select((.merged_at // "") >= $start) ] | sort_by(.merged_at) | reverse
      | .[]
      | "- !\(.iid) **\(.title)** — \(.author.name // .author.username), \(.source_branch) → \(.target_branch), merged \(.merged_at[:10])"
    ' > "${S3B_FILE}"

  # Open — mine
  if [[ -n "${me}" ]]; then
    printf '%s' "${mrs_json}" | jq -r --arg me "${me}" '
        [ .[] | select(.state == "opened") | select(.author.username == $me) ] | sort_by(.updated_at) | reverse
        | .[]
        | "- !\(.iid) **\(.title)** — \(.source_branch) → \(.target_branch), CI: \(
            (.pipeline // .head_pipeline // {}) | .status // "—"
          )"
      ' > "${S3C_FILE}"
  fi
}

# GitHub Section 3. Same three sub-files, same shape, "#<num>" prefix.
collect_section3_github() {
  ${HAS_GH} || return 0
  local prs_json
  prs_json="$(gh pr list --state=all \
                 --json number,title,author,headRefName,baseRefName,state,createdAt,updatedAt,mergedAt,statusCheckRollup \
                 --limit 100 2>/dev/null || printf '[]')"
  local me="${ME_USERNAME}"
  local start_iso="${WINDOW_START_ISO}"

  # statusCheckRollup is an array of checks; summarize to success/failure/pending/—.
  # Map to a single glyph-ish word for the "checks:" column.
  #   any FAILURE → failure
  #   else any PENDING/QUEUED/IN_PROGRESS → pending
  #   all SUCCESS (and non-empty) → success
  #   empty → —

  # Open — others
  printf '%s' "${prs_json}" | jq -r --arg me "${me}" '
      def rollup: (.statusCheckRollup // []) as $r
        | if ($r | length) == 0 then "—"
          elif any($r[]; (.conclusion // .status) == "FAILURE") then "failure"
          elif any($r[]; (.status // "") == "IN_PROGRESS" or (.status // "") == "QUEUED" or (.conclusion // "") == "PENDING") then "pending"
          elif all($r[]; (.conclusion // .status) == "SUCCESS") then "success"
          else "mixed" end;
      [ .[] | select(.state == "OPEN") | select(.author.login != $me) ] | sort_by(.updatedAt) | reverse
      | .[]
      | "- #\(.number) **\(.title)** — \(.author.login), \(.headRefName) → \(.baseRefName), checks: \(rollup)"
    ' > "${S3A_FILE}"

  # Merged this period
  printf '%s' "${prs_json}" | jq -r --arg start "${start_iso}" '
      [ .[] | select(.state == "MERGED") | select((.mergedAt // "") >= $start) ] | sort_by(.mergedAt) | reverse
      | .[]
      | "- #\(.number) **\(.title)** — \(.author.login), \(.headRefName) → \(.baseRefName), merged \(.mergedAt[:10])"
    ' > "${S3B_FILE}"

  # Open — mine
  if [[ -n "${me}" ]]; then
    printf '%s' "${prs_json}" | jq -r --arg me "${me}" '
        def rollup: (.statusCheckRollup // []) as $r
          | if ($r | length) == 0 then "—"
            elif any($r[]; (.conclusion // .status) == "FAILURE") then "failure"
            elif any($r[]; (.status // "") == "IN_PROGRESS" or (.status // "") == "QUEUED" or (.conclusion // "") == "PENDING") then "pending"
            elif all($r[]; (.conclusion // .status) == "SUCCESS") then "success"
            else "mixed" end;
        [ .[] | select(.state == "OPEN") | select(.author.login == $me) ] | sort_by(.updatedAt) | reverse
        | .[]
        | "- #\(.number) **\(.title)** — \(.headRefName) → \(.baseRefName), checks: \(rollup)"
      ' > "${S3C_FILE}"
  fi
}

# Dispatcher.
collect_section3() {
  case "${FORGE}" in
    gitlab) collect_section3_gitlab ;;
    github) collect_section3_github ;;
    *) return 0 ;;
  esac
}

collect_section4() {
  [[ -z "${MY_EMAIL_REGEX}" ]] && return 0
  # Group by branch, then by date.
  # Strategy: list commits with branches they're on, via `git log --all
  # --source`. %S is the source ref that led to the commit.
  local raw
  raw="$(git log --all --source --since="${SINCE}" \
             --extended-regexp --regexp-ignore-case --author="${MY_EMAIL_REGEX}" \
             --format='%S%x09%h%x09%cI%x09%s' 2>/dev/null || true)"
  [[ -z "${raw}" ]] && return 0

  # Group by branch (first-seen order), then by date within each branch.
  # Skip non-branch refs (stash, notes) and the origin/HEAD symbolic ref.
  printf '%s\n' "${raw}" | awk -F'\t' '
      function simplify(ref) {
        if (ref ~ /^refs\/remotes\//) { sub(/^refs\/remotes\//, "", ref); return ref }
        if (ref ~ /^refs\/heads\//)   { sub(/^refs\/heads\//, "", ref);   return ref }
        return ""
      }
      {
        ref = simplify($1)
        if (ref == "" || ref == "origin/HEAD") next
        sha = $2
        cdate = $3
        day = substr(cdate, 1, 10)
        hhmm = substr(cdate, 12, 5)
        subject = $4
        if (!(ref in branch_seen)) {
          branch_seen[ref] = 1
          nbranches = nbranches + 1
          branches[nbranches] = ref
        }
        key = ref SUBSEP day
        if (!(key in day_seen)) {
          day_seen[key] = 1
          ndays[ref] = ndays[ref] + 1
          days[ref SUBSEP ndays[ref]] = day
        }
        lines[key] = lines[key] sprintf("    - %s `%s` %s\n", hhmm, sha, subject)
      }
      END {
        for (i = 1; i <= nbranches; i++) {
          b = branches[i]
          printf("- **%s**\n", b)
          for (j = 1; j <= ndays[b]; j++) {
            d = days[b SUBSEP j]
            printf("  - %s\n", d)
            printf("%s", lines[b SUBSEP d])
          }
        }
      }'
}

collect_section5_gitlab() {
  ${HAS_GLAB} || return 0
  local mrs_json now_unix
  mrs_json="$(glab mr list --reviewer=@me -F json --per-page 100 2>/dev/null || printf '[]')"
  now_unix="${NOW_UNIX}"
  printf '%s' "${mrs_json}" | jq -r --argjson now "${now_unix}" '
      [ .[] | select(.state == "opened") ] | sort_by(.updated_at) | reverse
      | .[]
      | (((.created_at | fromdateiso8601)) as $c
         | ($now - $c) / 86400 | floor) as $age
      | "- !\(.iid) **\(.title)** — \(.author.name // .author.username), age: \($age) days"
    '
}

collect_section5_github() {
  ${HAS_GH} || return 0
  local prs_json now_unix
  prs_json="$(gh search prs --review-requested=@me --state=open \
                 --json number,title,author,createdAt,repository \
                 --limit 100 2>/dev/null || printf '[]')"
  now_unix="${NOW_UNIX}"
  printf '%s' "${prs_json}" | jq -r --argjson now "${now_unix}" '
      sort_by(.createdAt) | reverse
      | .[]
      | ((.createdAt | fromdateiso8601) as $c
         | ($now - $c) / 86400 | floor) as $age
      | "- #\(.number) **\(.title)** — \(.author.login), age: \($age) days [\(.repository.nameWithOwner)]"
    '
}

collect_section5() {
  case "${FORGE}" in
    gitlab) collect_section5_gitlab ;;
    github) collect_section5_github ;;
    *) return 0 ;;
  esac
}

collect_section6_gitlab() {
  ${HAS_GLAB} || return 0
  ${HAS_DEFAULT_REF} || return 0
  local json
  json="$(glab ci list --ref "${DEFAULT_BRANCH}" --per-page 1 -F json 2>/dev/null \
           || glab pipeline list --ref "${DEFAULT_BRANCH}" --per-page 1 -F json 2>/dev/null \
           || printf '[]')"
  printf '%s' "${json}" | jq -r '
      if (type == "array" and length > 0) then (.[0]) else . end
      | if type == "object" and (.id // null) != null
        then "- #\(.id) \(.status // "unknown") — \((.created_at // "")[:16] | sub("T";" ")) (\(.web_url // "—"))"
        else empty end
    '
}

collect_section6_github() {
  ${HAS_GH} || return 0
  ${HAS_DEFAULT_REF} || return 0
  local json
  json="$(gh run list --branch "${DEFAULT_BRANCH}" --limit 1 \
             --json databaseId,displayTitle,status,conclusion,workflowName,createdAt,url \
             2>/dev/null || printf '[]')"
  printf '%s' "${json}" | jq -r '
      if (type == "array" and length > 0) then (.[0]) else empty end
      | if type == "object" and (.databaseId // null) != null
        then (if (.status == "completed") then (.conclusion // "unknown") else (.status // "unknown") end) as $s
          | "- \(.workflowName) #\(.databaseId) \($s) — \((.createdAt // "")[:16] | sub("T";" ")) (\(.url // "—"))"
        else empty end
    '
}

collect_section6() {
  case "${FORGE}" in
    gitlab) collect_section6_gitlab ;;
    github) collect_section6_github ;;
    *) return 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# Parallel collection
# ---------------------------------------------------------------------------
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t whatsnew)"
trap 'rm -rf "${TMP}"' EXIT

S1_FILE="${TMP}/s1"
S2_FILE="${TMP}/s2"
S3A_FILE="${TMP}/s3a"
S3B_FILE="${TMP}/s3b"
S3C_FILE="${TMP}/s3c"
S4_FILE="${TMP}/s4"
S5_FILE="${TMP}/s5"
S6_FILE="${TMP}/s6"
: > "${S1_FILE}" "${S2_FILE}" "${S3A_FILE}" "${S3B_FILE}" "${S3C_FILE}" \
    "${S4_FILE}" "${S5_FILE}" "${S6_FILE}"

collect_section1 > "${S1_FILE}" 2>"${TMP}/s1.err" &
collect_section2 > "${S2_FILE}" 2>"${TMP}/s2.err" &
collect_section3                2>"${TMP}/s3.err" &
collect_section4 > "${S4_FILE}" 2>"${TMP}/s4.err" &
collect_section5 > "${S5_FILE}" 2>"${TMP}/s5.err" &
collect_section6 > "${S6_FILE}" 2>"${TMP}/s6.err" &
wait

# Propagate any stderr from background jobs as notes.
for f in "${TMP}"/s*.err; do
  [[ -s "${f}" ]] || continue
  while IFS= read -r line; do
    [[ -n "${line}" ]] && note "${line}"
  done < "${f}"
done

# ---------------------------------------------------------------------------
# Counting
# ---------------------------------------------------------------------------
count_lines() {
  if [[ -s "$1" ]]; then
    wc -l < "$1" | tr -d ' '
  else
    printf '0'
  fi
}
# grep -c always writes a number to stdout, but exits 1 on no match, so we
# swallow the exit status; we never want to emit a second value.
grep_count() {
  local pattern="$1" file="$2"
  [[ -s "${file}" ]] || { printf '0'; return; }
  grep -c "${pattern}" "${file}" 2>/dev/null || true
}

N1="$(count_lines "${S1_FILE}")"
N2="$(count_lines "${S2_FILE}")"
N3A="$(count_lines "${S3A_FILE}")"
N3B="$(count_lines "${S3B_FILE}")"
N3C="$(count_lines "${S3C_FILE}")"
N3_TOTAL=$((N3A + N3B + N3C))
N4_BRANCHES="$(grep_count '^- ' "${S4_FILE}")"
N4_COMMITS="$(grep_count '^    - [0-9][0-9]:' "${S4_FILE}")"
N5="$(count_lines "${S5_FILE}")"
N6="$(count_lines "${S6_FILE}")"

TOTAL=$((N1 + N2 + N3_TOTAL + N4_COMMITS + N5 + N6))

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
emit_notes() {
  if [[ ${#NOTES[@]} -gt 0 ]]; then
    printf '%s\n' "${NOTES[@]}"
    printf '\n'
  fi
}

if [[ "${TOTAL}" -eq 0 ]]; then
  emit_notes
  printf 'Nothing new since %s\n' "${WINDOW_START_ISO}"
  exit 0
fi

printf '# What'\''s new in %s\n\n' "${REPO_SLUG}"
printf 'Window: %s → %s (%s)\n\n' "${WINDOW_START_ISO}" "${NOW_ISO}" "${REASON}"
emit_notes

if [[ "${N1}" -gt 0 ]]; then
  printf '## Merged to `%s` (%s)\n' "${DEFAULT_BRANCH}" "${N1}"
  cat "${S1_FILE}"
  printf '\n'
fi

if [[ "${N2}" -gt 0 ]]; then
  printf '## New / updated branches (%s)\n' "${N2}"
  cat "${S2_FILE}"
  printf '\n'
fi

if [[ "${N3_TOTAL}" -gt 0 ]]; then
  printf '## Merge requests\n'
  if [[ "${N3A}" -gt 0 ]]; then
    printf '### Open — others (%s)\n' "${N3A}"
    cat "${S3A_FILE}"
    printf '\n'
  fi
  if [[ "${N3B}" -gt 0 ]]; then
    printf '### Merged this period (%s)\n' "${N3B}"
    cat "${S3B_FILE}"
    printf '\n'
  fi
  if [[ "${N3C}" -gt 0 ]]; then
    printf '### Open — mine (%s)\n' "${N3C}"
    cat "${S3C_FILE}"
    printf '\n'
  fi
fi

if [[ "${N4_COMMITS}" -gt 0 ]]; then
  printf '## My activity (%s commits across %s branches)\n' "${N4_COMMITS}" "${N4_BRANCHES}"
  cat "${S4_FILE}"
  printf '\n'
fi

if [[ "${N5}" -gt 0 ]]; then
  printf '## MRs awaiting my review (%s)\n' "${N5}"
  cat "${S5_FILE}"
  printf '\n'
fi

if [[ "${N6}" -gt 0 ]]; then
  printf '## CI on `%s`\n' "${DEFAULT_BRANCH}"
  cat "${S6_FILE}"
  printf '\n'
fi
