include { RUN_SPARKI } from '../modules/modules.nf'

workflow REFINE_KRAKEN2_RESULTS {
  take:
    std_reports
    mpa_reports
    reference_dir
    metadata
    metadata_columns
    prefix
    domain
    options
    outdir

  main:
    RUN_SPARKI(
      std_reports,
      mpa_reports,
      reference_dir,
      metadata,
      metadata_columns,
      prefix,
      domain,
      options,
      outdir
    )
}
