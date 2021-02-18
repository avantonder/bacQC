# bacQC

**Pipeline for trimming and running QC on bacterial short-read sequence data**.

[![Nextflow](https://img.shields.io/badge/nextflow-%E2%89%A520.04.0-brightgreen.svg)](https://www.nextflow.io/)

## Introduction

<!-- TODO nf-core: Write a 1-2 sentence summary of what data the pipeline is for and what it does -->
**bacQC** is a bioinformatics analysis pipeline for trimming Illumina reads with fastp, assessing read quality with fastQC
and species composition with Kraken2 and Bracken.

The pipeline is built using [Nextflow](https://www.nextflow.io), a workflow tool to run tasks across multiple compute infrastructures in a very portable manner. It comes with docker containers making installation trivial and results highly reproducible.

## Quick Start

1. Install [`nextflow`](https://nf-co.re/usage/installation)

2. Install any of [`Docker`](https://docs.docker.com/engine/installation/), [`Singularity`](https://www.sylabs.io/guides/3.0/user-guide/) or [`Podman`](https://podman.io/) for full pipeline reproducibility _(please only use [`Conda`](https://conda.io/miniconda.html) as a last resort; see [docs](https://nf-co.re/usage/configuration#basic-configuration-profiles))_

3. Download the pipeline and test it on a minimal dataset with a single command:

    ```bash
    nextflow run avantonder/bacQC -profile test,<docker/singularity/podman/conda/institute>
    ```

4. Start running your own analysis!

    <!-- TODO nf-core: Update the example "typical command" below used to run the pipeline -->

    ```bash
    nextflow run avantonder/bacQC -profile <docker/singularity/podman/conda/institute> --input '*_R{1,2}.fastq.gz' --kraken2db <path to kraken2 db> ----brackendb <path to bracken db>
    ```

## Pipeline Summary

By default, the pipeline currently performs the following:

<!-- TODO nf-core: Fill in short bullet-pointed list of default steps of pipeline -->

* Read and adapter trimming (`fastp`)
* Sequencing quality control (`FastQC`)
* Overall pipeline run summaries (`MultiQC`)
* Read assignment (`Kraken 2`)
* Bayesian classification of read assignments (`Bracken`)

## Credits

bacQC was originally written by Andries van Tonder.
