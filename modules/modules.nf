process BAM_TO_FASTQ {
    publishDir "${params.outdir}/fastq", mode: "copy"
    module "samtools-1.14/python-3.12.0"

    input:
        tuple val(SAMPLE_ID), path(BAM)

    output:
        tuple val(SAMPLE_ID), path("*_1.fq.gz"), emit: fastq_1
        tuple val(SAMPLE_ID), path("*_2.fq.gz"), emit: fastq_2

    script:
        """
        samtools collate -u -O ${BAM} | \
        samtools fastq \
        -c 6 \
        -@ 8 \
        -1 ${SAMPLE_ID}_1.fq.gz \
        -2 ${SAMPLE_ID}_2.fq.gz \
        -0 /dev/null \
        -s /dev/null \
        -n
        """

    stub:
        """
        touch ${SAMPLE_ID}_1.fq.gz
        touch ${SAMPLE_ID}_2.fq.gz
        """
}

// Run Kraken2 on a sample.
// This process will generate a standard report.
process RUN_KRAKEN2 {
    publishDir "${params.outdir}/std_reports", mode: "copy"
    module "kraken2/2.1.2"

    input: 
        tuple val(SAMPLE_ID), path(FASTQ1)
        tuple val(SAMPLE_ID), path(FASTQ2)
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
        --output /dev/null \
        ${FASTQ1} ${FASTQ2} 
        """
        
    stub:
        """
        pwd
        echo "Running Kraken2 on sample ${SAMPLE_ID}..."
        echo -e "\tUsing reference database from ${REF_DIR}"
        echo -e "\tUsing a confidence score of ${C_SCORE}"
        echo -e "\tCreating standard report ${SAMPLE_ID}.kraken"
        touch ${SAMPLE_ID}.kraken
        """

}

// Run KrakenTools on a sample.
// This process will generate an MPA-style report.
process RUN_KRAKENTOOLS {
    publishDir "${params.outdir}/mpa_reports", mode: "copy"
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
        pwd
        echo "Running KrakenTools on sample ${SAMPLE_ID}..."
        echo -e "\tPath to standard report: ${REPORT}"
        echo -e "\tCreating MPA-style report ${SAMPLE_ID}.kraken.mpa"
        touch ${SAMPLE_ID}.kraken.mpa
        """

}


// Run SPARKI on a set of samples.
// This process collates the Kraken2/KrakenTools results of a set
// of samples and refines the output to help with the interpretation.
process RUN_SPARKI {
   
    input:
        val(STD)
        val(MPA)
        path(STD_REPORTS)
        path(MPA_REPORTS)
        path(REF_DIR)
        path(METADATA)
        val(SAMPLE_COL)
        val(COLUMNS)
        val(PREFIX)
        val(DOMAIN)
        val(OPTIONS)
        path(OUTDIR)

    script:
        def RSCRIPT = "/software/team113/dermatlas/R/R-4.2.2/bin/Rscript"
        def SPARKI_CLI = "/lustre/scratch126/casm/team113da/users/jb62/projects/sparki/src/cli.R"
        """
        ${RSCRIPT} ${SPARKI_CLI} \
        --std-reports ${STD_REPORTS} \
        --mpa-reports ${MPA_REPORTS} \
        --reference ${REF_DIR}/inspect.txt \
        --metadata ${METADATA} \
        --sample-col ${SAMPLE_COL} \
        --columns ${COLUMNS} \
        --prefix ${PREFIX} \
        --outdir ${OUTDIR} \
        --domain ${DOMAIN} \
        ${OPTIONS}
        """

    stub:
        """
        pwd
        echo "${STD_REPORTS}"
        echo "${MPA_REPORTS}"
        echo "${REF_DIR}"
        echo "${METADATA}"
        echo "${COLUMNS}"
        echo "${PREFIX}"
        echo "${OUTDIR}"
        echo "${DOMAIN}"
        echo "${OPTIONS}"
        touch "${OUTDIR}/merged_reports.tsv"
        """

}
