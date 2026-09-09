include { RUN_SPARKI } from '../modules/modules.nf'

workflow REFINE_KRAKEN2_RESULTS {

    take:
        // (meta, standard reports, MPA-style reports) - one item per subcohort.
        // meta.cohort_id names the subcohort and its output directory.
        subcohort_reports
        organism
        reference_dir
        domain
        metadata
        metadata_sample_column
        metadata_columns
        prefix
        verbosity
        samples_to_remove
        flags

    main:

        RUN_SPARKI(
            subcohort_reports,       // Per-subcohort reports, staged into std_reports/ and mpa_reports/.
            organism,                // Organism being analysed, at the species level (e.g. Homo sapiens).
            reference_dir,           // Kraken2's reference database.
            domain,                  // Domain of interest (e.g. Viruses).
            metadata,                // Metadata table.
            metadata_sample_column,  // Sample column in metadata table.
            metadata_columns,        // Comma-delimited column names from the metadata table.
            prefix,                  // Prefix to be added to output files.
            verbosity,               // Whether SPARKI should be run in verbose mode.
            samples_to_remove,       // Samples that should not be included in the SPARKI analysis.
            flags
        )

    emit:
        sparki_results = RUN_SPARKI.out.sparki_results
}
