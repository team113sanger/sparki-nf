#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

process RUN_KRAKEN2 {
  publishDir "${params.kraken_outdir}", mode: "copy"
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
    pwd
    echo "Running Kraken2 on sample ${SAMPLE_ID}..."
    echo -e "\tUsing reference database from ${REF_DIR}"
    echo -e "\tUsing a confidence score of ${C_SCORE}"
    echo -e "\tCreating standard report ${SAMPLE_ID}.kraken"
    touch ${SAMPLE_ID}.kraken
    echo -e " 64.01\t32926460\t32926460\t0\t0\tU\t0\tunclassified" >> ${SAMPLE_ID}.kraken
    echo -e " 35.99\t18513589\t32699\t202279022\t6471685\tR\t1\troot" >> ${SAMPLE_ID}.kraken
    echo -e " 35.93\t18480884\t1148606\t201977282\t6471685\tR1\t131567\tcellular organisms" >> ${SAMPLE_ID}.kraken
    echo -e " 33.69\t17329988\t326720\t192969933\t6439972\tD\t2759\tEukaryota" >> ${SAMPLE_ID}.kraken
    echo -e " 33.05\t17002848\t5608\t189819013\t6402361\tD1\t33154\tOpisthokonta" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tK\t33208\tMetazoa" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tK1\t6072\tEumetazoa" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tK2\t33213\tBilateria" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tK3\t33511\tDeuterostomia" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tP\t7711\tChordata" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tP1\t89593\tCraniata" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tP2\t7742\tVertebrata" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tP3\t7776\tGnathostomata" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tP4\t117570\tTeleostomi" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tP5\t117571\tEuteleostomi" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tP6\t8287\tSarcopterygii" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tP7\t1338369\tDipnotetrapodomorpha" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tP8\t32523\tTetrapoda" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tP9\t32524\tAmniota" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tC\t40674\tMammalia" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tC1\t32525\tTheria" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tC2\t9347\tEutheria" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tC3\t1437010\tBoreoeutheria" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tC4\t314146\tEuarchontoglires" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tO\t9443\tPrimates" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tO1\t376913\tHaplorrhini" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tO2\t314293\tSimiiformes" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tO3\t9526\tCatarrhini" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tO4\t314295\tHominoidea" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tF\t9604\tHominidae" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tF1\t207598\tHomininae" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t0\t189756889\t6402361\tG\t9605\tHomo" >> ${SAMPLE_ID}.kraken
    echo -e " 33.04\t16997144\t16997144\t189756889\t6402361\tS\t9606\tHomo sapiens" >> ${SAMPLE_ID}.kraken
    """

}

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

    echo -e "d__Eukaryota\t17329988" >> ${SAMPLE_ID}.kraken.mpa
    echo -e "d__Eukaryota|k__Metazoa\t16997144" >> ${SAMPLE_ID}.kraken.mpa
    echo -e "d__Eukaryota|k__Metazoa|p__Chordata\t16997144" >> ${SAMPLE_ID}.kraken.mpa
    echo -e "d__Eukaryota|k__Metazoa|p__Chordata|c__Mammalia\t16997144" >> ${SAMPLE_ID}.kraken.mpa
    echo -e "d__Eukaryota|k__Metazoa|p__Chordata|c__Mammalia|o__Primates\t16997144" >> ${SAMPLE_ID}.kraken.mpa
    echo -e "d__Eukaryota|k__Metazoa|p__Chordata|c__Mammalia|o__Primates|f__Hominidae\t16997144" >> ${SAMPLE_ID}.kraken.mpa
    echo -e "d__Eukaryota|k__Metazoa|p__Chordata|c__Mammalia|o__Primates|f__Hominidae|g__Homo\t16997144" >> ${SAMPLE_ID}.kraken.mpa
    echo -e "d__Eukaryota|k__Metazoa|p__Chordata|c__Mammalia|o__Primates|f__Hominidae|g__Homo|s__Homo sapiens\t16997144" >> ${SAMPLE_ID}.kraken.mpa
    """

}

process RUN_SPARKI {
  publishDir "${params.sparki_outdir}", mode: "copy"
    
  input:
    path(SPARKI_INFILES)
    path(REF_DIR)
    path(METADATA)
    val(COLUMNS)
    val(PREFIX)
    val(DOMAIN)
    val(OPTIONS)
    path(SPARKI_OUTDIR)

  script:
    def RSCRIPT = "/software/team113/dermatlas/R/R-4.2.2/bin/Rscript"
    def SPARKI_CLI = "/lustre/scratch126/casm/team113da/users/jb62/projects/sparki/src/cli.R"
    """
    ${RSCRIPT} ${SPARKI_CLI} \
      --std-reports ${SPARKI_INFILES} \
      --mpa-reports ${SPARKI_INFILES} \
      --reference ${REF_DIR}/inspect.txt \
      --metadata ${METADATA} \
      --columns ${COLUMNS} \
      --prefix ${PREFIX} \
      --outdir ${SPARKI_OUTDIR} \
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

workflow {
    
  // Read pair of FASTQ files.
  reads_sample_pair = Channel.fromFilePairs(params.fastq_files, checkIfExists: true) // Add .take(1) to limit to a single sample
  // Read Kraken2's reference database.
  reference = file(params.reference_database, checkIfExists: true)
  // Read metadata file.
  metadata = file(params.metadata, checkIfExists: true)
  cscore = Channel.of(params.confidence)

  sparki_infiles = channel.fromPath(params.kraken_outdir, type: 'dir')
  sparki_outfiles = channel.fromPath(params.sparki_outdir, type: 'dir')

  
  RUN_KRAKEN2(reads_sample_pair, reference, cscore) | RUN_KRAKENTOOLS.collect() // Run KrakenTools.

    
    // Run SPARKI.
  RUN_SPARKI(
    sparki_infiles,
    reference, // Path to Kraken2's reference database (must be the same used in RUN_KRAKEN2).
    metadata,  // Path to a metadata table.
    params.metadata_columns,     // Comma-delimited columns names from the metadata table.
    params.prefix,   // Prefix to be added to output files.
    params.domain,   // Domain of interest (e.g. Viruses).
    params.options_for_sparki,   // Additional options for SPARKI (e.g. --verbose).
    sparki_outfiles    // Path to output directory.
  )
  // Note: both standard and MPA-style reports are saved in the same directory (params.outdir),
  // so SPARKI is provided with the same outdir path for both types of reports.

}
