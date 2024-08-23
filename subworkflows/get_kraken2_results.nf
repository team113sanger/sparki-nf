include { RUN_KRAKEN2; RUN_KRAKENTOOLS; CLEAN_UP } from '../modules/modules.nf'

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

        // Delete FASTQ files after usage by Kraken2/KrakenTools.
        CLEAN_UP(
            fastq_1,                         // FASTQ 1.
            fastq_2,                         // FASTQ 2.
            RUN_KRAKEN2.out.std_report,      // Standard reports.
            RUN_KRAKENTOOLS.out.mpa_report   // MPA-style reports.
        )
        /******************************************************************
           Note: the process CLEAN_UP will actually not do anything with
           the standard and MPA-style reports - providing these as inputs
           is just a way to make CLEAN_UP start only when RUN_KRAKEN2 and
           RUN_KRAKENTOOLS have finished running.
        *******************************************************************/
            
    emit:
        std_reports = RUN_KRAKEN2.out.std_report
        mpa_reports = RUN_KRAKENTOOLS.out.mpa_report

}