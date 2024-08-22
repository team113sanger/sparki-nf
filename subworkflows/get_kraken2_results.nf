include { RUN_KRAKEN2; RUN_KRAKENTOOLS } from '../modules/modules.nf'

workflow GET_KRAKEN2_RESULTS {

    take:
        reads
        reference_dir
        confidence_score
        options

    main:
        RUN_KRAKEN2(reads, reference_dir, confidence_score, options)
            .map { it[1] }
            .collect()
            .set { kraken2_std_reports }
        kraken2_std_reports.view()

        RUN_KRAKENTOOLS(RUN_KRAKEN2.out.std_report)
            .map { it[1] }
            .collect()
            .set { kraken2_mpa_reports }
        kraken2_mpa_reports.view()

    emit:
        std_reports = kraken2_std_reports
        mpa_reports = kraken2_mpa_reports

}