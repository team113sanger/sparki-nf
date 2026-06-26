include { RUN_SPARKI } from '../modules/modules.nf'

workflow REFINE_KRAKEN2_RESULTS {

    take:
        all_std_reports
        all_mpa_reports
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
            all_std_reports,         // Standard reports (staged into std_reports/).
            all_mpa_reports,         // MPA-style reports (staged into mpa_reports/).
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
}
