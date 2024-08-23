include { RUN_KRAKEN2; RUN_KRAKENTOOLS } from '../modules/modules.nf'

workflow GET_KRAKEN2_RESULTS {

    take:
        reads
        reference_dir
        confidence_score
        options

    main:
        RUN_KRAKEN2(reads, reference_dir, confidence_score, options)
        RUN_KRAKENTOOLS(RUN_KRAKEN2.out.std_report)
            
    emit:
        std_reports = RUN_KRAKEN2.out.std_report
        mpa_reports = RUN_KRAKENTOOLS.out.mpa_report

}