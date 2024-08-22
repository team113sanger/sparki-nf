#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { GET_KRAKEN2_RESULTS } from './subworkflows/get_kraken2_results.nf'
include { REFINE_KRAKEN2_RESULTS } from './subworkflows/refine_kraken2_results.nf'
include { BAM_TO_FASTQ } from './modules/modules.nf'

workflow {
    
  // Input data.
  bams = Channel.fromPath(params.bam_files, checkIfExists: true).take(5)
  reference_dir = file(params.reference_database, checkIfExists: true)
  confidence_score = Channel.of(params.confidence)
  metadata = file(params.metadata, checkIfExists: true)

  // Convert BAMs to FASTQ files.
  BAM_TO_FASTQ(bams)

  // Run Kraken2 and KrakenTools.
  GET_KRAKEN2_RESULTS(
    BAM_TO_FASTQ.out.fastq_1,
    BAM_TO_FASTQ.out.fastq_2,
    reference_dir,
    confidence_score
  )

  REFINE_KRAKEN2_RESULTS(
    GET_KRAKEN2_RESULTS.out.std_reports,
    GET_KRAKEN2_RESULTS.out.mpa_reports,
    reference_dir,
    metadata,
    params.metadata_columns,     // Comma-delimited columns names from the metadata table.
    params.prefix,   // Prefix to be added to output files.
    params.domain,   // Domain of interest (e.g. Viruses).
    params.options_for_sparki,   // Additional options for SPARKI (e.g. --verbose).
    params.sparki_outdir
  )

}
