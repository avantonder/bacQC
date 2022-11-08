#!/usr/bin/env python

import pandas as pd
import numpy as np
import glob
import json

# Parse raw fastq-scan results

# Read in fastqscan json files

raw_json_file = sorted(glob.glob('*.raw.json'))

raw_json_names = [i.replace('.raw.json', '') for i in raw_json_file]

raw_json_names_df = pd.DataFrame(raw_json_names)

raw_json_names_df.columns = ['Sample']

raw_jsons_data = {}

for index, file in enumerate(raw_json_file):
    with open(file, 'r') as f:
        raw_json_text = json.loads(f.read())
        qc = raw_json_text['qc_stats']
        raw_jsons_data[index] = qc

raw_jsons_data_df = pd.DataFrame.from_dict(raw_jsons_data, orient = 'index')

raw_json_merged_df = raw_json_names_df.join(raw_jsons_data_df)

fastqscan_raw_df = raw_json_merged_df.iloc[:, 0:4]

fastqscan_raw_df = fastqscan_raw_df.rename(columns = {'total_bp' : 'raw_total_bp', 'read_total' : 'num_raw_reads', 'coverage' : 'raw_coverage'})

# Parse trimmed fastq-scan results

trim_json_file = sorted(glob.glob('*.trim.json'))

trim_json_names = [i.replace('.trim.json', '') for i in trim_json_file]

trim_json_names_df = pd.DataFrame(trim_json_names)

trim_json_names_df.columns = ['Sample']

trim_jsons_data = {}

for index, file in enumerate(trim_json_file):
    with open(file, 'r') as f:
        trim_json_text = json.loads(f.read())
        qc = trim_json_text['qc_stats']
        trim_jsons_data[index] = qc

trim_jsons_data_df = pd.DataFrame.from_dict(trim_jsons_data, orient = 'index')

trim_json_merged_df = trim_json_names_df.join(trim_jsons_data_df)

fastqscan_trim_df = trim_json_merged_df.iloc[:, 0:4]

fastqscan_trim_df = fastqscan_trim_df.rename(columns = {'total_bp' : 'trim_total_bp', 'read_total' : 'num_trim_reads', 'coverage' : 'trim_coverage'})

# Merge fastq-scan dataframes

fastqscan_merged = pd.merge(fastqscan_raw_df, fastqscan_trim_df, on = ['Sample'])

fastqscan_merged['%reads_after_trimmed'] = fastqscan_merged['num_trim_reads'] / fastqscan_merged['num_raw_reads'] * 100

# Write merged dataframe to csv file

summary_file_name = 'read_stats.csv'

fastqscan_merged.to_csv(summary_file_name, sep = ',', header = True, index = False)