#!/bin/bash
#BSUB -q oversubscribed
#BSUB -G team113-grp
#BSUB -R "select[mem>8000] rusage[mem=8000] span[hosts=1]"
#BSUB -M 8000

################################################################################
# run_pathogen_id.sh - submit the sparki-nf pathogen-identification pipeline
#
# Sections ([edit] = user-editable, [skip] = owned by the script):
#   [skip] FUNCTIONS
#   [skip] FAILURE REPORTING ............. traps that report a setup failure
#   [skip] RESERVED VARIABLES ............ the env-var classes checked below
#   [edit] ENVIRONMENT SETUP ............. SOURCE_ME: a source_me.sh, or "none"
#   [edit] OPT-IN REPORTING .............. website / Slack / cleanup toggles
#   [edit] MANUAL ENVIRONMENT OVERRIDES .. commented exports, one per variable
#   [skip] ENVIRONMENT VALIDATION
#   [edit] RUN CONFIGURATION ............. CONFIG, REVISION, LABEL
#   [skip] FILE SYSTEM SETUP ............. RUN_ID, the lock, log/trace paths
#   [skip] EXECUTION OF THE PIPELINE
#
# Usage 1 - managed (projectify) runs. The dermanager-generated source_me.sh
#   exports everything. Edit nothing; optionally flip the OPT-IN REPORTING
#   toggles.
#     cd <project_dir> && bsub ... < commands/<pipeline>/run_pathogen_id.sh
#
# Usage 2 - git-clone runs (no dermanager source_me.sh). Provide the
#   environment either way:
#     a) set SOURCE_ME="none", then uncomment and fill in MANUAL ENVIRONMENT
#        OVERRIDES; or
#     b) write your own source_me.sh - copy the MANUAL ENVIRONMENT OVERRIDES
#        block into a file, uncomment, fill in - and point SOURCE_ME at it.
#   Then point CONFIG at your own pathogen_id.config, and set the OPT-IN
#   REPORTING toggles to "false" unless you know your cohort's slug,
#   sample-list version and API endpoint.
#
#   This launcher is an additional path, not a replacement: the portable
#   `nextflow run team113sanger/sparki-nf -profile container` usage documented
#   in the README still works and needs none of this.
################################################################################

# -E is required or the ERR trap below is not inherited by functions.
set -Eeuo pipefail

###################
#### FUNCTIONS ####
###################

function require_env() {
  # Check that the given environment variables are set and non-empty. The first
  # argument is a remedy hint printed after the list of missing variables. If
  # any are missing, print an error message and exit with a non-zero status.
  local remedy="$1"
  shift
  local var missing=()
  for var in "$@"; do
    [[ -n "${!var:-}" ]] || missing+=("${var}")
  done
  if (( ${#missing[@]} )); then
    printf 'ERROR: the environment did not provide: %s\n' "${missing[*]}" >&2
    printf '%s\n' "${remedy}" >&2
    exit 1
  fi
}

function normalize_bool() {
  # Canonicalise the named variable to exactly "true" or "false", rewriting it
  # in place so every downstream `== "true"` test - and Utils.envOptIn in the
  # groovy - sees one spelling. An unrecognised value is fatal here, at launch:
  # a typo must not silently pick a side, and it must not fail hours later in
  # onComplete where it is too late to abort.
  local var="$1" val="${!1:-}"
  case "${val,,}" in
    true|t|yes|y|on|1)   printf -v "${var}" '%s' 'true'  ;;
    false|f|no|n|off|0)  printf -v "${var}" '%s' 'false' ;;
    *)
      printf 'ERROR: %s must be a boolean (got: "%s").\n' "${var}" "${val}" >&2
      printf 'Accepted: true/t/yes/y/on/1 or false/f/no/n/off/0, in any case.\n' >&2
      printf 'Set it in your shell before bsub, in source_me.sh, or in the OPT-IN REPORTING section of this script.\n' >&2
      exit 1
      ;;
  esac
}

function check_for_source_me() {
  # Check that the source_me.sh about to be sourced exists and is readable.
  # If not, print an error message and exit with a non-zero status.
  local source_me="${SOURCE_ME:-./source_me.sh}"
  if [[ ! -f "${source_me}" ]]; then
    printf 'ERROR: %s not found (working directory: %s).\n' "${source_me}" "${PWD}" >&2
    printf 'Submit from the project directory, e.g.\n' >&2
    printf '  cd <project_dir> && bsub ... < commands/run_pathogen_id.sh\n' >&2
    printf '  (or go to the https://team113.sanger.ac.uk/dermatlas/cohorts/ page and re-create the run command for this pipeline for this cohort)\n' >&2
    exit 1
  fi
}

function sanitize() {
  # Sanitize a string to be filesystem-safe. Lowercase, whitespace to hyphen, remove all
  # non-alphanumeric (except for hyphens and underscores) characters.
  # printf '%s' rather than echo: echo's trailing newline survives the tr pipeline
  # as a trailing hyphen in every run id.
  local input="${1:-}"
  printf '%s' "${input}" | tr '[:upper:]' '[:lower:]' | tr '[:space:]' '-' | tr -cd '[:alnum:]-_'
}

function truncate_string() {
  # Truncate a string to a maximum length. If the string is longer than the max length,
  # it is truncated to the first max_length characters.
  # (Named truncate_string so it does not shadow the coreutils `truncate` binary.)
  local input="${1:-}"
  local max_length="${2:-}"
  if (( ${#input} > max_length )); then
    printf '%s' "${input:0:max_length}"
  else
    printf '%s' "${input}"
  fi
}

function set_run_id_from_label() {
  # Create a run ID derived from the date+time in an ISO 8601 timestamp but
  # filesystem-safe. A label is required and prepended to the timestamp. The label is
  # sanitized to be filesystem-safe. The format '<LABEL>_YYYYMMDDTHHMMSS'
  local label="${1:-}"
  local timestamp
  if [[ -z "${label}" ]]; then
    printf 'ERROR: set_run_id_from_label requires a label argument\n' >&2
    exit 1
  fi
  timestamp=$(date +'%Y%m%dT%H%M%S')
  local sanitized_label
  sanitized_label=$(sanitize "${label}")
  printf '%s_%s' "${sanitized_label}" "${timestamp}"
}

function set_run_id() {
  # Create a run ID derived from the date+time in an ISO 8601 timestamp but
  # filesystem-safe. If study, project, and cohort are provided (all optional),
  # they are prepended to the timestamp.
  #
  # Cohort strings longer than 40 characters are truncated to the first 40 characters.
  #
  # Cohort strings have whitespace replaced with hyphens and all other
  # non-alphanumeric (except for hyphens and underscores) characters removed.
  #
  # The format '<STUDY>_<PROJECT>_<COHORT>_YYYYMMDDTHHMMSS'
  local study="${1:-}"
  local project="${2:-}"
  local cohort="${3:-}"
  local timestamp
  timestamp=$(date +'%Y%m%dT%H%M%S')
  if [[ -n "${study}" ]]; then
    study="${study}_"
  fi
  if [[ -n "${project}" ]]; then
    project="${project}_"
  fi
  if [[ -n "${cohort}" ]]; then
    local sanitized_cohort
    sanitized_cohort=$(sanitize "${cohort}")
    cohort="$(truncate_string "${sanitized_cohort}" 40)_"
  fi
  printf '%s%s%s%s' "${study}" "${project}" "${cohort}" "${timestamp}"
}

function json_escape() {
  # Escape a string for embedding in a JSON string literal: backslash, quote and
  # newline. Kept as a helper rather than inlined so the Slack payload below has
  # exactly one escaping implementation to review.
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "${s}"
}

function slack_safe() {
  # Slack parses <...> as a link, so no value in a message may carry angle
  # brackets. Replace them with round brackets rather than dropping them.
  local s="${1:-}"
  s="${s//</(}"
  s="${s//>/)}"
  printf '%s' "${s}"
}

function post_slack_message() {
  # POST a plain-text Slack message. Never fatal: always returns 0, and the
  # caller runs under `set +e` anyway, so nothing here can change the exit
  # status the launcher is reporting.
  local text="$1"
  local payload
  payload="{\"text\": \"$(json_escape "${text}")\"}"
  # The payload is passed as a single argument rather than interpolated into a
  # shell string that would be re-parsed with the webhook URL in it.
  curl -sS -X POST -H 'Content-type: application/json' \
       --max-time 20 \
       --data "${payload}" \
       "${SLACK_WEBHOOK_URL}" >/dev/null 2>&1 || true
  return 0
}

function pipeline_dir_flock_scope() {
  # Report whether a flock taken under PIPELINE_DIR is cluster-wide or only
  # node-local. Lustre mounted with localflock/noflock, and NFS with
  # local_lock=, give a lock that excludes nothing on another node. This only
  # ever warns: the launcher continues either way. (A process that *deletes*
  # data on the strength of the lock - an external work-dir pruner - must fail
  # closed on this check instead.)
  local dir="${1:-}"
  local fstype options
  if ! command -v findmnt >/dev/null 2>&1; then
    printf 'unknown'
    return 0
  fi
  fstype="$(findmnt -n -o FSTYPE --target "${dir}" 2>/dev/null || printf '')"
  options="$(findmnt -n -o OPTIONS --target "${dir}" 2>/dev/null || printf '')"
  case "${fstype}" in
    lustre)
      if [[ "${options}" == *localflock* || "${options}" == *noflock* ]]; then
        printf 'node-local'
      else
        printf 'cluster-wide'
      fi
      ;;
    nfs|nfs4)
      if [[ "${options}" == *local_lock=all* || "${options}" == *local_lock=flock* ]]; then
        printf 'node-local'
      else
        printf 'cluster-wide'
      fi
      ;;
    '') printf 'unknown' ;;
    *)  printf 'node-local' ;;
  esac
  return 0
}

function lock_holder_description() {
  # Read the identity line the current holder wrote into the lock file, for the
  # contention error message. Sanitised for Slack.
  local file="${1:-}"
  local line=''
  if [[ -r "${file}" ]]; then
    line="$(tail -n 1 "${file}" 2>/dev/null || printf '')"
  fi
  if [[ -z "${line}" ]]; then
    line='no identity recorded'
  fi
  slack_safe "${line}"
}

function acquire_pipeline_lock() {
  # One launcher owns PIPELINE_DIR at a time. Two concurrent submissions of one
  # cohort otherwise share one work/, and the first to finish deletes it under
  # the second.
  #
  # The lock lives on the open file description, so the kernel drops it when
  # this process dies however it dies - there is no release path and no
  # stale-lock cleanup. The fd is inherited by `nextflow run` on purpose: an
  # orphaned nextflow still owns the directory.
  local scope
  scope="$(pipeline_dir_flock_scope "${PIPELINE_DIR}")"
  if [[ "${scope}" == "node-local" ]]; then
    printf 'WARNING: %s is on a filesystem whose flock is node-local; concurrent runs on other hosts will not be excluded.\n' \
      "${PIPELINE_DIR}" >&2
  fi

  # Refuse anything that is not a plain file at the lock path: a symlink or a
  # fifo planted here would redirect the lock, or the identity write, elsewhere.
  if [[ -e "${LOCK_FILE}" || -L "${LOCK_FILE}" ]]; then
    if [[ -L "${LOCK_FILE}" || ! -f "${LOCK_FILE}" ]]; then
      printf 'ERROR: %s exists and is not a regular file; refusing to lock.\n' "${LOCK_FILE}" >&2
      exit 1
    fi
  fi

  # >> and never >: > truncates on open, destroying a live holder's identity
  # line before flock has even reported the loss.
  exec {_LOCK_FD}>>"${LOCK_FILE}"

  # -E 75 is outside flock's own sysexits range (64-71), so "another run holds
  # it" can never be confused with "flock itself failed".
  # Captured with `|| rc=$?` rather than `if ! flock ...; then rc=$?`: after a
  # negated command $? is the *negation*, i.e. 0, which would report every
  # contention as "flock itself failed (status 0)" and exit 0 - letting a second
  # run continue into a directory it does not own.
  local rc=0
  flock -n -E "${_LOCK_CONFLICT_RC}" "${_LOCK_FD}" || rc=$?
  if (( rc != 0 )); then
    if (( rc == _LOCK_CONFLICT_RC )); then
      _LAUNCHER_EXTRA_NOTE="another run holds ${LOCK_FILE}: $(lock_holder_description "${LOCK_FILE}")"
      printf 'ERROR: %s\n' "${_LAUNCHER_EXTRA_NOTE}" >&2
      printf 'Wait for it to finish, or submit against a different project directory.\n' >&2
    else
      printf 'ERROR: flock failed on %s (status %s). This is not lock contention.\n' "${LOCK_FILE}" "${rc}" >&2
    fi
    exit "${rc}"
  fi

  # Nothing may ever unlink .lock - the next run would lock a fresh inode and
  # exclude nobody. Re-validate that the fd we hold is still the file at the
  # path; a mismatch means it was replaced mid-acquisition.
  local fd_id path_id
  fd_id="$(stat -Lc '%d:%i' "/proc/self/fd/${_LOCK_FD}" 2>/dev/null || printf 'fd-unknown')"
  path_id="$(stat -c '%d:%i' "${LOCK_FILE}" 2>/dev/null || printf 'path-unknown')"
  if [[ "${fd_id}" != "${path_id}" ]]; then
    printf 'ERROR: %s was replaced while being locked (%s != %s); refusing to continue.\n' \
      "${LOCK_FILE}" "${fd_id}" "${path_id}" >&2
    exit 1
  fi

  # The held fd is O_APPEND, so the identity line goes through a separate
  # truncating open - done under the lock, so two runs cannot interleave.
  printf 'run_id=%s pid=%s host=%s lsf_job=%s revision=%s flock_scope=%s started=%s\n' \
    "${RUN_ID}" "$$" "$(hostname -s 2>/dev/null || printf 'unknown')" \
    "${LSB_JOBID:-none}" "${REVISION}" "${scope}" "$(date -Is)" \
    > "${LOCK_FILE}"

  # Set only after every failure path above is passed: it gates the sentinel
  # writer, and a run that lost the race must not write a verdict.
  _HOLDS_PIPELINE_LOCK=1

  # From here until the exit trap neither sentinel exists, which a pruner must
  # read as "in progress, or died without a verdict - do not touch".
  rm -f "${PIPELINE_DIR}/.completed_successfully" "${PIPELINE_DIR}/.completed_with_error"
}

function write_completion_sentinel() {
  # Record this run's verdict for machines (an external work-dir pruner) and
  # humans. The *filename* is the state; the contents are an audit line no
  # pruning decision should parse.
  #
  # Guarded by _HOLDS_PIPELINE_LOCK: a run that lost the flock race exits 75 and
  # still reaches its EXIT trap, and writing .completed_with_error there would
  # declare the *live* run failed and invite the pruner to delete its work dir.
  local status="${1:-1}"
  [[ "${_HOLDS_PIPELINE_LOCK:-0}" == "1" ]] || return 0
  [[ -n "${PIPELINE_DIR:-}" ]] || return 0

  local outcome file
  if (( status == 0 )); then
    outcome='success'
    file="${PIPELINE_DIR}/.completed_successfully"
  elif (( status >= 128 )); then
    # bkill, MEMLIMIT, RUNLIMIT.
    outcome='killed'
    file="${PIPELINE_DIR}/.completed_with_error"
  else
    outcome='failed'
    file="${PIPELINE_DIR}/.completed_with_error"
  fi

  # Exactly one verdict exists, and a symlink planted at the path is dropped
  # rather than written through. One printf - one write - so a reader sees the
  # file absent or whole.
  rm -f "${PIPELINE_DIR}/.completed_successfully" "${PIPELINE_DIR}/.completed_with_error"
  printf 'outcome=%s\nexit_status=%s\nrun_id=%s\nrevision=%s\nfinished=%s\nlsf_job_id=%s\nlsf_job_name=%s\nhost=%s\nwork_dir=%s\nwork_dir_disposition=%s\n' \
    "${outcome}" "${status}" "${RUN_ID:-unknown}" "${REVISION:-unknown}" "$(date -Is)" \
    "${LSB_JOBID:-none}" "${LSB_JOBNAME:-none}" "$(hostname -s 2>/dev/null || printf 'unknown')" \
    "${NXF_WORK:-unknown}" "${_WORK_DIR_DISPOSITION:-unknown}" \
    > "${file}" 2>/dev/null || true
  return 0
}

function work_dir_is_ours() {
  # NXF_WORK must be the work dir this launcher created, not one inherited from
  # the submitting environment. The non-empty PIPELINE_DIR test keeps ""/work
  # from matching.
  [[ -n "${PIPELINE_DIR:-}" ]] || return 1
  [[ -n "${NXF_WORK:-}" ]] || return 1
  [[ "${NXF_WORK}" == "${PIPELINE_DIR}/work" ]] || return 1
  return 0
}

function cleanup_work_dir() {
  # Delete ${NXF_WORK} and nothing else - tmp/, clones/, logs/, traces/, stats/
  # and the published results all stay. Only ever called on a successful run:
  # a failed run's work dir is its -resume state and its debugging evidence.
  #
  # This is safe only because publishDir has already *copied* the keepers out
  # (params.publish_dir_mode = 'copy' in nextflow.config). A pipeline that
  # publishes by symlink would lose its results here.
  if ! work_dir_is_ours; then
    _WORK_DIR_DISPOSITION='not-removed-refused'
    printf 'NOTE: NXF_WORK (%s) does not belong to this launcher; not removing it.\n' \
      "${NXF_WORK:-unset}" >&2
    return 0
  fi
  if [[ ! -d "${NXF_WORK}" ]]; then
    _WORK_DIR_DISPOSITION='absent'
    return 0
  fi
  if [[ "${DERMATLAS_CLEANUP_WORK_DIR:-}" != "true" ]]; then
    _WORK_DIR_DISPOSITION='kept-opted-out'
    printf 'Work directory kept (DERMATLAS_CLEANUP_WORK_DIR=false): %s\n' "${NXF_WORK}"
    return 0
  fi
  if rm -rf "${NXF_WORK}"; then
    _WORK_DIR_DISPOSITION='removed'
    printf 'Work directory removed: %s\n' "${NXF_WORK}"
  else
    _WORK_DIR_DISPOSITION='partially-removed'
    printf 'WARNING: failed to fully remove %s\n' "${NXF_WORK}" >&2
  fi
  return 0
}

function pipeline_wall_seconds() {
  # Wall time of `nextflow run` only - not of the launcher. Empty if the run
  # never started. A multi-day run can outlive an NTP step, so a negative delta
  # is clamped to 0 rather than reported.
  [[ -n "${_PIPELINE_START_EPOCH:-}" ]] || return 0
  local now delta
  now="$(date +%s)"
  delta=$(( now - _PIPELINE_START_EPOCH ))
  (( delta < 0 )) && delta=0
  printf '%s' "${delta}"
}

function measure_work_dir() {
  # One walk, not two du's: %b is st_blocks, so this yields allocated bytes and
  # the inode count from a single traversal - on Lustre the traversal is the
  # whole cost. Symlinks are not followed; hardlinks count per link.
  #
  # `set -o pipefail` is set *inside* the command substitution: outside, PIPESTATUS
  # would describe the assignment, and a find that died mid-walk would leave awk
  # printing a partial total that reads exactly like a real one.
  work_dir_is_ours || return 0
  [[ -d "${NXF_WORK}" ]] || return 0
  local out
  out="$(set -o pipefail; find "${NXF_WORK}" -xdev -printf '%b\n' 2>/dev/null \
          | awk '{blocks+=$1; files++} END {printf "%.0f %d", blocks*512, files}')" || return 0
  [[ -n "${out}" ]] || return 0
  _WORK_DIR_BYTES="${out%% *}"
  _WORK_DIR_INODES="${out##* }"
  return 0
}

function human_duration() {
  local total="${1:-}" h m s
  [[ -n "${total}" ]] || return 0
  h=$(( total / 3600 )); m=$(( (total % 3600) / 60 )); s=$(( total % 60 ))
  printf '%dh %02dm %02ds' "${h}" "${m}" "${s}"
}

function human_bytes() {
  local b="${1:-}"
  [[ -n "${b}" ]] || return 0
  awk -v b="${b}" 'BEGIN {
    split("B KiB MiB GiB TiB PiB", u, " ");
    i = 1; while (b >= 1024 && i < 6) { b /= 1024; i++ }
    printf (i == 1 ? "%d %s" : "%.2f %s"), b, u[i]
  }'
}

function human_count() {
  local n="${1:-}"
  [[ -n "${n}" ]] || return 0
  awk -v n="${n}" 'BEGIN {
    if (n >= 1000000) printf "%.1f million", n/1000000;
    else if (n >= 1000) printf "%.1f thousand", n/1000;
    else printf "%d", n
  }'
}

function write_resource_stats() {
  # key=value, with the human-readable conversions as # comments on their own
  # lines, so `value="${line#*=}"` stays a valid reader.
  #
  # An unmeasurable figure is omitted, never written as 0: a missing key cannot
  # be silently summed into a cost estimate.
  [[ -n "${STATS_FILE:-}" ]] || return 0
  {
    printf 'run_id=%s\n' "${RUN_ID:-unknown}"
    printf 'revision=%s\n' "${REVISION:-unknown}"
    if [[ -n "${_PIPELINE_WALL_SECONDS:-}" ]]; then
      printf '# wall_time: %s (`nextflow run` only)\n' "$(human_duration "${_PIPELINE_WALL_SECONDS}")"
      printf 'wall_time=%s\n' "${_PIPELINE_WALL_SECONDS}"
    fi
    if [[ -n "${_WORK_DIR_BYTES:-}" ]]; then
      printf '# disk_usage: %s allocated\n' "$(human_bytes "${_WORK_DIR_BYTES}")"
      printf 'disk_usage=%s\n' "${_WORK_DIR_BYTES}"
    fi
    if [[ -n "${_WORK_DIR_INODES:-}" ]]; then
      printf '# disk_inodes: %s\n' "$(human_count "${_WORK_DIR_INODES}")"
      printf 'disk_inodes=%s\n' "${_WORK_DIR_INODES}"
    fi
  } > "${STATS_FILE}" 2>/dev/null || true
  return 0
}

function report_launcher_failure() {
  # Graceful degradation, in order: stderr always (it lands in the LSF job
  # output, so a setup failure is never fully silent); then Slack, only if the
  # trap has been armed AND the toggle says true AND a webhook is set AND curl
  # is on PATH. Each skip prints a NOTE: naming the condition that failed.
  #
  # Always returns 0, and the handler runs with `set +e`, so nothing here can
  # change the exit status being reported.
  local status="$1"

  # Identity: the environment's cohort if it got that far, else the user's
  # LABEL, else a literal. BASH_SOURCE[0] is deliberately not reported - LSF
  # spools this script to a transient ~/.lsbatch/<jobid> copy, so it names
  # nothing a reader can find. LSF's own values identify the submission.
  local cohort="${COHORT_SLUG:-}"
  [[ -n "${cohort}" ]] || cohort="${LABEL:-}"
  [[ -n "${cohort}" ]] || cohort='unknown-cohort'

  local slug="${PIPELINE_SLUG:-unset}"
  local rev="${REVISION:-unset}"

  local -a lines=()
  lines+=("${_LAUNCHER_LABEL} failed before the pipeline started.")
  lines+=("cohort: $(slack_safe "${cohort}")")
  lines+=("study: $(slack_safe "${STUDY:-unset}")  project: $(slack_safe "${PROJECT:-unset}")")
  lines+=("pipeline: $(slack_safe "${slug}") ($(slack_safe "${rev}"))")
  lines+=("exit status: ${status}")
  lines+=("failing command: $(slack_safe "${_ERR_COMMAND:-unknown}") (line ${_ERR_LINENO:-unknown})")
  [[ -n "${_LAUNCHER_EXTRA_NOTE:-}" ]] && lines+=("note: $(slack_safe "${_LAUNCHER_EXTRA_NOTE}")")
  [[ -n "${RUN_ID:-}" ]] && lines+=("run id: $(slack_safe "${RUN_ID}")")
  if [[ -n "${NXF_PULL_LOG_FILE:-}" && -f "${NXF_PULL_LOG_FILE}" ]]; then
    lines+=("pull log: $(slack_safe "${NXF_PULL_LOG_FILE}")")
  fi
  lines+=("host: $(hostname -s 2>/dev/null || printf 'unknown')")
  lines+=("lsf job: ${LSB_JOBID:-none} ${LSB_JOBNAME:-}")
  [[ -n "${LS_SUBCWD:-}" ]] && lines+=("submitted from: $(slack_safe "${LS_SUBCWD}")")

  local text
  text="$(printf '%s\n' "${lines[@]}")"

  printf '%s\n' "${text}" >&2

  if [[ "${_TRAP_CAN_SLACK:-0}" != "1" ]]; then
    printf 'NOTE: failure occurred before the reporting toggles were resolved; no Slack message sent.\n' >&2
    return 0
  fi
  if [[ "${DERMATLAS_SLACK_NOTIFICATIONS:-}" != "true" ]]; then
    printf 'NOTE: DERMATLAS_SLACK_NOTIFICATIONS is not true; no Slack message sent.\n' >&2
    return 0
  fi
  if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
    printf 'NOTE: SLACK_WEBHOOK_URL is unset; no Slack message sent.\n' >&2
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    printf 'NOTE: curl is not on PATH; no Slack message sent.\n' >&2
    return 0
  fi
  post_slack_message "${text}"
  return 0
}

function on_launcher_exit() {
  # The EXIT trap does the reporting, not the ERR trap: doing it here means an
  # explicit `exit 1` (from require_env, say) is reported too, just without a
  # failing command to name.
  local status="$1"
  # Never re-enter. set +e AND set +u: under set -u an unset reference kills the
  # shell even with set +e, which would mask the real status with a second,
  # different failure.
  trap - EXIT ERR INT TERM HUP
  set +e
  set +u

  if (( status != 0 )); then
    # The verdict goes on disk before the human report: reporting can hang on
    # curl or be cut short by a second signal.
    _WORK_DIR_DISPOSITION='kept-failed-run'
    write_completion_sentinel "${status}"
    report_launcher_failure "${status}"
  else
    write_completion_sentinel 0
  fi
  exit "${status}"
}

function on_pipeline_exit() {
  # Installed in place of on_launcher_exit immediately before `nextflow run`.
  # From that point onComplete owns *reporting* - a run that starts must be
  # reported exactly once, and this handler reports nothing. The launcher still
  # owns the lifecycle: stats, cleanup, sentinel.
  local status="$1"
  trap - EXIT ERR INT TERM HUP
  set +e
  set +u

  if (( status == 0 )); then
    # Order matters: wall seconds first (the walk is not run time), then
    # measure, then write the stats, and only then cleanup - after the rm -rf
    # there is nothing left to measure.
    _PIPELINE_WALL_SECONDS="$(pipeline_wall_seconds)"
    measure_work_dir
    write_resource_stats
    cleanup_work_dir
  else
    # A failed or killed run keeps its work dir; the toggle is not consulted.
    # No stats file either - it kept its work dir anyway.
    _WORK_DIR_DISPOSITION='kept-failed-run'
  fi

  write_completion_sentinel "${status}"
  exit "${status}"
}

##########################
#### FAILURE REPORTING ###
##########################

# Installed here, right after the functions they call, so everything downstream
# is covered. The ERR trap only records context; the EXIT trap reports.
#
# The trap arms in two stages: SLACK_WEBHOOK_URL and the toggles only exist
# after source_me.sh and the OPT-IN section, so until _TRAP_CAN_SLACK=1 is set
# at the end of OPT-IN REPORTING the trap reports to stderr only. A user who has
# opted out of Slack must never receive a Slack message, so "toggle not yet
# known" degrades to silence, never to a default of true.
_ERR_COMMAND=""
_ERR_LINENO=""
trap '_ERR_COMMAND="${BASH_COMMAND}"; _ERR_LINENO="${LINENO}"' ERR
trap 'on_launcher_exit $?' EXIT
# Route LSF kills (bkill, run/memory limits) through the same EXIT trap.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

############################
#### RESERVED VARIABLES ####
############################
_DEFAULT_PIPELINE_SLUG="pathogen_pipe"
_DEFAULT_SOURCE_ME="./source_me.sh"
_LAUNCHER_LABEL="Sparki pathogen-identification launcher"

# Environment variables checked after sourcing source_me.sh, by class:
#  - pipeline-essential: always required to run the pipeline at all.
#  - website-essential:  required only when DERMATLAS_WEBSITE_LOGGING=true.
#  - slack-essential:    required only when DERMATLAS_SLACK_NOTIFICATIONS=true.
# The two sample lists are contract because the asset config interpolates them:
# Kraken2 runs over every BAM, and each subcohort's SPARKI run is restricted to
# the samples its list names. `metadata` and `samples_to_remove` remain optional
# workflow inputs, not contract.
_PIPELINE_ENV_VARS=(PROJECT_DIR COMMANDS_DIR ANALYSIS_DIR BAMS_DIR STUDY PROJECT \
                RNA_SAMPLE_LIST_ONE_PER_PATIENT RNA_SAMPLE_LIST_FINAL_DECISION)
_WEBSITE_ENV_VARS=(COHORT_SLUG SAMPLE_LIST_VERSION_FILE SELF_DESCRIBING_API)
_SLACK_ENV_VARS=(SLACK_WEBHOOK_URL)

# An undocumented per-run escape hatch for the dermanager slug.
PIPELINE_SLUG="${PATHOGEN_ID_PIPELINE_SLUG:-${_DEFAULT_PIPELINE_SLUG}}"

# Toggle defaults, and a snapshot of whatever the submitting shell already set,
# taken *before* source_me.sh so precedence can be resolved afterwards.
_DEFAULT_WEBSITE_LOGGING="true"
_DEFAULT_SLACK_NOTIFICATIONS="true"
_DEFAULT_CLEANUP_WORK_DIR="true"
_ENV_WEBSITE_LOGGING="${DERMATLAS_WEBSITE_LOGGING:-}"
_ENV_SLACK_NOTIFICATIONS="${DERMATLAS_SLACK_NOTIFICATIONS:-}"
_ENV_CLEANUP_WORK_DIR="${DERMATLAS_CLEANUP_WORK_DIR:-}"

# Everything the traps read is declared here, before any trap can fire, so
# set -u cannot turn a trap into a second, different failure.
_TRAP_CAN_SLACK=0
LOCK_FILE=""
_LOCK_FD=""
_HOLDS_PIPELINE_LOCK=0
_LOCK_CONFLICT_RC=75
_WORK_DIR_DISPOSITION="kept"
_LAUNCHER_EXTRA_NOTE=""
STATS_DIR=""
STATS_FILE=""
_PIPELINE_START_EPOCH=""
_PIPELINE_WALL_SECONDS=""
_WORK_DIR_BYTES=""
_WORK_DIR_INODES=""
NXF_PULL_LOG_FILE=""
NXF_RUN_LOG_FILE=""
RUN_ID=""
REVISION=""
PIPELINE_DIR=""

###########################
#### ENVIRONMENT SETUP ####
###########################

# Path to the environment file, or "none" to skip sourcing and rely on
# MANUAL ENVIRONMENT OVERRIDES below.
SOURCE_ME=${SOURCE_ME:-"${_DEFAULT_SOURCE_ME}"}
if [[ "${SOURCE_ME}" != "none" ]]; then
  check_for_source_me
  source "${SOURCE_ME}"             # Most of the environment variables are set here
fi

############################
#### OPT-IN REPORTING   ####
############################

# Set to "false" to opt out. Opted-out (and stub) runs make no network calls.
#
# Precedence: the submitting shell wins over source_me.sh, which wins over the
# in-script default - so a one-off run can opt out with a plain
# `export DERMATLAS_CLEANUP_WORK_DIR=false` before bsub, without editing this
# script or a shared source_me.sh.
DERMATLAS_WEBSITE_LOGGING="${_ENV_WEBSITE_LOGGING:-${DERMATLAS_WEBSITE_LOGGING:-${_DEFAULT_WEBSITE_LOGGING}}}"
DERMATLAS_SLACK_NOTIFICATIONS="${_ENV_SLACK_NOTIFICATIONS:-${DERMATLAS_SLACK_NOTIFICATIONS:-${_DEFAULT_SLACK_NOTIFICATIONS}}}"
DERMATLAS_CLEANUP_WORK_DIR="${_ENV_CLEANUP_WORK_DIR:-${DERMATLAS_CLEANUP_WORK_DIR:-${_DEFAULT_CLEANUP_WORK_DIR}}}"

normalize_bool DERMATLAS_WEBSITE_LOGGING
normalize_bool DERMATLAS_SLACK_NOTIFICATIONS
normalize_bool DERMATLAS_CLEANUP_WORK_DIR
export DERMATLAS_WEBSITE_LOGGING DERMATLAS_SLACK_NOTIFICATIONS DERMATLAS_CLEANUP_WORK_DIR

printf 'Dermatlas website logging:      %s\n' "${DERMATLAS_WEBSITE_LOGGING}"
printf 'Dermatlas Slack notifications:  %s\n' "${DERMATLAS_SLACK_NOTIFICATIONS}"
printf 'Clean up work dir on success:   %s\n' "${DERMATLAS_CLEANUP_WORK_DIR}"

# Arm the trap's Slack channel: the toggles and the webhook are known from here.
_TRAP_CAN_SLACK=1

######################################
#### MANUAL ENVIRONMENT OVERRIDES ####
######################################

# The full environment contract, one commented export per variable. Uncomment
# and fill in to run without a source_me.sh (SOURCE_ME="none") or to override
# individual values - anything exported here wins over source_me.sh. To write
# your own source_me.sh instead, copy this block into a file and point
# SOURCE_ME at it.
#
# Pipeline-essential (always required):
# export PROJECT_DIR=""    # e.g. "/lustre/scratch127/.../<my_project>"; the pipeline's work/log/trace dirs are created under it
# export COMMANDS_DIR=""   # e.g. "${PROJECT_DIR}/commands"; CONFIG below defaults to living beneath it
# export ANALYSIS_DIR=""   # e.g. "${PROJECT_DIR}/analysis"; results land in ${ANALYSIS_DIR}/pathogen_id (config: outdir)
# export BAMS_DIR=""       # e.g. "${PROJECT_DIR}/bams"; the config globs ${BAMS_DIR}/**.bam (config: bam_files)
# export STUDY=""          # e.g. "6740"; part of the run id
# export PROJECT=""        # e.g. "3016"; part of the run id
# export RNA_SAMPLE_LIST_ONE_PER_PATIENT=""  # e.g. "${PROJECT_DIR}/metadata/<cohort>_one_samp_ppat_sampnames.tsv"; the "one_per_patient" subcohort (config: subcohorts)
# export RNA_SAMPLE_LIST_FINAL_DECISION=""   # e.g. "${PROJECT_DIR}/metadata/<cohort>_final_decision_sampnames.tsv"; the "final_decision" subcohort (config: subcohorts)
#
# Website-essential (required only when DERMATLAS_WEBSITE_LOGGING="true"):
# export COHORT_SLUG=""              # e.g. "m10-cutaneous-mixed-tumour"; keys the analysis-log record
# export SAMPLE_LIST_VERSION_FILE="" # e.g. "${PROJECT_DIR}/metadata/VERSION"; a file holding one integer >= 1
# export SELF_DESCRIBING_API=""      # e.g. "https://team113.sanger.ac.uk/api/v1/resolve/"; dermatlas-http --api endpoint
#
# Slack-essential (required only when DERMATLAS_SLACK_NOTIFICATIONS="true"):
# export SLACK_WEBHOOK_URL=""        # e.g. "https://hooks.slack.com/services/T000/B000/XXXX"
#
# Optional workflow inputs (not contract; unset simply means unset):
# export SPARKI_METADATA=""                # e.g. "${PROJECT_DIR}/metadata/samples.csv"  (config: metadata)
# export SPARKI_METADATA_SAMPLE_COLUMN=""  # e.g. "sample"                               (config: metadata_sample_column)
# export SPARKI_METADATA_COLUMNS=""        # e.g. "tumour_type,site"                     (config: metadata_columns)
# export SPARKI_SAMPLES_TO_REMOVE=""       # e.g. "${PROJECT_DIR}/metadata/rejected_samples.list" (config: samples_to_remove)
#
# The DERMATLAS_* toggles are deliberately not listed here: OPT-IN REPORTING
# above has already resolved them.

################################
#### ENVIRONMENT VALIDATION ####
################################

require_env 'Regenerate source_me.sh with a dermanager version that exports these variables (or export them yourself if you git-cloned the pipeline).' \
            "${_PIPELINE_ENV_VARS[@]}"
if [[ "${DERMATLAS_WEBSITE_LOGGING}" == "true" ]]; then
  require_env 'Needed because DERMATLAS_WEBSITE_LOGGING=true. Fix source_me.sh, or set DERMATLAS_WEBSITE_LOGGING="false" in this script to opt out of website logging.' \
              "${_WEBSITE_ENV_VARS[@]}"
fi
if [[ "${DERMATLAS_SLACK_NOTIFICATIONS}" == "true" ]]; then
  require_env 'Needed because DERMATLAS_SLACK_NOTIFICATIONS=true. Fix source_me.sh, or set DERMATLAS_SLACK_NOTIFICATIONS="false" in this script to opt out of Slack notifications.' \
              "${_SLACK_ENV_VARS[@]}"
fi

###########################
#### RUN CONFIGURATION ####
###########################

# Nextflow config for this run; git-clone runs point this at their own copy.
CONFIG="${COMMANDS_DIR}/${PIPELINE_SLUG}/pathogen_id.config"
# Pipeline version to run: a tag or commit hash. Maintained by .update-version.sh.
REVISION="1.0.1"
# Optional. If set, RUN_ID becomes <label>_<timestamp> instead of
# <study>_<project>_<cohort>_<timestamp>.
LABEL=""

###########################
#### FILE SYSTEM SETUP ####
###########################

# The launcher owns the run's identity and the pipeline directory's lifecycle.
PIPELINE_DIR="${PROJECT_DIR}/${PIPELINE_SLUG}"
mkdir -p "${PIPELINE_DIR}"

# RUN_ID is computed above the lock, so the lock file and the sentinels can name
# the run.
if [[ -n "${LABEL:-}" ]]; then
  RUN_ID="$(set_run_id_from_label "${LABEL}")"
else
  RUN_ID="$(set_run_id "${STUDY:-}" "${PROJECT:-}" "${COHORT_SLUG:-}")"
fi
# One id names every artifact of this run: the run and pull logs,
# execution_trace-<RUN_ID>.txt, execution_report-<RUN_ID>.html,
# resource-stats-<RUN_ID>.txt, and the run reference in Slack messages.
# Exported so the pipeline's nextflow.config and onComplete handler can read it.
export RUN_ID

# Acquire the lock before anything under PIPELINE_DIR is written.
LOCK_FILE="${PIPELINE_DIR}/.lock"
acquire_pipeline_lock

# Set isolated Nextflow directories
export NXF_WORK="${PIPELINE_DIR}/work"
export NXF_TEMP="${PIPELINE_DIR}/tmp"
mkdir -p "${NXF_WORK}" "${NXF_TEMP}"

# One clone per revision. The shared default at ${NXF_HOME}/assets is checked out
# in place by every pull and run, so parallel runs on different revisions clobber
# each other, and a first pull of a newly published tag can fail with
# "Cannot find revision".
export NXF_ASSETS="${PIPELINE_DIR}/clones/${REVISION}"

# Pinned because an LSF job inherits the submitter's profile, and because
# Nextflow's default cache lives *under* work/, which the cleanup deletes.
# Must match singularity.cacheDir in the farm22 profile of nextflow.config.
export NXF_SINGULARITY_CACHEDIR="/lustre/scratch127/casm/projects/dermatlas/singularity_images"

# One log per nextflow command. NXF_LOG_FILE applies to *every* nextflow
# invocation and Nextflow rotates an existing log to <name>.1 at startup, so a
# single exported value would leave the run's log plus a .log.1 (the pull) that
# reads like a rerun. Set, never exported: each command is prefixed instead, which
# is what puts NXF_LOG_FILE in that process's environment for
# Utils.resolveNextflowLog to read back in onComplete.
LOG_DIR="${PIPELINE_DIR}/logs"
NXF_RUN_LOG_FILE="${LOG_DIR}/nextflow-run-${RUN_ID}.log"
NXF_PULL_LOG_FILE="${LOG_DIR}/nextflow-pull-${RUN_ID}.log"

# Directory for this run's execution trace and report; consumed by nextflow.config.
export TRACE_DIR="${PIPELINE_DIR}/traces"

# Made here, not in the trap: a mkdir that fails inside a trap is a second,
# harder failure.
STATS_DIR="${PIPELINE_DIR}/stats"
STATS_FILE="${STATS_DIR}/resource-stats-${RUN_ID}.txt"
mkdir -p "${LOG_DIR}" "${TRACE_DIR}" "${STATS_DIR}"

###################################
#### EXECUTION OF THE PIPELINE ####
###################################

# Load module dependencies
module load nextflow-23.10.0
module load /software/modules/ISG/singularity/3.11.4

# Change to pipeline directory so .nextflow.log goes here
cd "${PIPELINE_DIR}"

NXF_LOG_FILE="${NXF_PULL_LOG_FILE}" \
  nextflow pull "https://github.com/team113sanger/sparki-nf" -r "${REVISION}"

# Hand the traps over - never a bare `trap -`. Re-arming the signal traps is
# mandatory: for an untrapped fatal signal bash runs the EXIT trap with $? from
# the last *completed* command, so a bkill/MEMLIMIT/RUNLIMIT during
# `nextflow run` would arrive as status 0, a killed run would read as
# successful, and the cleanup would delete its work directory. The 128+n
# re-raise makes it the failure it is.
trap - EXIT ERR INT TERM HUP
trap 'on_pipeline_exit $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Taken after the modules and the pull, so wall time measures `nextflow run` only.
_PIPELINE_START_EPOCH="$(date +%s)"

NXF_LOG_FILE="${NXF_RUN_LOG_FILE}" \
  nextflow run "https://github.com/team113sanger/sparki-nf" \
  -resume \
  -c "${CONFIG}" \
  -r "${REVISION}" \
  -profile farm22 \
  -work-dir "${NXF_WORK}"
