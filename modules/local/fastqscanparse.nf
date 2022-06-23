process FASTQSCANPARSE {
    label 'process_low'
    publishDir "${params.outdir}",
        mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), publish_id:'') }
    
    conda (params.enable_conda ? 'conda-forge::numpy=1.15.2 conda-forge::pandas=0.23.4 conda-forge::scipy=1.2.1' : null)
    if (workflow.containerEngine == 'singularity' && !params.singularity_pull_docker_container) {
        container "https://depot.galaxyproject.org/singularity/mulled-v2-9adca5a7d3b24119897cfc20386da6c7fa47bdab:77c1885b47edc369aceb4cccf161a549bdac3d4b-0"
    } else {
        container "quay.io/biocontainers/mulled-v2-9adca5a7d3b24119897cfc20386da6c7fa47bdab:77c1885b47edc369aceb4cccf161a549bdac3d4b-0"
    }
    
    input:
    path json

    output:
    path "fastq-scan_summary.tsv", emit: tsv
    path  "versions.yml"         , emit: versions
    
    script: // This script is bundled with the pipeline in avantonder/bovisanalyzer/bin/
    def parser_version = '1.0'
    """
    fastqscan_parser.py
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastqscan_parser.py: ${parser_version}
    END_VERSIONS 
    """
}