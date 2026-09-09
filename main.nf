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

    // Every BAM is classified by Kraken2. Only the SPARKI refinement step is
    // restricted to a subcohort, so one Kraken2 run per sample serves every
    // subcohort. Each subcohort is a name plus a sample list; the lists are
    // generated and versioned by dermanager, so the asset config names them by
    // their exported variables rather than rebuilding their paths.
    //
    // With no subcohorts configured the pipeline behaves as it always has: a
    // single SPARKI run over every sample, published under "all_samples". That
    // keeps the portable `-profile container` usage working unchanged.
    def subcohort_defs = null
    if (params.subcohorts && !params.subcohorts.isEmpty()) {
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
                error "ERROR: subcohort '${subcohort_name}': sample list ${list_file} contains no sample ids."
            }
            [name: subcohort_name, ids: ids, path: list_file]
        }
        log.info("Processing subcohorts: ${subcohort_defs.collect { it.name }.join(', ')}")
    }

    /*************************/
    /**** Load input data ****/
    /*************************/

    bams = Channel.fromPath(params.bam_files, checkIfExists: true)         // BAM files.
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

    if (subcohort_defs) {
        sparki_inputs = Channel.fromList(subcohort_defs)
            .combine(all_std_reports)
            .combine(all_mpa_reports)
            .map { subcohort, std_pairs, mpa_pairs ->
                def std = std_pairs.findAll { subcohort.ids.contains(it[0]) }.sort { it[0] }.collect { it[1] }
                def mpa = mpa_pairs.findAll { subcohort.ids.contains(it[0]) }.sort { it[0] }.collect { it[1] }
                if (!std) {
                    error "ERROR: subcohort '${subcohort.name}' matched none of the classified samples. " +
                          "Check that the ids in ${subcohort.path} match the BAM filenames."
                }
                tuple(["cohort_id": subcohort.name], std, mpa)
            }
    }
    else {
        sparki_inputs = all_std_reports
            .combine(all_mpa_reports)
            .map { std_pairs, mpa_pairs ->
                tuple(
                    ["cohort_id": "all_samples"],
                    std_pairs.sort { it[0] }.collect { it[1] },
                    mpa_pairs.sort { it[0] }.collect { it[1] }
                )
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
