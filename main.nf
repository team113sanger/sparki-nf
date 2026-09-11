#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { BAM_TO_FASTQ } from './modules/modules.nf'
include { GET_KRAKEN2_RESULTS } from './subworkflows/get_kraken2_results.nf'
include { REFINE_KRAKEN2_RESULTS } from './subworkflows/refine_kraken2_results.nf'

workflow {

    /***************************/
    /**** Validate the input ***/
    /***************************/

    // Declared with null defaults in nextflow.config and supplied by the asset config
    // (or -params-file / --flags). Named here so a missing value is a message rather
    // than a null dereference inside a channel factory.
    ['bam_files', 'reference_database', 'confidence', 'organism', 'domain'].each { name ->
        if (params[name] == null || params[name].toString().trim() == '') {
            error "Missing required parameter: --${name}. See the README, or assets/pathogen_id.config for the projectify defaults."
        }
    }

    /*******************************/
    /**** Resolve the subcohorts ***/
    /*******************************/

    // subcohort. Each subcohort is a name plus a sample list; the lists are
    // generated and versioned by dermanager, so the asset config names them by
    // their exported variables rather than rebuilding their paths.

    def use_subcohorts = Utils.parseCLIBool(params.use_subcohorts, false, 'use_subcohorts')
    def allow_empty    = Utils.parseCLIBool(params.allow_empty_input, false, 'allow_empty_input')

    if (!use_subcohorts && params.subcohorts && !params.subcohorts.isEmpty()) {
        log.info(
            "use_subcohorts is false: running a single SPARKI analysis over every sample " +
            "and ignoring the ${params.subcohorts.size()} configured subcohort(s)."
        )
    }

    def subcohort_defs = null
    if (use_subcohorts) {
        if (!params.subcohorts || params.subcohorts.isEmpty()) {
            error "ERROR: use_subcohorts is true but no subcohorts are configured. " +
                  "Either set subcohorts, or set use_subcohorts = false to run a single " +
                  "SPARKI analysis over every sample."
        }
        subcohort_defs = params.subcohorts.collect { subcohort_name, config ->
            if (!config?.sample_list) {
                error "ERROR: subcohort '${subcohort_name}' has no sample_list. " +
                      "Example: subcohorts = ['one_per_patient': [sample_list: '/path/to/samples.tsv']]"
            }
            def list_file = file(config.sample_list, checkIfExists: true)
            // One sample id per line; a leading tab-separated column is honoured so
            // the same file works whether it is a .txt of ids or a .tsv.
            def ids = list_file.readLines()
                .collect { it.trim().split('\t')[0].trim() }
                .findAll { it } as Set
            if (!ids) {
                if (!allow_empty) {
                    error "ERROR: subcohort '${subcohort_name}': sample list ${list_file} contains no sample ids."
                }
                log.warn("Subcohort '${subcohort_name}': sample list ${list_file} contains no sample ids; skipping it.")
                return null
            }
            [name: subcohort_name, ids: ids, path: list_file]
        }.findAll { it != null }

        // Every subcohort dropped out above, so there is nothing left to select
        // samples for and no SPARKI run to make. The classification still runs:
        // its per-sample Kraken2 output is published and cached, so the SPARKI
        // step is all that is waiting on the sample lists being populated.
        if (!subcohort_defs) {
            log.warn(
                "Every configured subcohort has an empty sample list; classifying the samples " +
                "but skipping the SPARKI analysis (allow_empty_input is true)."
            )
        }
        else {
            log.info("Processing subcohorts: ${subcohort_defs.collect { it.name }.join(', ')}")
        }
    }

    /*************************/
    /**** Load input data ****/
    /*************************/

    // Resolved here rather than by Channel.fromPath(checkIfExists: true) so that
    // zero matches is something the workflow decides about: file() with a glob
    // returns a (possibly empty) list, where the channel factory would throw.
    def bam_paths = file(params.bam_files)                                 // BAM files.
    if (!(bam_paths instanceof List)) {
        bam_paths = bam_paths ? [bam_paths] : []
    }
    if (!bam_paths) {
        if (!allow_empty) {
            error "ERROR: no BAM files match ${params.bam_files}. Check BAMS_DIR, or set " +
                  "allow_empty_input = true for a cohort that is expected to have no data yet."
        }
        log.warn(
            "No BAM files match ${params.bam_files}; nothing to analyse. " +
            "Completing successfully (allow_empty_input is true)."
        )
        return
    }

    bams = Channel.fromList(bam_paths)
        .map { file -> tuple(file.simpleName, file) }
    reference_dir = file(params.reference_database, checkIfExists: true)   // Kraken2's reference database.

    // Warn about samples that will be classified but appear in no subcohort sample
    // list, and so are dropped from every SPARKI output. The sample id comes from
    // the BAM filename, so a naming mismatch would otherwise fail silently.
    if (subcohort_defs) {
        def known_ids = subcohort_defs.collectMany { it.ids } as Set
        bams.map { sample_id, bam -> sample_id }
            .collect()
            .subscribe { processed_ids ->
                def dropped = processed_ids.unique().findAll { !known_ids.contains(it) }.sort()
                if (dropped) {
                    log.warn(
                        "${dropped.size()} sample(s) will be classified but are not listed in any " +
                        "subcohort sample list, so they will be dropped from all SPARKI outputs: " +
                        "${dropped.join(', ')}"
                    )
                }
            }
    }

    /************************/
    /**** Start analysis ****/
    /************************/

    // Convert BAMs to FASTQ files.
    BAM_TO_FASTQ(bams)

    // Run Kraken2 and KrakenTools over every sample.
    GET_KRAKEN2_RESULTS(
        BAM_TO_FASTQ.out.fastqs,   // FASTQs
        reference_dir,              // Kraken2's reference database.
        params.confidence           // Confidence score.
    )

    // Collect the per-sample reports once, keeping their sample ids so each
    // subcohort can select its own without re-running anything upstream.
    all_std_reports = GET_KRAKEN2_RESULTS.out.std_reports.toList().map { pairs -> [pairs] }
    all_mpa_reports = GET_KRAKEN2_RESULTS.out.mpa_reports.toList().map { pairs -> [pairs] }

    if (use_subcohorts && !subcohort_defs) {
        // Classification ran; there is no subcohort left to select samples for.
        sparki_inputs = Channel.empty()
    }
    else if (use_subcohorts) {
        sparki_inputs = Channel.fromList(subcohort_defs)
            .combine(all_std_reports)
            .combine(all_mpa_reports)
            .flatMap { subcohort, std_pairs, mpa_pairs ->
                def std = std_pairs.findAll { subcohort.ids.contains(it[0]) }.sort { it[0] }.collect { it[1] }
                def mpa = mpa_pairs.findAll { subcohort.ids.contains(it[0]) }.sort { it[0] }.collect { it[1] }
                if (!std) {
                    if (!allow_empty) {
                        error "ERROR: subcohort '${subcohort.name}' matched none of the classified samples. " +
                              "Check that the ids in ${subcohort.path} match the BAM filenames."
                    }
                    log.warn(
                        "Subcohort '${subcohort.name}' matched none of the classified samples; " +
                        "no SPARKI run for it. Check that the ids in ${subcohort.path} match the BAM filenames."
                    )
                    return []
                }
                return [tuple(["cohort_id": subcohort.name], std, mpa)]
            }
    }
    else {
        sparki_inputs = all_std_reports
            .combine(all_mpa_reports)
            .flatMap { std_pairs, mpa_pairs ->
                if (!std_pairs) {
                    if (!allow_empty) {
                        error "ERROR: no samples were classified, so there is nothing for SPARKI to refine."
                    }
                    log.warn("No samples were classified; skipping the SPARKI analysis.")
                    return []
                }
                return [tuple(
                    ["cohort_id": "all_samples"],
                    std_pairs.sort { it[0] }.collect { it[1] },
                    mpa_pairs.sort { it[0] }.collect { it[1] }
                )]
            }
    }

    // Run SPARKI once per subcohort.
    REFINE_KRAKEN2_RESULTS(
        sparki_inputs,                  // (meta, standard reports, MPA-style reports) per subcohort.
        params.organism,                // Organism being analysed, at the species level (e.g. Homo sapiens).
        reference_dir,                  // Kraken2's reference database.
        params.domain,                  // Domain of interest (e.g. Viruses).
        params.metadata,                // Metadata table.
        params.metadata_sample_column,  // Sample column in metadata table.
        params.metadata_columns,        // Comma-delimited column names from the metadata table.
        params.prefix,                  // Prefix to be added to output files.
        params.verbosity,               // Whether SPARKI should be run in verbose mode.
        params.samples_to_remove,       // Samples that should not be included in the SPARKI analysis.
        params.flags
    )
}

workflow.onComplete {
    Utils.reportRun(workflow, params)
}
