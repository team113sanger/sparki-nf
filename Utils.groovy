import groovy.json.JsonOutput

/**
 * Small collection of static helpers used across the pipeline.
 *
 * Classes placed in lib/ are added to the Nextflow classpath automatically,
 * so these methods can be called from main.nf / nextflow.config without an
 * explicit import (e.g. `Utils.sendSlackSuccess(...)`).
 */
class Utils {

    /**
     * Parse a Nextflow CLI param into a strict boolean.
     *
     * Accepts:
     *  - Boolean: true/false
     *  - Number: 1/0
     *  - String (case-insensitive, trimmed): "true"/"false"/"1"/"0"
     *
     * If value is null (or empty string), returns defaultValue.
     * Otherwise throws IllegalArgumentException on invalid inputs.
     */
    static boolean parseCLIBool(Object givenValue, boolean defaultValue = false, String paramName = null) {
        if (givenValue == null) {
            return defaultValue
        }

        if (givenValue instanceof Boolean) {
            return (Boolean) givenValue
        }

        if (givenValue instanceof Number) {
            int n = ((Number) givenValue).intValue()
            if (n == 0) return false
            if (n == 1) return true
            throw new IllegalArgumentException(errMsg(paramName, givenValue, "expected 0 or 1"))
        }

        String s = givenValue.toString().trim()
        if (s.length() == 0) {
            throw new IllegalArgumentException(errMsg(paramName, givenValue, "empty string is not a valid, expected true/false/1/0"))
        }

        s = s.toLowerCase()
        if (s == "true" || s == "1")  return true
        if (s == "false" || s == "0") return false

        throw new IllegalArgumentException(errMsg(paramName, givenValue, "expected true/false/1/0 (case-insensitive)"))
    }

    // ---- Run-completion entry point ----

    /**
     * Single entry point for `workflow.onComplete`. Drop this into any pipeline:
     *
     *   workflow.onComplete { Utils.reportRun(workflow, params) }
     *
     * Everything pipeline-specific is read from `workflow.manifest` and `params`,
     * so this method is identical across pipelines. Notifications and the
     * analysis-log call are best-effort: a failure here never changes the
     * pipeline's exit status.
     */
    static void reportRun(def workflow, def params) {
        println "Pipeline completed at: ${workflow.complete}"
        if (workflow.success) {
            println "Pipeline finished successfully!"
        } else {
            System.err.println "Pipeline finished with errors!"
        }

        boolean isStub  = parseCLIBool(params.is_stub, false)
        String cohort   = (params.cohort_slug ?: '').toString().trim()
        String runId    = buildRunId(params)
        // Label shown in Slack: prefer the human-readable manifest description,
        // fall back to the manifest name, then a generic default.
        String label    = (workflow.manifest?.description ?: workflow.manifest?.name ?: 'pipeline').toString()
        String version  = workflow.manifest?.version

        // Slack notification (if a webhook is configured and this is not a stub run)
        String slackUrl = (params.slack_webhook_url ?: '').toString().trim()
        if (slackUrl && !isStub) {
            boolean sent
            if (workflow.success) {
                sent = sendSlackSuccess(slackUrl, runId, version, workflow.duration, label, cohort)
            } else {
                String nxfLog = System.getenv('NXF_LOG_FILE') ?: ''
                sent = sendSlackFailure(slackUrl, runId, version, workflow.duration, label,
                                        workflow.errorReport, nxfLog, cohort)
            }
            if (sent) {
                println "Slack notification sent"
            } else {
                System.err.println "WARNING: Slack notification failed (pipeline result is unaffected)"
            }
        }

        // Append a run record to the cohort analysis-log (if configured and not a stub run)
        String logUrl = (params.analysis_log_api_url ?: '').toString().trim()
        if (logUrl && !isStub) {
            String runStatus    = workflow.success ? 'completed' : 'failed'
            String pipelineSlug = (params.analysis_pipeline_slug ?: '').toString().trim()
            Integer sampleVer   = readSampleListVersion(params.sample_list_version)
            if (reportCohortAnalysisLog(logUrl, cohort, pipelineSlug, runStatus, sampleVer, version)) {
                println "Reported analysis run for cohort '${cohort}' (${runStatus}) to analysis-log API"
            } else {
                System.err.println "WARNING: Failed to report analysis run for cohort '${cohort}' to analysis-log API (pipeline result is unaffected)"
            }
        }
    }

    // ---- Slack notification helpers ----

    /**
     * Notify Slack that the pipeline completed successfully.
     *
     * @param label human-readable pipeline name (e.g. workflow.manifest.description)
     */
    static boolean sendSlackSuccess(String webhookUrl, String runId, String version,
                                    def duration, String label, String cohortSlug = '') {
        def ref = runRef(runId, cohortSlug)
        String msg = ":white_check_mark: *${label}* completed successfully - `${ref}`\n" +
            "_Pipeline v${version} | Duration: ${duration}_"

        return postSlackMessage(webhookUrl, msg)
    }

    /**
     * Notify Slack that the pipeline failed.
     *
     * Parses workflow.errorReport to extract the failed process name and work
     * directory (if present). Includes NXF_LOG_FILE path when available.
     *
     * @param errorReport  workflow.errorReport from Nextflow (may be null)
     * @param nxfLogFile   NXF_LOG_FILE path (may be null or empty)
     */
    static boolean sendSlackFailure(String webhookUrl, String runId, String version,
                                    def duration, String label, String errorReport,
                                    String nxfLogFile, String cohortSlug = '') {
        def ref = runRef(runId, cohortSlug)
        def msg = ":octagonal_sign: *${label}* failed - `${ref}`\n" +
                  "_Pipeline v${version} | Duration: ${duration}_"

        def processName = parseProcessName(errorReport)
        def workDir = parseWorkDir(errorReport)

        if (processName) {
            msg += "\nProcess: `${processName}`"
        }
        if (workDir) {
            msg += "\nWork dir: `${workDir}`"
        }
        if (nxfLogFile) {
            msg += "\nNextflow Log: `${nxfLogFile}`"
        }

        return postSlackMessage(webhookUrl, msg)
    }

    // ---- Cohort analysis-log helpers ----

    /**
     * Append one analysis-pipeline run record for a single cohort to the
     * versioned-cohort-analysis-log endpoint.
     *
     * The endpoint is append-only and validates that `cohortSlug` and
     * `pipelineSlug` resolve to a known Cohort / AnalysisPipeline (a bad slug
     * comes back as HTTP 422). `runStatus` is one of the IngestionStatus values
     * (not_run / completed / failed / blocked / unknown); `sampleListVersion`
     * must be an integer >= 1; `pipelineVersion` is optional (may be null).
     *
     * Returns true on a 2xx response. Required-field problems are caught here
     * (logged, returns false) and any network/HTTP failure is swallowed by
     * postJson, so logging a run can never change the pipeline's exit status.
     */
    static boolean reportCohortAnalysisLog(String url, String cohortSlug, String pipelineSlug,
                                           String runStatus, Integer sampleListVersion,
                                           String pipelineVersion, int timeoutMs = 10_000) {
        if (!url) {
            return false
        }
        if (!cohortSlug || !pipelineSlug) {
            System.err.println("WARNING: analysis-log skipped — cohort_slug and analysis_pipeline_slug are both required")
            return false
        }
        if (sampleListVersion == null || sampleListVersion < 1) {
            System.err.println("WARNING: analysis-log skipped for cohort '${cohortSlug}' — sample_list_version must be an integer >= 1 (got ${sampleListVersion})")
            return false
        }
        Map payload = [
            cohort_slug              : cohortSlug,
            analysis_pipeline_slug   : pipelineSlug,
            run_status               : runStatus,
            sample_list_version      : sampleListVersion,
            analysis_pipeline_version: pipelineVersion,
        ]
        return postJson(url, payload, timeoutMs)
    }

    // ---- private helpers ----

    private static String errMsg(String paramName, Object givenValue, String expectation) {
        String namePart = paramName ? "--${paramName} " : ""
        return "Invalid ${namePart}${givenValue} (${expectation})"
    }

    /**     *
     * An explicit `params.run_id` wins outright. Otherwise the id is assembled
     * from the STUDY / PROJECT env vars used by our run wrappers; the
     * genotype falls back to `params.default_genotype` (then 'rna') so non-RNA
     * pipelines can set their own default rather than inheriting this one.
     */
    private static String buildRunId(def params) {
        if (params?.run_id) {
            return params.run_id.toString()
        }
        String study    = System.getenv('STUDY') ?: ''
        String project  = System.getenv('PROJECT') ?: ''
        return "${study}_${project}"
    }

    /**
     * Read the sample-list version from a file whose contents are a single
     * integer. Returns null (with a stderr warning) if the path is unset, the
     * file is missing, or it does not contain an integer — in which case the
     * analysis-log call is skipped.
     */
    private static Integer readSampleListVersion(def sampleListVersionPath) {
        if (!sampleListVersionPath) {
            return null
        }
        def f = new File(sampleListVersionPath.toString())
        if (!f.exists()) {
            System.err.println("WARNING: sample_list_version file '${f}' not found; analysis-log will be skipped")
            return null
        }
        try {
            return f.text.trim() as Integer
        } catch (NumberFormatException e) {
            System.err.println("WARNING: sample_list_version file '${f}' does not contain an integer; analysis-log will be skipped")
            return null
        }
    }

    /**
     * Human-facing reference for a pipeline run in Slack messages.
     *
     * The cohort slug is optional (the pipeline can run without it). When it is
     * set, the run is shown as "<cohort_slug> (<run_id>)" so readers see the
     * cohort first; otherwise the bare run id is used.
     *
     * @param runId      always present (e.g. study_project_genotype)
     * @param cohortSlug optional cohort slug (null/empty when not configured)
     */
    private static String runRef(String runId, String cohortSlug) {
        return (cohortSlug != null && !cohortSlug.trim().isEmpty())
            ? "${cohortSlug.trim()} (${runId})"
            : runId
    }

    /**
     * Extract the process name from workflow.errorReport.
     * Matches: Error executing process > 'P45_RUN_RNASEQ_MANIFEST (tag)'
     * @return process name string or null
     */
    private static String parseProcessName(String errorReport) {
        if (!errorReport) return null
        def m = errorReport =~ /Error executing process > '([^']+)'/
        return m.find() ? m.group(1) : null
    }

    /**
     * Extract the work directory from workflow.errorReport.
     * Matches the line after "Work dir:" in the report.
     * @return work directory path or null
     */
    private static String parseWorkDir(String errorReport) {
        if (!errorReport) return null
        def m = errorReport =~ /(?m)Work dir:\s*\n\s*(\S+)/
        return m.find() ? m.group(1) : null
    }

    /**
     * POST a message to a Slack incoming webhook.
     *
     * Network errors and non-2xx responses are caught and logged to stderr
     * so that a notification failure never causes the pipeline itself to fail.
     *
     * @return true if the webhook accepted the message (HTTP 2xx), false otherwise
     */
    private static boolean postSlackMessage(String webhookUrl, String message, int timeoutMs = 10_000) {
        if (!webhookUrl || !message) {
            return false
        }

        try {
            def url = new java.net.URL(webhookUrl)
            def conn = (java.net.HttpURLConnection) url.openConnection()
            conn.setRequestMethod('POST')
            conn.setRequestProperty('Content-Type', 'application/json; charset=UTF-8')
            conn.setConnectTimeout(timeoutMs)
            conn.setReadTimeout(timeoutMs)
            conn.setDoOutput(true)

            // Minimal JSON-safe escaping for the message text
            def escaped = message
                .replace('\\', '\\\\')
                .replace('"', '\\"')
                .replace('\n', '\\n')

            conn.outputStream.withWriter('UTF-8') { writer ->
                writer.write("{\"text\":\"${escaped}\"}")
            }

            int code = conn.getResponseCode()
            if (code >= 200 && code < 300) {
                return true
            }
            System.err.println("WARNING: Slack webhook returned HTTP ${code}")
            return false
        } catch (SocketTimeoutException e) {
            System.err.println("WARNING: Slack notification timed out after ${timeoutMs}ms: ${e.message}")
            return false
        } catch (Exception e) {
            System.err.println("WARNING: Slack notification failed: ${e.message}")
            return false
        }
    }

    /**
     * POST a JSON-serialised payload to `url`.
     *
     * Network errors and non-2xx responses are caught and logged to stderr
     * so that a reporting failure never causes the pipeline itself to fail.
     *
     * @return true if the endpoint accepted the payload (HTTP 2xx), false otherwise
     */
    private static boolean postJson(String url, Map payload, int timeoutMs = 10_000) {
        if (!url || payload == null) {
            return false
        }

        HttpURLConnection conn = null
        try {
            String body = JsonOutput.toJson(payload)
            conn = (HttpURLConnection) new URL(url).openConnection()
            conn.setRequestMethod('POST')
            conn.setRequestProperty('Content-Type', 'application/json; charset=UTF-8')
            conn.setRequestProperty('Accept', 'application/json')
            conn.setConnectTimeout(timeoutMs)
            conn.setReadTimeout(timeoutMs)
            conn.setDoOutput(true)

            conn.outputStream.withWriter('UTF-8') { writer ->
                writer.write(body)
            }

            int code = conn.getResponseCode()
            if (code >= 200 && code < 300) {
                return true
            }
            String errBody = ''
            try {
                errBody = conn.errorStream?.getText('UTF-8')?.trim() ?: ''
            } catch (ignored) {
                // best-effort: a missing/unreadable error body is fine
            }
            System.err.println("WARNING: API at ${url} returned HTTP ${code}${errBody ? ': ' + errBody : ''}")
            return false
        } catch (SocketTimeoutException e) {
            System.err.println("WARNING: status API request timed out after ${timeoutMs}ms: ${e.message}")
            return false
        } catch (Exception e) {
            System.err.println("WARNING: status API request failed: ${e.message}")
            return false
        } finally {
            if (conn != null) {
                conn.disconnect()
            }
        }
    }
}
