// Import generic module functions
include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
options        = initOptions(params.options)

process KRAKENPARSE {
    label 'process_low'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), publish_id:'') }
    
    conda (params.enable_conda ? 'conda-forge::numpy=1.17 conda-forge::pandas=0.25' : null)
    if (workflow.containerEngine == 'singularity' && !params.singularity_pull_docker_container) {
        container "https://depot.galaxyproject.org/singularity/mulled-v2-344874846f44224e5f0b7b741eacdddffe895d1e:1c62d2bdb53ec7327655a589a6fe7792a36e3ac6-0"
    } else {
        container "quay.io/biocontainers/mulled-v2-344874846f44224e5f0b7b741eacdddffe895d1e:1c62d2bdb53ec7327655a589a6fe7792a36e3ac6-0"
    }
    
    input:
    tuple val(meta), path(txt)
    tuple val(meta), path(brackenreport)

    output:
    path "Bracken_species_composition.tsv", emit: composition
    path "*.version.txt",                   emit: version
    
    script: // This script is bundled with the pipeline in avantonder/bacQC/bin/
    def software = getSoftwareName(task.process)
    """
    kraken_parser.py

    echo '1.0' > ${software}.version.txt 
    """
}