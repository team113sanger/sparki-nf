# sparki-nf: an end-to-end pathogen identification pipeline

## Introduction
*sparki-nf* is an end-to-end pathogen identification pipeline written in NextFlow that can be used to analyse data from any projects, such as DERMATLAS and FUR. The pipeline leverages the Kraken2 software, whose methodology is briefly described below.

### Kraken2 methodology
Briefly, Kraken2 (Wood *et al*., 2019) splits the sequencing data from a FASTQ file into *k*-mers, from which minimisers are obtained. By calculating a compact hash code for each minimiser, Kraken2 is then able to assign each *k*-mer the appropriate lower common ancestor taxon. When run with the `--report` mode, Kraken2 generates a sample report (herein referred to as 'standard' report) containing all taxa, at different taxonomic ranks, which were identified in the sample; furthermore, if run with the flag `--report-minimizer-data`, the tool also outputs the number of unique minimisers associated with each taxon that were found in the sample. Alternatively, Kraken2 can be run with with the `--report` mode and the flag `--use-mpa-style` to generate MetaPhlAn2 (MPA)-style reports. MPA-style reports can also be generated from 'standard' reports with KrakenTools (Lu *et al*., 2022).

## Pipeline summary
Below is a summary of what the pipeline *sparki-nf* does:
- It runs Kraken2 with the `--report` mode and the flag `--report-minimizer-data` to generate per-sample 'standard' reports.
- It runs the KrakenTools' script `kreport2mpa.py` to generate per-sample MPA-style reports.
- It runs SPARKI to collate and refine the results from the 'standard' and MPA-style reports.



```
module load nextflow
nextflow run main.nf -params-file params.json -c nextflow.config -profile farm22 -stub-run
```