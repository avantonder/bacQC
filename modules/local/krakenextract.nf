def VERSION = '1.2' // Version information not provided by tool on CLI

process KRAKENTOOLS_EXTRACT {
    tag "$meta.id"
    label 'process_low'

    conda (params.enable_conda ? "bioconda::krakentools=1.2" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/krakentools:1.2--pyh5e36f6f_0':
        'quay.io/biocontainers/krakentools:1.2--pyh5e36f6f_0' }"

    input:
    tuple val(meta), path(reads) 
    tuple val(meta), path(kraken_out)
    tuple val(meta), path(kraken_report)
    val tax_id

    output:
    tuple val(meta), path('*.extracted.fastq.gz') , emit: reads
    path "versions.yml"                           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    if (meta.single_end) {
        """
        extract_kraken_reads.py \\
            -k ${kraken_out} \\
            -r ${kraken_report} \\
            -s ${prefix}.trim.fastq.gz \\
            -o ${prefix}.extracted.fastq \\
            -t ${tax_id} \\
            ${args}

        gzip *.fastq

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            extract_kraken_reads.py: ${VERSION}
        END_VERSIONS
        """
    } else {
        """
        extract_kraken_reads.py \\
        -k ${kraken_out} \\
        -r ${kraken_report} \\
        -s1 ${prefix}_1.trim.fastq.gz \\
        -s2 ${prefix}_2.trim.fastq.gz \\
        -o ${prefix}_1.extracted.fastq \\
        -o2 ${prefix}_2.extracted.fastq \\
        -t ${tax_id} \\
        ${args}

        gzip *.fastq

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            extract_kraken_reads.py: ${VERSION}
        END_VERSIONS
        """
    }
}