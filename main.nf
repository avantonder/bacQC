#!/usr/bin/env nextflow
/*
========================================================================================
                         avantonder/bacQC
========================================================================================
 avantonder/bacQC Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/avantonder/bacQC
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

////////////////////////////////////////////////////
/* --               PRINT HELP                 -- */
////////////////////////////////////////////////////

def json_schema = "$projectDir/nextflow_schema.json"
if (params.help) {
    def command = "nextflow run avantonder/bacQC --input samplesheet.csv --kraken2db path/to/kraken2/database --brackendb path/to/bracken/database -profile docker"
    log.info Schema.params_help(workflow, params, json_schema, command)
    exit 0
}

////////////////////////////////////////////////////
/* --         PRINT PARAMETER SUMMARY          -- */
////////////////////////////////////////////////////

def summary_params = Schema.params_summary_map(workflow, params, json_schema)
log.info Schema.params_summary_log(workflow, params, json_schema)

////////////////////////////////////////////////////
/* --          PARAMETER CHECKS                -- */
////////////////////////////////////////////////////

// Check that conda channels are set-up correctly
if (params.enable_conda) {
    Checks.check_conda_channels(log)
}

// Check AWS batch settings
Checks.aws_batch(workflow, params)

// Check the hostnames against configured profiles
Checks.hostname(workflow, params, log)

////////////////////////////////////////////////////
/* --          VALIDATE INPUTS                 -- */
////////////////////////////////////////////////////

checkPathParamList = [ params.input, params.kraken2db, params.brackendb, params.multiqc_config ]
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
if (params.input) { ch_input = file(params.input) } else { exit 1, 'Input samplesheet not specified!' }
if (params.kraken2db) { ch_kraken2db = file(params.kraken2db) } else { exit 1, 'kraken2 database not specified!' }
if (params.brackendb) { ch_brackendb = file(params.brackendb) } else { exit 1, 'bracken database not specified!' }

////////////////////////////////////////////////////
/* --          CONFIG FILES                    -- */
////////////////////////////////////////////////////

ch_multiqc_config        = file("$projectDir/assets/multiqc_config.yaml", checkIfExists: true)
ch_multiqc_custom_config = params.multiqc_config ? Channel.fromPath(params.multiqc_config) : Channel.empty()

////////////////////////////////////////////////////
/* --       IMPORT MODULES / SUBWORKFLOWS      -- */
////////////////////////////////////////////////////

// Don't overwrite global params.modules, create a copy instead and use that within the main script.
def modules = params.modules.clone()
def multiqc_options   = modules['multiqc']
multiqc_options.args += params.multiqc_title ? Utils.joinModuleArgs(["--title \"$params.multiqc_title\""]) : ''

// Local: Modules
include { GET_SOFTWARE_VERSIONS } from './modules/local/get_software_versions'     addParams( options: [publish_files : ['csv':'']] )
include { BRACKEN } from './modules/local/bracken'                                 addParams( options: modules['bracken'])
include { KRAKENPARSE } from './modules/local/krakenparse'                         addParams( options: modules['krakenparse'])

// nf-core: Modules
include { KRAKEN2_RUN } from './modules/nf-core/software/kraken2/run/main'          addParams( options: modules['kraken2_run'])
include { MULTIQC } from './modules/nf-core/software/multiqc/main'                  addParams( options: modules['multiqc'])

// Local: Sub-workflows
def fastp_options   = modules['fastp']

include { INPUT_CHECK       } from './modules/local/subworkflow/input_check'        addParams( options: [:] )
include { FASTQC_FASTP      } from './subworkflows/nf-core/fastqc_fastp'            addParams( fastqc_raw_options: modules['fastqc_raw'], fastqc_trim_options: modules['fastqc_trim'], fastp_options: fastp_options )

////////////////////////////////////////////////////
/* --           RUN MAIN WORKFLOW              -- */
////////////////////////////////////////////////////

// Info required for completion email and summary
def multiqc_report = []

workflow {

    ch_software_versions = Channel.empty()

    /*
     * SUBWORKFLOW: Read in samplesheet, validate and stage input files
     */
    INPUT_CHECK ( 
        ch_input
    )

    /*
     * SUBWORKFLOW: Read QC and trim adapters
     */
    FASTQC_FASTP (
        INPUT_CHECK.out.sample_info
    )
    ch_reads    = FASTQC_FASTP.out.reads
    ch_software_versions = ch_software_versions.mix(FASTQC_FASTP.out.fastqc_version.first().ifEmpty(null))
    ch_software_versions = ch_software_versions.mix(FASTQC_FASTP.out.fastp_version.first().ifEmpty(null))

    /*
    * MODULE: Run kraken2
    */
    ch_kraken2_multiqc = Channel.empty()
    KRAKEN2_RUN (
            ch_reads,
            ch_kraken2db
        )
        ch_kraken2_multiqc       = KRAKEN2_RUN.out.txt
        ch_kraken2_bracken       = KRAKEN2_RUN.out.txt
        ch_kraken2_krakenparse   = KRAKEN2_RUN.out.txt
        ch_software_versions     = ch_software_versions.mix(KRAKEN2_RUN.out.version.first().ifEmpty(null))

    /*
    * MODULE: Run bracken
    */

    BRACKEN (
            ch_kraken2_bracken,
            ch_brackendb
        )
        ch_bracken           = BRACKEN.out.brackenreport
        ch_software_versions = ch_software_versions.mix(BRACKEN.out.version.first().ifEmpty(null))

    /*
    * MODULE: Run krakenparse
    */

    KRAKENPARSE (
            ch_kraken2_krakenparse,
            ch_bracken
        )
        ch_software_versions = ch_software_versions.mix(KRAKENPARSE.out.version.first().ifEmpty(null))
    
    /*
     * MODULE: Pipeline reporting
     */
    
    GET_SOFTWARE_VERSIONS ( 
        ch_software_versions.map { it }.collect()
    ) 
    
    /*
    * MODULE: Run MultiQC
    */

    MULTIQC (
            ch_multiqc_config,
            ch_multiqc_custom_config.collect().ifEmpty([]),
            GET_SOFTWARE_VERSIONS.out.yaml.collect(),
            ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'),
            FASTQC_FASTP.out.fastqc_raw_zip.collect{it[1]}.ifEmpty([]),
            FASTQC_FASTP.out.trim_json.collect{it[1]}.ifEmpty([]),
            ch_kraken2_multiqc.collect{it[1]}.ifEmpty([]) 
        )
        multiqc_report = MULTIQC.out.report.toList()   
}

////////////////////////////////////////////////////
/* --              COMPLETION EMAIL            -- */
////////////////////////////////////////////////////

workflow.onComplete {
    Completion.email(workflow, params, summary_params, projectDir, log, multiqc_report)
    Completion.summary(workflow, params, log)
}

////////////////////////////////////////////////////
/* --                  THE END                 -- */
////////////////////////////////////////////////////
