#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

process RUN_KRAKEN2 {
    publishDir "${params.outdir}", mode: "copy"
    module "kraken2/2.1.2"

    input: 
    tuple val(METADATA), path(READS)
    path(REF_DIR)
    val(C_SCORE)

    output:
    tuple val(METADATA), path("*.kraken"), emit: std_report

    script: 
    """
    kraken2 \
    --paired \
    --gzip-compressed \
    --use-names \
    --confidence ${C_SCORE} \
    --db ${REF_DIR} \
    --report ${METADATA}.kraken \
    --report-minimizer-data \
    --output /dev/null ${READS} 
    """
    
    stub:
    """
    echo ${C_SCORE}
    echo ${REF_DIR}
    echo ${METADATA}
    echo ${READS}
    touch sample.kraken
    """

}

//process RUN_KRAKENTOOLS {
  //  publishDir "${params.outdir}", mode: "copy"
  //  module "krakentools/1.2.4"

  //  input: 
  //  tuple val(METADATA), path(REPORT)

  //  output:
  //  tuple val(METADATA), path("*.kraken"), emit: mpa_report

  //  script: 
  //  """
  //  kreport2mpa.py \
  //     --report ${REPORT} \
  //      --output ${METADATA}.kraken.mpa
  //  """
    
    //stub:
    //"""
    //"""

//}

workflow {
    
    reads_sample_pair = Channel.fromFilePairs(params.fastq_files, checkIfExists: true) // Add .take(1) to limit to a single sample
    reference = file(params.reference_database, checkIfExists: true)
    confidence = Channel.of(params.c_score)

    RUN_KRAKEN2(reads_sample_pair, reference, confidence).view() // Add .view() to see results as they are output by kraken
}
