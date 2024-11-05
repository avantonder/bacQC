/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { paramsSummaryMap         } from 'plugin/nf-validation'
include { paramsSummaryMultiqc     } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText   } from '../subworkflows/local/utils_bacqc_pipeline'
include { validateInputSamplesheet } from '../subworkflows/local/utils_bacqc_pipeline'
include { validateParameters; paramsHelp; paramsSummaryLog; fromSamplesheet } from 'plugin/nf-validation'

// Check input path parameters to see if they exist
def checkPathParamList = [ params.input, params.multiqc_config, params.kraken2db, params.kronadb,
                           params.multiqc_logo, params.multiqc_methods_description ]
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
if ( params.input ) {
    ch_input = file(params.input, checkIfExists: true)
} else {
    error("Input samplesheet not specified")
}

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

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { FASTQSCAN as FASTQSCAN_RAW                      } from '../modules/nf-core/fastqscan/main'
include { FASTQSCAN as FASTQSCAN_TRIM                     } from '../modules/nf-core/fastqscan/main'
include { KRAKEN2_KRAKEN2                                 } from '../modules/nf-core/kraken2/kraken2/main'
include { BRACKEN_BRACKEN                                 } from '../modules/nf-core/bracken/main'
include { KRONA_KTIMPORTTAXONOMY                          } from '../modules/nf-core/krona/ktimporttaxonomy/main'
include { MULTIQC                                         } from '../modules/nf-core/multiqc/main'

include { FASTQ_TRIM_FASTP_FASTQC     } from '../subworkflows/nf-core/fastq_trim_fastp_fastqc/main'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Info required for completion email and summary
def multiqc_report = []
def fail_mapped_reads = [:]

workflow BACQC {

    take:
    ch_samplesheet // channel: samplesheet read in from --input

    main:
    
    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    //
    // MODULE: Run fastq-scan
    //
    FASTQSCAN_RAW (
        ch_samplesheet,
        params.genome_size
    )
    ch_fastqscanraw_fastqscanparse = FASTQSCAN_RAW.out.json
    ch_fastqscanraw_readstats      = FASTQSCAN_RAW.out.json
    ch_versions                    = ch_versions.mix(FASTQSCAN_RAW.out.versions)

    //
    // MODULE: Run fastqscanparse
    //
    FASTQSCANPARSE_RAW (
        ch_fastqscanraw_fastqscanparse.collect{it[1]}.ifEmpty([])
    )
    ch_versions = ch_versions.mix(FASTQSCANPARSE_RAW.out.versions)

    //
    // MODULE: FASTQ_TRIM_FASTP_FASTQC
    //

    FASTQ_TRIM_FASTP_FASTQC (
        ch_samplesheet,
        params.adapter_fasta ?: [],
        params.save_trimmed_fail,
        params.save_merged,
        params.skip_fastp,
        params.skip_fastqc
    )
    ch_multiqc_files = ch_multiqc_files.mix(FASTQ_TRIM_FASTP_FASTQC.out.fastqc_raw_zip.collect{it[1]})
    ch_multiqc_files = ch_multiqc_files.mix(FASTQ_TRIM_FASTP_FASTQC.out.fastqc_trim_zip.collect{it[1]})
    ch_versions = ch_versions.mix(FASTQ_TRIM_FASTP_FASTQC.out.versions)
    ch_filtered_reads = FASTQ_TRIM_FASTP_FASTQC.out.reads

    //
    // MODULE: Run fastq-scan
    //
    FASTQSCAN_TRIM (
        ch_filtered_reads,
        params.genome_size
    )
    ch_fastqscantrim_fastqscanparse = FASTQSCAN_TRIM.out.json
    ch_versions                     = ch_versions.mix(FASTQSCAN_TRIM.out.versions)

    //
    // MODULE: Run fastqscanparse
    //
    FASTQSCANPARSE_TRIM (
            ch_fastqscantrim_fastqscanparse.collect{it[1]}.ifEmpty([])
    )
    ch_versions = ch_versions.mix(FASTQSCANPARSE_TRIM.out.versions)
    
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
    ch_versions                 = ch_versions.mix(READ_STATS.out.versions)

    //
    // MODULE: Summarise read stats outputs
    //
    READSTATS_PARSE (
        ch_readstats_readstatsparse.collect{it[1]}.ifEmpty([])
    )
    ch_versions = ch_versions.mix(READSTATS_PARSE.out.versions)
    
    //
    // MODULE: Run kraken2
    //  
    ch_kraken2_multiqc = Channel.empty()
    ch_kraken2db       = Channel.empty()
    ch_kronadb         = Channel.empty()
    if (!params.skip_kraken2) {
        ch_kraken2db = file(params.kraken2db)
        ch_kronadb   = file(params.kronadb)
        
        KRAKEN2_KRAKEN2 (
                ch_filtered_reads,
                ch_kraken2db,
                params.save_output_fastqs,
                params.save_reads_assignment
            )
        ch_kraken2_bracken             = KRAKEN2_KRAKEN2.out.report
        ch_kraken2_krakenparse         = KRAKEN2_KRAKEN2.out.report
        ch_kraken2_multiqc             = KRAKEN2_KRAKEN2.out.report
        ch_versions                    = ch_versions.mix(KRAKEN2_KRAKEN2.out.versions.first().ifEmpty(null))
        //
        // MODULE: Run bracken
        //
        BRACKEN_BRACKEN (
                ch_kraken2_bracken,
                ch_kraken2db
            )
        ch_bracken_krakenparse = BRACKEN_BRACKEN.out.bracken_report
        ch_bracken_krona       = BRACKEN_BRACKEN.out.bracken_report
        ch_versions            = ch_versions.mix(BRACKEN_BRACKEN.out.versions)

        //
        // MODULE: Run krakenparse
        //
        KRAKENPARSE (
                ch_kraken2_krakenparse.collect{it[1]}.ifEmpty([]),
                ch_bracken_krakenparse.collect{it[1]}.ifEmpty([])
            )
        ch_versions = ch_versions.mix(KRAKENPARSE.out.versions)

        //
        // MODULE: Run krona
        //
        KRONA_KTIMPORTTAXONOMY (
                ch_bracken_krona,
                ch_kronadb
            )
        ch_versions = ch_versions.mix(KRONA_KTIMPORTTAXONOMY.out.versions)
    }
    
    //
    // MODULE: Run krakentools extract
    // 
    if (params.kraken_extract) {
        ch_filtered_reads
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
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_pipeline_software_mqc_versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }

    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = Channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        Channel.fromPath(params.multiqc_config, checkIfExists: true) :
        Channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        Channel.fromPath("${workflow.projectDir}/docs/images/bacqc_logo.png", checkIfExists: true)

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))

    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    ch_multiqc_files = ch_multiqc_files.mix( FASTQC_FINAL.out.zip.collect{it[1]}.ifEmpty([]) )
   
    if (!params.skip_kraken2) {
        ch_multiqc_files = ch_multiqc_files.mix( BRACKEN_BRACKEN.out.bracken_kraken_style_report.collect{it[1]}.ifEmpty([]) )
    }
    
    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:
    multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/