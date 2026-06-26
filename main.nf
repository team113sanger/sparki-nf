#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { BAM_TO_FASTQ } from './modules/modules.nf'
include { GET_KRAKEN2_RESULTS } from './subworkflows/get_kraken2_results.nf'
include { REFINE_KRAKEN2_RESULTS } from './subworkflows/refine_kraken2_results.nf'

workflow {
    
    /*************************/
    /**** Load input data ****/
    /*************************/

    bams = Channel.fromPath(params.bam_files, checkIfExists: true)         // BAM files.
        .map { file -> tuple(file.simpleName, file) }
    reference_dir = file(params.reference_database, checkIfExists: true)   // Kraken2's reference database.

    /************************/
    /**** Start analysis ****/
    /************************/

    // Convert BAMs to FASTQ files.
    BAM_TO_FASTQ(bams)

    // Run Kraken2 and KrakenTools.
    GET_KRAKEN2_RESULTS(                         
        BAM_TO_FASTQ.out.fastqs,   // FASTQs
        reference_dir,              // Kraken2's reference database.
        params.confidence           // Confidence score.
    )

    // Collect all standard reports into a single item.
    GET_KRAKEN2_RESULTS.out.std_reports
        .map { it[1] }
        .collect()
        .set { all_std_reports }

    // Collect all MPA-style reports into a single item.
    GET_KRAKEN2_RESULTS.out.mpa_reports
        .map { it[1] }
        .collect()
        .set { all_mpa_reports }

    // Run SPARKI.
    REFINE_KRAKEN2_RESULTS(
        all_std_reports,                // Standard reports.
        all_mpa_reports,                // MPA-style reports.
        params.organism,                // Organism being analysed, at the species level (e.g. Homo sapiens).
        reference_dir,                  // Kraken2's reference database.
        params.domain,                  // Domain of interest (e.g. Viruses).
        params.metadata,                // Metadata table.
        params.metadata_sample_column,  // Sample column in metadata table.
        params.metadata_columns,        // Comma-delimited column names from the metadata table.
        params.prefix,                  // Prefix to be added to output files.
        params.verbosity,                // Whether SPARKI should be run in verbose mode.
        params.samples_to_remove,       // Samples that should not be included in the SPARKI analysis.
        params.flags
    )
}

workflow.onComplete {
    Utils.reportRun(workflow, params)
}
