include { RUN_KRAKEN2; RUN_KRAKENTOOLS } from '../modules/modules.nf'

workflow GET_KRAKEN2_RESULTS {

    take:
        fastq_1
        fastq_2
        reference_dir
        confidence_score

    main:

        // Run Kraken2 to get standard reports.
        RUN_KRAKEN2(fastq_1, fastq_2, reference_dir, confidence_score)

        // Run KrakenTools to get MPA-style reports.
        RUN_KRAKENTOOLS(RUN_KRAKEN2.out.std_report)
            
    emit:
        std_reports = RUN_KRAKEN2.out.std_report
        mpa_reports = RUN_KRAKENTOOLS.out.mpa_report

}