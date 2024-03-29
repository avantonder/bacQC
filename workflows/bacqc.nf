/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATE INPUTS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def summary_params = NfcoreSchema.paramsSummaryMap(workflow, params)

// Validate input parameters
WorkflowBacQC.initialise(params, log)

// Check input path parameters to see if they exist
def checkPathParamList = [ params.input, params.multiqc_config, params.kraken2db ]
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
if (params.input) { ch_input = file(params.input) } else { exit 1, 'Input samplesheet not specified!' }

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    CONFIG FILES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

ch_multiqc_config        = file("$projectDir/assets/multiqc_config.yml",       checkIfExists: true)
ch_multiqc_custom_config = params.multiqc_config ? file(params.multiqc_config) : []

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//

include { FASTQSCANPARSE as FASTQSCANPARSE_RAW  } from '../modules/local/fastqscanparse'
include { FASTQSCANPARSE as FASTQSCANPARSE_TRIM } from '../modules/local/fastqscanparse'
include { READ_STATS                            } from '../modules/local/read_stats'
include { READSTATS_PARSE                       } from '../modules/local/readstats_parse'
include { KRAKENPARSE                           } from '../modules/local/krakenparse'
include { KRAKENTOOLS_EXTRACT                   } from '../modules/local/krakenextract'

include { INPUT_CHECK                           } from '../subworkflows/local/input_check'
include { FASTQC_FASTP                          } from '../subworkflows/local/fastqc_fastp'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { FASTQSCAN as FASTQSCAN_RAW                      } from '../modules/nf-core/modules/fastqscan/main'
include { FASTQSCAN as FASTQSCAN_TRIM                     } from '../modules/nf-core/modules/fastqscan/main'
include { KRAKEN2_KRAKEN2                                 } from '../modules/nf-core/modules/kraken2/kraken2/main'
include { BRACKEN_BRACKEN                                 } from '../modules/nf-core/modules/bracken/bracken/main'

include { MULTIQC                                         } from '../modules/nf-core/modules/multiqc/main'
include { MULTIQC_TSV_FROM_LIST as MULTIQC_TSV_FAIL_READS } from '../modules/local/multiqc_tsv_from_list'
include { CUSTOM_DUMPSOFTWAREVERSIONS                     } from '../modules/nf-core/modules/custom/dumpsoftwareversions/main' 

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Info required for completion email and summary
def multiqc_report = []
def fail_mapped_reads = [:]

workflow BACQC {

    ch_versions = Channel.empty()

    //
    // SUBWORKFLOW: Read in samplesheet, validate and stage input files
    //
    INPUT_CHECK (
        ch_input
    )
    ch_versions = ch_versions.mix(INPUT_CHECK.out.versions)

    //
    // MODULE: Run fastq-scan
    //
    FASTQSCAN_RAW (
        INPUT_CHECK.out.reads,
        params.genome_size
    )
    ch_fastqscanraw_fastqscanparse = FASTQSCAN_RAW.out.json
    ch_fastqscanraw_readstats      = FASTQSCAN_RAW.out.json
    ch_versions                    = ch_versions.mix(FASTQSCAN_RAW.out.versions.first())

    //
    // MODULE: Run fastqscanparse
    //
    FASTQSCANPARSE_RAW (
        ch_fastqscanraw_fastqscanparse.collect{it[1]}.ifEmpty([])
    )
    ch_versions = ch_versions.mix(FASTQSCANPARSE_RAW.out.versions.first())

    //
    // SUBWORKFLOW: Read QC and trim adapters
    //
    FASTQC_FASTP (
        INPUT_CHECK.out.reads,
        params.save_trimmed_fail,
        false
    )
    ch_variants_fastq = FASTQC_FASTP.out.reads
    ch_versions = ch_versions.mix(FASTQC_FASTP.out.versions)

    //
    // Filter empty FastQ files after adapter trimming
    //
    ch_fail_reads_multiqc = Channel.empty()
    if (!params.skip_fastp) {
        ch_variants_fastq
            .join(FASTQC_FASTP.out.trim_json)
            .map {
                meta, reads, json ->
                    pass = WorkflowBacQC.getFastpReadsAfterFiltering(json) > 0
                    [ meta, reads, json, pass ]
            }
            .set { ch_pass_fail_reads }

        ch_pass_fail_reads
            .map { meta, reads, json, pass -> if (pass) [ meta, reads ] }
            .set { ch_variants_fastq }

        ch_pass_fail_reads
            .map {
                meta, reads, json, pass ->
                if (!pass) {
                    fail_mapped_reads[meta.id] = 0
                    num_reads = WorkflowBacQC.getFastpReadsBeforeFiltering(json)
                    return [ "$meta.id\t$num_reads" ]
                }
            }
            .set { ch_pass_fail_reads }

        MULTIQC_TSV_FAIL_READS (
            ch_pass_fail_reads.collect(),
            ['Sample', 'Reads before trimming'],
            'fail_mapped_reads'
        )
        .set { ch_fail_reads_multiqc }
    }

    //
    // MODULE: Run fastq-scan
    //
    FASTQSCAN_TRIM (
        ch_variants_fastq,
        params.genome_size
    )
    ch_fastqscantrim_fastqscanparse = FASTQSCAN_TRIM.out.json
    ch_versions                     = ch_versions.mix(FASTQSCAN_TRIM.out.versions.first())

    //
    // MODULE: Run fastqscanparse
    //
    FASTQSCANPARSE_TRIM (
            ch_fastqscantrim_fastqscanparse.collect{it[1]}.ifEmpty([])
    )
    ch_versions = ch_versions.mix(FASTQSCANPARSE_TRIM.out.versions.first())
    
    //
    // MODULE: Calculate read stats
    //
    ch_fastqscanraw_readstats                           // tuple val(meta), path(json)
        .join( FASTQSCAN_TRIM.out.json )                // tuple val(meta), path(json) 
        .set { ch_readstats }                           // tuple val(meta), path(json), path(json)

    READ_STATS (
        ch_readstats
    )
    ch_readstats_readstatsparse = READ_STATS.out.csv
    ch_versions                 = ch_versions.mix(READ_STATS.out.versions.first())

    //
    // MODULE: Summarise read stats outputs
    //
    READSTATS_PARSE (
        ch_readstats_readstatsparse.collect{it[1]}.ifEmpty([])
    )
    ch_versions = ch_versions.mix(READSTATS_PARSE.out.versions.first())
    
    //
    // MODULE: Run kraken2
    //  
    ch_kraken2_multiqc = Channel.empty()
    ch_kraken2db       = Channel.empty()
    if (!params.skip_kraken2) {
        ch_kraken2db = file(params.kraken2db)
        
        KRAKEN2_KRAKEN2 (
                ch_variants_fastq,
                ch_kraken2db
            )
        ch_kraken2_bracken             = KRAKEN2_KRAKEN2.out.txt
        ch_kraken2_krakenparse         = KRAKEN2_KRAKEN2.out.txt
        ch_kraken2_multiqc             = KRAKEN2_KRAKEN2.out.txt
        ch_versions                    = ch_versions.mix(KRAKEN2_KRAKEN2.out.versions.first().ifEmpty(null))
        //
        // MODULE: Run bracken
        //
        BRACKEN_BRACKEN (
                ch_kraken2_bracken,
                ch_kraken2db
            )
        ch_bracken_krakenparse = BRACKEN_BRACKEN.out.reports
        ch_versions            = ch_versions.mix(BRACKEN_BRACKEN.out.versions.first())

        //
        // MODULE: Run krakenparse
        //
        KRAKENPARSE (
                ch_kraken2_krakenparse.collect{it[1]}.ifEmpty([]),
                ch_bracken_krakenparse.collect{it[1]}.ifEmpty([])
            )
        ch_versions = ch_versions.mix(KRAKENPARSE.out.versions.first())
    }
    
    //
    // MODULE: Run krakentools extract
    // 
    if (params.kraken_extract) {
        ch_variants_fastq
            .join(KRAKEN2_KRAKEN2.out.output)
            .join(KRAKEN2_KRAKEN2.out.txt)
            .map {
                meta, reads, output, txt -> [ meta, reads, output, txt]
            }
            .set { ch_krakenextract }

        KRAKENTOOLS_EXTRACT (
                ch_krakenextract,
                params.tax_id
        )
        ch_versions = ch_versions.mix(KRAKENTOOLS_EXTRACT.out.versions.first().ifEmpty(null))
    }
    
    //
    // MODULE: Collate software versions
    //
    CUSTOM_DUMPSOFTWAREVERSIONS (
        ch_versions.unique().collectFile(name: 'collated_versions.yml')
    )

    //
    // MODULE: MultiQC
    //
    workflow_summary    = WorkflowBacQC.paramsSummaryMultiqc(workflow, summary_params)
    ch_workflow_summary = Channel.value(workflow_summary)

    MULTIQC (
        ch_multiqc_config,
        ch_multiqc_custom_config,
        CUSTOM_DUMPSOFTWAREVERSIONS.out.mqc_yml.collect(),
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'),
        ch_fail_reads_multiqc.ifEmpty([]),
        FASTQC_FASTP.out.fastqc_raw_zip.collect{it[1]}.ifEmpty([]),
        FASTQC_FASTP.out.trim_json.collect{it[1]}.ifEmpty([]),
        ch_kraken2_multiqc.collect{it[1]}.ifEmpty([])
    )
    multiqc_report = MULTIQC.out.report.toList()
    ch_versions    = ch_versions.mix(MULTIQC.out.versions)
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    COMPLETION EMAIL AND SUMMARY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow.onComplete {
    if (params.email || params.email_on_fail) {
        NfcoreTemplate.email(workflow, params, summary_params, projectDir, log, multiqc_report, fail_mapped_reads)
    }
    NfcoreTemplate.summary(workflow, params, log)
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/