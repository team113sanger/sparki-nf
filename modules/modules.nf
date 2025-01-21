process BAM_TO_FASTQ {
    publishDir "${params.outdir}/fastq"
    module "samtools-1.14/python-3.12.0"

    input:
        tuple val(SAMPLE_ID), path(BAM)

    output:
        tuple val(SAMPLE_ID), path("*_1.fq.gz"), emit: fastq_1
        tuple val(SAMPLE_ID), path("*_2.fq.gz"), emit: fastq_2

    script:
        """
        samtools view -b -f 4 ${BAM} | \
        samtools collate - -u -O | \
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
// This process will generate a sample-level standard report.
process RUN_KRAKEN2 {
    publishDir "${params.outdir}/std_reports"
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
        touch ${SAMPLE_ID}.kraken
        """

}

// Run KrakenTools' kreport2mpa.py on a sample.
// This process will generate a sample-level MPA-style report.
process RUN_KRAKENTOOLS {
    publishDir "${params.outdir}/mpa_reports"
    module "krakentools/1.2.4"

    input: 
        tuple val(SAMPLE_ID), path(REPORT)
        
    output:
        tuple val(SAMPLE_ID), path("*.kraken.mpa"), emit: mpa_report

    script: 
        """
        kreport2mpa.py \
        --report ${REPORT} \
        --output ${SAMPLE_ID}.kraken.mpa \
        --keep-spaces
        """
        
    stub:
        """
        touch ${SAMPLE_ID}.kraken.mpa
        """

}

// Run SPARKI on a set of samples.
// This process collates the Kraken2/KrakenTools results of a set
// of samples and refines the output to help with the interpretation.
process RUN_SPARKI {
    publishDir "${params.outdir}/logs"
    module "sparki/0.1.0"
   
    input:
        val(ALL_STD_REPORTS)
        val(ALL_MPA_REPORTS)
        // Mandatory inputs for SPARKI.
        path(STD_REPORTS_DIR)
        path(MPA_REPORTS_DIR)
        val(ORGANISM)
        path(REF_DIR)
        val(DOMAIN)
        path(OUTDIR)
        // Optional inputs for SPARKI.
        val(METADATA)
        val(SAMPLE_COL)
        val(COLUMNS)
        val(PREFIX)
        val(VERBOSITY)
        val(SAMPLES_TO_REMOVE)
        val(FLAGS)

    script:
        """
        Rscript -e "${SPARKI_CLI}" \
            --std-reports ${STD_REPORTS_DIR} \
            --mpa-reports ${MPA_REPORTS_DIR} \
            --organism ${ORGANISM} \
            --reference ${REF_DIR}/inspect.txt \
            --outdir ${OUTDIR} \
            --domain ${DOMAIN} \
            --metadata ${METADATA} \
            --sample-col ${SAMPLE_COL} \
            --columns ${COLUMNS} \
            --prefix ${PREFIX} \
            --verbosity ${VERBOSITY} \
            --samples-to-remove ${SAMPLES_TO_REMOVE} \
            ${FLAGS}
        """

    stub:
        """
        echo "USER-DEFINED INPUTS:"
        echo -e "\tStandard reports directory: ${STD_REPORTS_DIR}"
        echo -e "\tMPA-style reports directory: ${MPA_REPORTS_DIR}"
        echo -e "\tOrganism: ${ORGANISM}"
        echo -e "\tKraken2 reference path: ${REF_DIR}"
        echo -e "\tOutput directory for SPARKI results: ${OUTDIR}"
        echo -e "\tDomain(s): ${DOMAIN}"
        echo -e "\tMetadata: ${METADATA}"
        echo -e "\tMetadata sample column: ${SAMPLE_COL}"
        echo -e "\tMetadata columns: ${COLUMNS}"
        echo -e "\tPrefix: ${PREFIX}"
        echo -e "\tVerbose: ${VERBOSITY}"
        echo -e "\tSamples to remove: ${SAMPLES_TO_REMOVE}"
        echo -e "\tFlags: ${FLAGS}"

        echo "SPARKI OUTPUT:"
        touch "${OUTDIR}/sparki.csv"
        """
}
