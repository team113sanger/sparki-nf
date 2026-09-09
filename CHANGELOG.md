# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Keywords

As of the next release (see [Unreleased] below) the following *keywords* are used at
the start of each changelog entry to indicate the impact of the change:

- **REPRODUCIBILITY** - a change to the pipeline's scientific processing that
  may cause the same input data to produce different scientific outputs or
  results, including changes to algorithms, tolerances, randomisation,
  scientific functionality, or output formats.
- **ROBUSTNESS** - a fix or improvement to the pipeline's scientific
  functionality that improves correctness, reliability, or the range of inputs
  that can be processed, without intentionally changing the scientific results
  of an equivalent successful analysis.
- **INTEGRATION** - a change to how the pipeline integrates with other systems
  or infrastructure, without changing its scientific processing or results.

## [Unreleased]
### Added
- **INTEGRATION** - `assets/run_pathogen_id.sh`, a launcher for managed (projectify)
  runs and for git-clone runs. It owns the run's identity (`RUN_ID`), validates the
  environment in three classes before Nextflow starts, takes a `flock` on
  `${PIPELINE_DIR}/.lock` so one run owns the pipeline directory at a time, reports
  setup failures that `onComplete` cannot see, writes a machine-readable completion
  sentinel, records resource statistics and cleans up the work directory.
- **INTEGRATION** - `assets/pathogen_id.config`, the projectify asset config. It holds
  workflow inputs only; every location is interpolated from a variable the project
  `source_me.sh` exports and the launcher checks.
- **INTEGRATION** - Three environment toggles, resolved with the precedence
  submitting shell > `source_me.sh` > in-script default, and canonicalised by
  `normalize_bool` so an unrecognised value fails at launch rather than silently
  picking a side:
  - `DERMATLAS_WEBSITE_LOGGING` (default `true`) - log the run to the Dermatlas
    analysis log via the `dermatlas-http` CLI.
  - `DERMATLAS_SLACK_NOTIFICATIONS` (default `true`) - post a Slack message on
    completion, and on a launcher-phase failure.
  - `DERMATLAS_CLEANUP_WORK_DIR` (default `true`) - delete `work/` after a
    successful run.
- **INTEGRATION** - `RUN_ID`-based artifact naming. One id names the run log, the pull
  log, `execution_trace-<RUN_ID>.txt`, `execution_report-<RUN_ID>.html`,
  `stats/resource-stats-<RUN_ID>.txt` and the run reference in Slack messages.
  `params.trace_file` is assigned from the same value as `trace.file`, so the two
  cannot drift.
- **INTEGRATION** - `trace {}` and `report {}` blocks, both built from the exported
  `TRACE_DIR`. Without a trace there is no `--nextflow-performance` upload.
- **INTEGRATION** - `.update-version.sh`, which rewrites the version in every file
  that records it (the launcher's `REVISION=` and `manifest.version`) after
  pre-flighting each target.
- **INTEGRATION** - `.github/workflows/publish-assets.yml`, publishing the contents of
  `assets/` as a release bundle for `dermanager projectify`. The rolling
  `main-latest` / `develop-latest` tags are created once and never moved; only the
  attached assets are replaced.
- **INTEGRATION** - Required parameters (`bam_files`, `reference_database`,
  `confidence`, `organism`, `domain`) are declared in `nextflow.config` and validated
  by name in `main.nf`, so a missing value is a message rather than a null
  dereference inside a channel factory.
- **INTEGRATION** - This `## Keywords` block, and keywords on every entry from this
  release forward.

- **REPRODUCIBILITY** - `subcohorts` restricts which samples each SPARKI analysis
  covers. Kraken2 and KrakenTools still classify every sample matched by `bam_files`;
  each subcohort then gets its own SPARKI run over only the reports of the samples its
  `sample_list` names, published under `outdir/sparki/<subcohort>/` and prefixed with
  the subcohort name. Results for a given set of samples are unchanged, but a run that
  previously produced one `sparki/` directory over every sample now produces one per
  subcohort - and samples absent from every list no longer contribute to any SPARKI
  output. With `subcohorts` left empty the previous behaviour is kept, as a single
  `all_samples` subcohort. A subcohort matching none of the classified samples is an
  error, and samples in no subcohort are logged as a warning, because the sample id is
  derived from the BAM filename and a naming mismatch would otherwise be silent.
- **INTEGRATION** - `pathogen_id.config` feeds `subcohorts` from
  `RNA_SAMPLE_LIST_ONE_PER_PATIENT` and `RNA_SAMPLE_LIST_FINAL_DECISION`, which
  `run_pathogen_id.sh` now checks are exported and documents in its MANUAL ENVIRONMENT
  OVERRIDES block. The standalone contract is eight exports rather than six.

### Changed
- **INTEGRATION** - **Breaking:** run reporting is opt-in via the toggles above;
  exporting `SLACK_WEBHOOK_URL` alone no longer triggers Slack messages.
- **INTEGRATION** - **Breaking:** website logging goes through the `dermatlas-http`
  CLI (>= 0.6.1) against the `SELF_DESCRIBING_API` endpoint; `ANALYSIS_LOG_API_URL`
  and `params.analysis_log_api_url` are dropped. The Nextflow log and execution trace
  are attached to the analysis-log record. Reporting failures warn and never change
  the pipeline's exit status.
- **INTEGRATION** - **Breaking:** a run killed by LSF (`bkill`, MEMLIMIT, RUNLIMIT)
  now exits `128+n` and writes `.completed_with_error` instead of looking successful.
  Previously the exit trap saw the status of the last completed command.
- **INTEGRATION** - On-completion reporting variables are decoupled from the
  workflow's: `params.cohort_slug`, `params.sample_list_version` and
  `params.slack_webhook_url` are gone from `nextflow.config` (nothing in the workflow
  consumed them; `lib/Utils.groovy` reads `COHORT_SLUG`, `SAMPLE_LIST_VERSION_FILE`
  and `SLACK_WEBHOOK_URL` from the environment in `onComplete`), leaving the config
  files with workflow inputs only.
- **INTEGRATION** - `lib/Utils.groovy` is replaced with the current shared library,
  byte-for-byte identical to the copy in `dermatlas_rnafusions_nf`: env-gated opt-ins,
  the `dermatlas-http` subprocess runner in place of the raw `postJson`
  `HttpURLConnection` stack, a `workflow.stubRun` guard, and the log and trace passed
  as plain file paths rather than gzipped and base64'd in groovy.
- **INTEGRATION** - `params.publish_dir_mode = 'copy'` is set and applied by every
  `publishDir`. This is load-bearing rather than a preference: the launcher's work-dir
  cleanup is safe only because the published results have already been copied out.
  Note the cost - sparki publishes its intermediate FASTQs, which are now duplicated
  bytes rather than symlinks.
- **INTEGRATION** - `manifest.homePage` points at
  `https://github.com/team113sanger/sparki-nf`, and `manifest.defaultBranch` is `main`,
  matching the repository's default branch.
- **INTEGRATION** - The `farm22` profile sets `singularity.cacheDir`, matching the
  `NXF_SINGULARITY_CACHEDIR` the launcher pins. Nextflow's default cache lives under
  `work/`, which the cleanup deletes.
- **INTEGRATION** - `params.json` carries neutral repo-relative example paths instead
  of personal absolute ones, and drops the unused `copy_mode` key.

### Fixed
- **ROBUSTNESS** - Stub runs (`-stub-run`, or `params.is_stub`) never contact the
  website or Slack, regardless of the opt-in toggles.
- **INTEGRATION** - Each `nextflow` command gets its own log
  (`nextflow-pull-<RUN_ID>.log`, `nextflow-run-<RUN_ID>.log`) via a per-command
  `NXF_LOG_FILE` prefix. A single exported value would leave the run's log plus a
  rotated `.log.1` from the pull, which reads like a rerun.
- **INTEGRATION** - The unused `params.tracedir` is removed; it was declared and
  consumed by nothing.

## [1.0.1] - 2025-07-04

### Fixed
- Fixed the `nextflow.config` file to allow sparki-nf to be triggered using the repo URL.

## [1.0.0] - 2025-07-01

### Added
- Initial tag.
