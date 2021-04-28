// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
options        = initOptions(params.options)

process BRACKEN {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        aveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), meta:meta, publish_by_meta:['id']) }

    conda     (params.enable_conda ? "conda-forge::python=3.8.3" : null)
    container "quay.io/biocontainers/python:3.8.3"
    
    input:
    tuple val(meta), path(txt)
    path brackendb

    output:
    tuple val(meta), path('*_output_species_abundance.txt'), emit: brackenreport
    path "*.version.txt",                                    emit: version
    
    script: // This script is bundled with the pipeline in avantonder/bacQC/bin/
    def software = getSoftwareName(task.process)
    def prefix   = options.suffix ? "${meta.id}${options.suffix}" : "${meta.id}"
    """
    est_abundance.py \\
        -i ${prefix}.kraken2.report.txt \\
        -k ${brackendb} \\
        -l S \\
        -t 10 \\
        -o ${prefix}_output_species_abundance.txt
  
    echo '1.0' > ${software}.version.txt 
    """
}