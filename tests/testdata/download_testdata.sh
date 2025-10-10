#!/bin/bash

# Output directory relative to path/to/sparki-nf (i.e. you must be inside the sparki-nf
# repo directory for this to work!)
OUTDIR="./tests/testdata"

#####################
# Getting BAM files #
#####################

#### 1 - Download CRAMs ####

mkdir -p ${OUTDIR}/cram_files/
wget -P ${OUTDIR}/cram_files/ -nc ftp://ftp.sra.ebi.ac.uk/vol1/run/ERR125/ERR12549242/46643_1%235.cram
wget -P ${OUTDIR}/cram_files/ -nc ftp://ftp.sra.ebi.ac.uk/vol1/run/ERR125/ERR12549242/46643_1%235.cram.crai
wget -P ${OUTDIR}/cram_files/ -nc ftp://ftp.sra.ebi.ac.uk/vol1/run/ERR125/ERR12549245/46643_1%2311.cram
wget -P ${OUTDIR}/cram_files/ -nc ftp://ftp.sra.ebi.ac.uk/vol1/run/ERR125/ERR12549245/46643_1%2311.cram.crai
wget -P ${OUTDIR}/cram_files/ -nc ftp://ftp.sra.ebi.ac.uk/vol1/run/ERR125/ERR12549246/46643_1%2314.cram
wget -P ${OUTDIR}/cram_files/ -nc ftp://ftp.sra.ebi.ac.uk/vol1/run/ERR125/ERR12549246/46643_1%2314.cram.crai

#### 2 - Convert CRAMs to BAMs ####

# 2.1 - Retrieve reference genome
mkdir -p ${OUTDIR}/felis_catus_reference_genome/
wget -P ${OUTDIR}/felis_catus_reference_genome/ -nc https://ftp.ensembl.org/pub/release-104/fasta/felis_catus/dna/Felis_catus.Felis_catus_9.0.dna.toplevel.fa.gz
gunzip ${OUTDIR}/felis_catus_reference_genome/Felis_catus.Felis_catus_9.0.dna.toplevel.fa.gz

# 2.2 - Index reference genome
docker run -v ${OUTDIR}/:/opt/data/ quay.io/biocontainers/samtools:1.22--h96c455f_0 \
    samtools faidx "/opt/data/felis_catus_reference_genome/Felis_catus.Felis_catus_9.0.dna.toplevel.fa"

# 2.3 - Generate BAMs
mkdir -p ${OUTDIR}/bam_files/
for SAMPLE in "46643_1#5" "46643_1#11" "46643_1#14"; do
    docker run -v ${OUTDIR}/:/opt/data/ quay.io/biocontainers/samtools:1.22--h96c455f_0 \
        samtools view \
            -b \
            -T "/opt/data/felis_catus_reference_genome/Felis_catus.Felis_catus_9.0.dna.toplevel.fa" \
            -o "/opt/data/bam_files/${SAMPLE}.bam" \
            "/opt/data/cram_files/${SAMPLE}.cram"
done

#######################
# Getting FASTQ files #
#######################

mkdir -p ${OUTDIR}/fastq_files/
wget -P ${OUTDIR}/fastq_files/ -nc ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR125/042/ERR12549242/ERR12549242_1.fastq.gz
wget -P ${OUTDIR}/fastq_files/ -nc ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR125/042/ERR12549242/ERR12549242_2.fastq.gz
wget -P ${OUTDIR}/fastq_files/ -nc ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR125/045/ERR12549245/ERR12549245_1.fastq.gz
wget -P ${OUTDIR}/fastq_files/ -nc ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR125/045/ERR12549245/ERR12549245_2.fastq.gz
wget -P ${OUTDIR}/fastq_files/ -nc ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR125/046/ERR12549246/ERR12549246_1.fastq.gz
wget -P ${OUTDIR}/fastq_files/ -nc ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR125/046/ERR12549246/ERR12549246_2.fastq.gz

########################################
# Getting a Kraken2 reference database #
########################################

wget -P ${OUTDIR}/ -nc https://genome-idx.s3.amazonaws.com/kraken/k2_pluspfp_16gb_20230314.tar.gz
mkdir -p ${OUTDIR}/kraken2_reference/
tar -xvzf ${OUTDIR}/k2_pluspfp_16gb_20230314.tar.gz -C ${OUTDIR}/kraken2_reference/
rm -f ${OUTDIR}/k2_pluspfp_16gb_20230314.tar.gz
