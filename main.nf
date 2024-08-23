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
        .take(10)
        .map { file -> tuple(file.simpleName, file)}
    reference_dir = file(params.reference_database, checkIfExists: true)   // Kraken2's reference database.
    metadata = file(params.metadata, checkIfExists: true)                  // Metadata file.

    /****************************/
    /**** Create directories ****/
    /****************************/

    fastq_outdir = file("${params.outdir}/fastq")            // FASTQ directory.
    fastq_outdir.mkdirs()

    std_reports_dir = file("${params.outdir}/std_reports")   // Standard reports directory.
    std_reports_dir.mkdirs()

    mpa_reports_dir = file("${params.outdir}/mpa_reports")   // MPA-style reports directory.
    mpa_reports_dir.mkdirs()

    sparki_dir = file("${params.outdir}/sparki")             // SPARKI outputs directory.
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

    CLEAN_UP(
        BAM_TO_FASTQ.out.fastq_1,
        BAM_TO_FASTQ.out.fastq_2,
        GET_KRAKEN2_RESULTS.out.std_reports,
        GET_KRAKEN2_RESULTS.out.mpa_reports
    )

    // Get number of starting BAM files.
    n_bams = bams.count()
    n_bams.view()

    // Get number of output standard and MPA-style reports.
    GET_KRAKEN2_RESULTS.out.std_reports.set { out_std_reports }
    GET_KRAKEN2_RESULTS.out.mpa_reports.set { out_mpa_reports }

    out_std_reports.count().view()
    out_mpa_reports.count().view()
    
    // If the number of standard/MPA-style reports is the same as the number of starting BAM files,
    // this means that all output files have been generated and, therefore, the SPARKI analysis can
    // begin.
    if (out_std_reports.count() == n_bams && out_mpa_reports.count() == n_bams) {

        // Organise outputs and run SPARKI.
        REFINE_KRAKEN2_RESULTS(                     
            GET_KRAKEN2_RESULTS.out.std_reports,   // Standard reports.
            GET_KRAKEN2_RESULTS.out.mpa_reports,   // MPA-style reports.
            std_reports_dir,                       // Directory for standard reports.
            mpa_reports_dir,                       // Directory for MPA-style reports.
            reference_dir,                         // Kraken2's reference database.
            metadata,                              // Metadata table.
            params.metadata_sample_column,
            params.metadata_columns,               // Comma-delimited columns names from the metadata table.
            params.prefix,                         // Prefix to be added to output files.
            params.domain,                         // Domain of interest (e.g. Viruses).
            params.options_for_sparki,             // Additional options for SPARKI (e.g. --verbose).
            sparki_dir                             // Directory for SPARKI outputs.
        )
    }

}
