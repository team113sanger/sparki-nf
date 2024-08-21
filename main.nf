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
    path(STD_DIR)
    path(MPA_DIR)
    path(REF_DIR)
    path(METADATA)
    val(COLUMNS)
    val(PREFIX)
    val(DOMAIN)
    val(OPTIONS)
    val(OUTDIR)

    script:
    def RSCRIPT = "/software/team113/dermatlas/R/R-4.2.2/bin/Rscript"
    def SPARKI_CLI = "/lustre/scratch126/casm/team113da/users/jb62/projects/sparki/src/cli.R"
    """
    ${RSCRIPT} ${SPARKI_CLI} \
        --std-reports ${STD_DIR} \
        --mpa-reports ${MPA_DIR} \
        --reference ${REF_DIR}/inspect.txt \
        --metadata ${METADATA} \
        --columns ${COLUMNS} \
        --prefix ${PREFIX} \
        --outdir ${OUTDIR} \
        --domain ${DOMAIN} \
        ${OPTIONS}
    """

}

workflow {
    
    // Read pair of FASTQ files.
    reads_sample_pair = Channel.fromFilePairs(params.fastq_files, checkIfExists: true) // Add .take(1) to limit to a single sample
    // Read Kraken2's reference database.
    reference = file(params.reference_database, checkIfExists: true)
    // Read metadata file.
    metadata = file(params.metadata, checkIfExists: true)

    // Run Kraken2.
    RUN_KRAKEN2(
        reads_sample_pair,           // Pair of FASTQ files (paired-end).
        reference,                   // Path to Kraken2's reference database.
        params.confidence            // Confidence score (e.g. 0.1 [recommended]).
    ).view() 
    
    // Run KrakenTools.
    RUN_KRAKENTOOLS(RUN_KRAKEN2.out.std_report).view()

    // Run SPARKI.
    RUN_SPARKI(
        params.outdir,               // Path to directory with standard and MPA-style reports.
        params.outdir,
        reference,                   // Path to Kraken2's reference database (must be the same used in RUN_KRAKEN2).
        metadata,                    // Path to a metadata table.
        params.metadata_columns,     // Comma-delimited columns names from the metadata table.
        params.prefix,               // Prefix to be added to output files.
        params.domain,               // Domain of interest (e.g. Viruses).
        params.options_for_sparki,   // Additional options for SPARKI (e.g. --verbose).
        params.outdir                // Path to output directory.
    )
    // Note: both standard and MPA-style reports are saved in the same directory (params.outdir),
    // so SPARKI is provided with the same outdir path for both types of reports.
}
