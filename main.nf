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

    /****************************/
    /**** Create directories ****/
    /****************************/

    std_reports_dir = file("${params.outdir}/std_reports") // Standard reports directory.
    std_reports_dir.mkdirs()

    mpa_reports_dir = file("${params.outdir}/mpa_reports") // MPA-style reports directory.
    mpa_reports_dir.mkdirs()

    sparki_dir = file("${params.outdir}/sparki")           // SPARKI directory.
    sparki_dir.mkdirs()

    /************************/
    /**** Start analysis ****/
    /************************/

    // Convert BAMs to FASTQ files.
    BAM_TO_FASTQ(bams)

    // Run Kraken2 and KrakenTools.
    GET_KRAKEN2_RESULTS(                         
        BAM_TO_FASTQ.out.fastq_1,   // FASTQ1.
        BAM_TO_FASTQ.out.fastq_2,   // FASTQ2.
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
        std_reports_dir,                // Directory for standard reports.
        mpa_reports_dir,                // Directory for MPA-style reports.
        params.organism,                // Organism being analysed, at the species level (e.g. Homo sapiens).
        reference_dir,                  // Kraken2's reference database.
        params.domain,                  // Domain of interest (e.g. Viruses).
        params.metadata,                // Metadata table.
        params.metadata_sample_column,  // Sample column in metadata table.
        params.metadata_columns,        // Comma-delimited columns names from the metadata table.
        params.prefix,                  // Prefix to be added to output files.
        params.include_eukaryotes,      // Whether eukaryotes should be included in all plots.
        params.include_sample_names,    // Whether sample names should be included in all plots.
        params.verbose,                 // Whether SPARKI should be run in verbose mode.
        params.samples_to_remove,       // Samples that should not be included in the SPARKI analysis.
        sparki_dir,                     // Directory for SPARKI outputs.
        params.sparki_cli,
        params.rscript
    )
}
