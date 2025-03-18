# bacQC

# ![avantonder/bacQC](assets/bacQC_metromap.png)

[![Cite with Zenodo](https://zenodo.org/badge/681230079.svg)](https://doi.org/10.5281/zenodo.15040673)

[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A524.04.2-23aa62.svg)](https://www.nextflow.io/)
[![run with conda](http://img.shields.io/badge/run%20with-conda-3EB049?labelColor=000000&logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)
[![Launch on Seqera Platform](https://img.shields.io/badge/Launch%20%F0%9F%9A%80-Seqera%20Platform-%234256e7)](https://cloud.seqera.io/launch?pipeline=https://github.com/nf-core/taxprofiler)

## Introduction

**bacQC** is a bioinformatics analysis pipeline for trimming Illumina reads with `fastp`, assessing read quality with `fastQC` and species composition with `Kraken2` and `Bracken`.  It also allows reads to be extracted using a Taxon id (optional).

1. Read QC ([`FastQC`](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/))
2. Calculate fastq summary statistics ([`fastq-scan`](https://github.com/rpetit3/fastq-scan))
3. Trim reads for quality and adapter sequence ([`fastp`](https://github.com/OpenGene/fastp))
4. Assign taxonomic labels to sequence reads ([`Kraken 2`](https://ccb.jhu.edu/software/kraken2/))
5. Re-estimate taxonomic abundance of samples analyzed by kraken 2([`Bracken`](https://ccb.jhu.edu/software/bracken/))
6. Visualize Bracken reports with ([`Krona`](https://github.com/marbl/Krona))
7. Extract reads using Taxon ID ([`KrakenTools`](https://github.com/jenniferlu717/KrakenTools))) (OPTIONAL)
8. Present QC and visualisation for raw read, trimmed read and kraken2/Bracken results ([`MultiQC`](http://multiqc.info/))

## Usage

> [!NOTE]
> If you are new to Nextflow and nf-core, please refer to [this page](https://nf-co.re/docs/usage/installation) on how to set-up Nextflow. Make sure to [test your setup](https://nf-co.re/docs/usage/introduction#how-to-run-a-pipeline) with `-profile test` before running the workflow on actual data.

You will need to download a taxonomic database for Kraken 2 and Bracken (this is a large file and may take a while):

```bash
wget ftp://ftp.ccb.jhu.edu/pub/data/kraken2_dbs/old/minikraken2_v1_8GB_201904.tgz

tar xvfz minikraken2_v1_8GB_201904.tgz
```
You will also need to download the taxonomy file for Krona (this requires Krona to be installed e.g. with Conda):

```bash
ktUpdateTaxonomy.sh .
```

Download the pipeline and test it on a minimal dataset with a single command:

```bash
nextflow run avantonder/bacQC -profile test,YOURPROFILE --outdir <OUTDIR>
```

Note that some form of configuration will be needed so that Nextflow knows how to fetch the required software. This is usually done in the form of a config profile (`YOURPROFILE` in the example command above). You can chain multiple config profiles in a comma-separated string.

> - The pipeline comes with config profiles called `docker`, `singularity`, `podman`, `shifter`, `charliecloud` and `conda` which instruct the pipeline to use the named tool for software management. For example, `-profile test,docker`.
> - Please check [nf-core/configs](https://github.com/nf-core/configs#documentation) to see if a custom config file to run nf-core pipelines already exists for your Institute. If so, you can simply use `-profile <institute>` in your command. This will enable either `docker` or `singularity` and set the appropriate execution settings for your local compute environment.
> - If you are using `singularity`, please use the [`nf-core download`](https://nf-co.re/tools/#downloading-pipelines-for-offline-use) command to download images first, before running the pipeline. Setting the [`NXF_SINGULARITY_CACHEDIR` or `singularity.cacheDir`](https://www.nextflow.io/docs/latest/singularity.html?#singularity-docker-hub) Nextflow options enables you to store and re-use the images from a central location for future pipeline runs.
> - If you are using `conda`, it is highly recommended to use the [`NXF_CONDA_CACHEDIR` or `conda.cacheDir`](https://www.nextflow.io/docs/latest/conda.html) settings to store the environments in a central location for future pipeline runs.

An executable Python script called [`fastq_dir_to_samplesheet.py`](https://github.com/avantonder/bacQC/blob/main/bin/fastq_dir_to_samplesheet.py) has been provided  to auto-create an input samplesheet based on a directory containing FastQ files **before** you run the pipeline (requires Python 3 installed locally) e.g.

```bash
wget -L https://raw.githubusercontent.com/avantonder/bacQC/main/bin/fastq_dir_to_samplesheet.py

./fastq_dir_to_samplesheet.py <FASTQ_DIR> samplesheet.csv -r1 <FWD_FASTQ_SUFFIX> -r2 <REV_FASTQ_SUFFIX> 
```

```csv title="samplesheet.csv"
sample,fastq_1,fastq_2
SAMPLE_PAIRED_END,/path/to/fastq/files/sample1_1.fastq.gz,/path/to/fastq/files/sample1_2.fastq.gz
SAMPLE_SINGLE_END,/path/to/fastq/files/sample2.fastq.gz, 
```

Alternatively the samplesheet.csv file created by [`nf-core/fetchngs`](https://nf-co.re/fetchngs) can also be used.

Now you can run the pipeline using: 

```bash
nextflow run avantonder/bacQC \
    -profile <docker/singularity/podman/conda/institute> \
    --input samplesheet.csv \
    --kraken2db path/to/minikraken2_v1_8GB \
    --kronadb path/to/taxonomy.tab \
    --genome_size 4300000 \
    --outdir <OUTDIR>
```

The typical command for QC, species composition **and** read extraction using a taxon ID:

```bash
nextflow run avantonder/bacQC \
    -profile <docker/singularity/podman/conda/institute> \
    --input samplesheet.csv \
    --kraken2db path/to/minikraken2_v1_8GB \
    --kronadb path/to/taxonomy.tab \
    --genome_size 4300000 \
    --kraken_extract \
    --tax_id <TAXON_ID> \
    --outdir <OUTDIR>
```

See [usage docs](docs/usage.md) for all of the available options when running the pipeline.

Note that some form of configuration will be needed so that Nextflow knows how to fetch the required software. This is usually done in the form of a config profile (`<INSTITUTION>.config` in the example command above). You can chain multiple config profiles in a comma-separated string.

> - The pipeline comes with config profiles called `docker`, `singularity`, `podman`, `shifter`, `charliecloud` and `conda` which instruct the pipeline to use the named tool for software management. For example, `-profile test,docker`.
> - Please check [nf-core/configs](https://github.com/nf-core/configs#documentation) to see if a custom config file to run nf-core pipelines already exists for your Institute. If so, you can simply use `-profile <institute>` in your command. This will enable either `docker` or `singularity` and set the appropriate execution settings for your local compute environment.
> - If you are using `singularity`, please use the [`nf-core download`](https://nf-co.re/tools/#downloading-pipelines-for-offline-use) command to download images first, before running the pipeline. Setting the [`NXF_SINGULARITY_CACHEDIR` or `singularity.cacheDir`](https://www.nextflow.io/docs/latest/singularity.html?#singularity-docker-hub) Nextflow options enables you to store and re-use the images from a central location for future pipeline runs.
> - If you are using `conda`, it is highly recommended to use the [`NXF_CONDA_CACHEDIR` or `conda.cacheDir`](https://www.nextflow.io/docs/latest/conda.html) settings to store the environments in a central location for future pipeline runs.

## Documentation

The avantonder/bacQC pipeline comes with documentation about the pipeline [usage](https://github.com/avantonder/bacQC/blob/main/docs/usage.md), [parameters](https://github.com/avantonder/bacQC/blob/main/docs/parameters.md) and [output](https://github.com/avantonder/bacQC/blob/main/docs/output.md).

## Acknowledgements

bacQC was originally written by Andries van Tonder. I wouldn't have been able to write this pipeline with out the tools, documentation, pipelines and modules made available by the fantastic [nf-core community](https://nf-co.re/).

## Feedback

If you have any issues, questions or suggestions for improving bovisanalyzer, please submit them to the [Issue Tracker](https://github.com/avantonder/bacQC/issues).

## Citations

If you use the avantonder/bacQC pipeline, please cite it using the following doi: [10.5281/zenodo.15040673](https://doi.org/10.5281/zenodo.15040673)

An extensive list of references for the tools used by the pipeline can be found in the [`CITATIONS.md`](CITATIONS.md) file.
