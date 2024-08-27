include { RUN_SPARKI } from '../modules/modules.nf'

workflow REFINE_KRAKEN2_RESULTS {

    take:
        all_std_reports
        all_mpa_reports
        std_reports_dir
        mpa_reports_dir
        organism
        reference_dir
        metadata
        metadata_sample_column
        metadata_columns
        prefix
        domain
        options
        sparki_dir

    main:

        RUN_SPARKI(
            all_std_reports,
            all_mpa_reports,
            std_reports_dir,
            mpa_reports_dir,
            organism,
            reference_dir,
            metadata,
            metadata_sample_column,
            metadata_columns,
            prefix,
            domain,
            options,
            sparki_dir
        )

}
