#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

process RUN_KRAKEN2 {
    publishDir "${params.outdir}", mode: "copy"
    module "kraken2/2.1.2"

    input: 
    tuple val(SAMPLE_ID), path(READS)
    path(REF_DIR)
    val(C_SCORE)

    output:
    tuple val(SAMPLE_ID), path("*.kraken"), emit: std_report

    script: 
    """
    kraken2 \
        --paired \
        --gzip-compressed \
        --use-names \
        --confidence ${C_SCORE} \
        --db ${REF_DIR} \
        --report ${SAMPLE_ID}.kraken \
        --report-minimizer-data \
        --output /dev/null ${READS} 
    """
    
    stub:
    """
    echo ${C_SCORE}
    echo ${REF_DIR}
    echo ${SAMPLE_ID}
    echo ${READS}
    touch ${SAMPLE_ID}.kraken
    """

}

process RUN_KRAKENTOOLS {
    publishDir "${params.outdir}", mode: "copy"
    module "krakentools/1.2.4"

    input: 
    tuple val(SAMPLE_ID), path(REPORT)

    output:
    tuple val(SAMPLE_ID), path("*.kraken.mpa"), emit: mpa_report

    script: 
    """
    kreport2mpa.py \
        --report ${REPORT} \
        --output ${SAMPLE_ID}.kraken.mpa
    """
    
    stub:
    """
    echo ${REPORT}
    echo ${SAMPLE_ID}
    touch ${SAMPLE_ID}.kraken.mpa
    """

}

process RUN_SPARKI {
    publishDir "${params.outdir}", mode: "copy"

    input:
    tuple val(SAMPLE_ID), path(STD_REPORT)
    tuple val(SAMPLE_ID), path(MPA_REPORT)
    path(REF_DIR)
    path(METADATA)
    val(COLUMNS)
    val(PREFIX)

    output:

    """
    SPARKI_EXEC --std-reports ${STD_REPORT} --mpa-reports ${MPA_REPORT} \
        --reference ${REF_DIR}/inspect.txt \
        --metadata ${METADATA} \
        --columns ${COLUMNS} \
        --prefix ${PREFIX} \
        --outdir ${PROJECTDIR}/test/outputs/ \
        --verbose \
        --domain Viruses
    """

}

workflow {
    
    reads_sample_pair = Channel.fromFilePairs(params.fastq_files, checkIfExists: true) // Add .take(1) to limit to a single sample
    reference = file(params.reference_database, checkIfExists: true)
    metadata = file(params.metadata, checkIfExists: true)

    // Run Kraken2.
    RUN_KRAKEN2(reads_sample_pair, reference, params.confidence).view() 
    
    // Run KrakenTools.
    RUN_KRAKENTOOLS(RUN_KRAKEN2.out.std_report).view()

    // Run SPARKI.
    RUN_SPARKI(
        RUN_KRAKEN2.out.std_report, 
        RUN_KRAKENTOOLS.out.mpa_report,
        reference,
        metadata,
        params.metadata_columns,
        params.prefix,
        params.outdir,

    )
}
