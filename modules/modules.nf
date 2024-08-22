process BAM_TO_FASTQ {
  publishDir "${params.fastq_outdir}", mode: "copy"
  module "samtools-1.14/python-3.12.0"

  input:
    path(BAM)

  output:
    tuple val(SAMPLE_ID), path("*_1.fq.gz"), emit: fastq_1
    tuple val(SAMPLE_ID), path("*_2.fq.gz"), emit: fastq_2

  script:
    def SAMPLE_ID = BAM.getSimpleName()
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
}

// Run Kraken2 on a sample.
// This process will generate a standard report.
process RUN_KRAKEN2 {
  publishDir "${params.kraken_outdir}", mode: "copy"
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
  publishDir "${params.kraken_outdir}", mode: "copy"
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
  publishDir "${params.sparki_outdir}", mode: "copy"
    
  input:
    path(STD_REPORTS)
    path(MPA_REPORTS)
    path(REF_DIR)
    path(METADATA)
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
      --columns ${COLUMNS} \
      --prefix ${PREFIX} \
      --outdir ${OUTDIR} \
      --domain ${DOMAIN} \
      ${OPTIONS}
    """

  stub:
    """
    pwd
    echo "${SPARKI_INFILES}"
    echo "${REF_DIR}"
    echo "${METADATA}"
    echo "${COLUMNS}"
    echo "${PREFIX}"
    echo "${SPARKI_OUTDIR}"
    echo "${DOMAIN}"
    echo "${OPTIONS}"
    touch "${SPARKI_OUTDIR}/merged_reports.tsv"
    """

}
