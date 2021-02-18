#!/usr/bin/env python

import os, argparse, sys, subprocess, glob
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

def parse_args(args):

	global _parser

	_parser = argparse.ArgumentParser(description = 'kraken_parser.py: a tool for parsing bracken outputs')
	_parser.add_argument('--threshold', '-c', help='Minimum percentage of reads assigned to a species to be reported (default = 5) [OPTIONAL]')
	_parser.add_argument('--output_prefix', '-o', help='Prefix to append to output files (default = Bracken) [OPTIONAL]')

	opts = _parser.parse_args(args)

	return opts

def main(opts):

	if not opts.output_prefix:
		out_name = 'Bracken'
	else:
		out_name = str(opts.output_prefix)

	if not opts.threshold:
		min_threshold = 5
	else:
		min_threshold = int(opts.threshold)

	kraken_report_files = sorted(glob.glob('kraken_results/*_kraken.report'))
	species_abundance_files = sorted(glob.glob('kraken_results/*_output_species_abundance.txt'))

	for i in kraken_report_files:
		subprocess.call('awk ' + "'{print FILENAME, $6, $2}' " + i + " | head -n1 | sed 's/.kraken.report//g' | sed 's@kraken_results/@@g' >> kraken_unclassified.txt", shell = True)

	unclassified = pd.read_csv('kraken_unclassified.txt', header=None, delim_whitespace=True)

	unclassified = unclassified[[0,2]]

	unclassified = unclassified.set_index([0]).T

	unclassified.insert(loc = 0, column = 'name', value = 'unclassified')

	unclassified.columns = unclassified.columns.map(str)

	species_abundance_df = [pd.read_csv(f, sep='\t') for f in species_abundance_files]

	species_abundance_names = [i.split('/')[1].replace('_output_species_abundance.txt', '') for i in species_abundance_files]

	for a,b in zip(species_abundance_df, species_abundance_names):
		a.rename(columns = {'new_est_reads': b, 'fraction_total_reads': b + '_frac'}, inplace=True)

	#species_abundance_df_filtered = [i[[0,5]] for i in species_abundance_df]

	species_abundance_df_filtered = [i.iloc[:,[0,5]] for i in species_abundance_df]

	species_abundance_joined = pd.concat([i.set_index('name') for i in species_abundance_df_filtered], axis=1).reset_index()

	species_abundance_joined.fillna(0, inplace=True)

	species_abundance_joined.rename(columns = {'index':'name'}, inplace=True)

	species_abundance_unclassified = species_abundance_joined.append(unclassified, ignore_index=True)

	for column in species_abundance_unclassified.columns[1:]:
		species_abundance_unclassified[column + '_freq'] = species_abundance_unclassified[column] / species_abundance_unclassified[column].sum() * 100

	species_abundance_unclassified_filtered = pd.concat([species_abundance_unclassified['name'], species_abundance_unclassified.filter(like='_freq')], axis=1)

	species_abundance_unclassified_filtered['Max_value'] = species_abundance_unclassified_filtered.filter(like='_freq').max(axis=1)

	species_abundance_unclassified_filtered = species_abundance_unclassified_filtered[(species_abundance_unclassified_filtered['Max_value'] >= min_threshold)]

	total = 100 - species_abundance_unclassified_filtered.filter(like='_freq').apply(np.sum)

	total['name'] = 'other'

	final_abundance = species_abundance_unclassified_filtered.append(pd.DataFrame(total.values, index=total.keys()).T, ignore_index=True)

	final_abundance_sorted = pd.concat([final_abundance['name'], final_abundance.filter(like = '_freq')], axis = 1)

	final_abundance_sorted.columns = final_abundance_sorted.columns.str.replace('_freq', '')

	final_abundance_tsv_name = out_name + '_species_composition.tsv'

	final_abundance_sorted.T.to_csv(final_abundance_tsv_name, sep = '\t', header = False)

	as_list = final_abundance_sorted.index.tolist()

	name_list = final_abundance_sorted['name'].tolist()

	final_abundance_plot_df = final_abundance_sorted.iloc[:,1:].rename(index=dict(zip(as_list,name_list)))

	bracken_plot = final_abundance_plot_df.T.plot(kind='bar', stacked=True, figsize=(18.5, 10.5))

	bracken_plot.set_ylabel('Assigned reads (%)')

	bracken_plot.set_xlabel('Sample')

	box = bracken_plot.get_position()

	bracken_plot.set_position([box.x0, box.y0, box.width * 0.8, box.height])

	bracken_plot.legend(loc='center left', bbox_to_anchor=(1, 0.5))

	bracken_plot_name = out_name + '_species_composition.png'

	plt.savefig(bracken_plot_name)

if __name__ == "__main__":
  opts= parse_args(sys.argv[1:])
  main(opts)