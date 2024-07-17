#!/bin/bash

# BSUB -q normal
# BSUB -o /lustre/scratch126/casm/team113da/users/jb62/projects/sparki-nf/test/logs/bam_to_fastq.out
# BSUB -e /lustre/scratch126/casm/team113da/users/jb62/projects/sparki-nf/test/logs/bam_to_fastq.err
# BSUB -J bam_to_fastq
# BSUB -R "select[mem>20GB] rusage[mem=20GB] span[hosts=1]"
# BSUB -M 20GB

BAMS=$(ls /lustre/scratch126/casm/team113da/projects/5765_2680_sebaceous_tumour_RNAseq_remap/bams/*.bam | head -5)
OUTDIR="/lustre/scratch126/casm/team113da/users/jb62/projects/sparki-nf/test/data"

module load samtools/1.14

for BAM in ${BAMS}; do
    SAMPLE_NAME=$(basename ${BAM} ".bam")
    echo "Running ${SAMPLE_NAME}"
    samtools collate -u -O ${BAM} | samtools fastq -c 6 -@ 8 -1 ${OUTDIR}/${SAMPLE_NAME}_1.fq.gz -2 ${OUTDIR}/${SAMPLE_NAME}_2.fq.gz -0 /dev/null -s /dev/null -n
done
