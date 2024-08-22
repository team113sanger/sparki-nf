#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { GET_KRAKEN2_RESULTS } from './subworkflows/get_kraken2_results.nf'
include { REFINE_KRAKEN2_RESULTS } from './subworkflows/refine_kraken2_results.nf'

workflow {
    
  // Input data.
  sample_read_pair = Channel.fromFilePairs(params.fastq_files, checkIfExists: true) // Add .take(1) to limit to a single sample
  reference_dir = file(params.reference_database, checkIfExists: true)
  confidence_score = Channel.of(params.confidence)
  metadata = file(params.metadata, checkIfExists: true)

  // Run Kraken2 and KrakenTools.
  GET_KRAKEN2_RESULTS(
    sample_read_pair,
    reference_dir,
    confidence_score,
    params.options_for_kraken2
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
