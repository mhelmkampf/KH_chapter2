#!/usr/bin/env nextflow
// git 5.1
// open genotype data
Channel
	.fromFilePairs("../../1_genotyping/4_phased/phased_mac2.vcf.{gz,gz.tbi}")
	.into{ vcf_fasttree_whg; vcf_locations }

// git 5.2
// setting the sampling location
// (the script is set up to run on diffferent subsets of samples)
Channel
	.from( "all" ) //, "bel", "hon", "pan" )
	.set{ locations4_ch }

// git 5.3
// setting loci restrictions
// (keep vs remove outlier regions)
Channel
	.from( "whg" ) //, "no_musks" )
	.set{ whg_modes }

// git 5.4
// setting the sampling mode
// (the script is set up to run on diffferent subsets of samples)
Channel
	.from( "no_outgroups" ) //, "all" )
	.into{ sample_modes }

// git 5.5
// compile the config settings and add data file
locations4_ch
	.combine( vcf_fasttree_whg )
	.combine( whg_modes )
	.combine( sample_modes )
	.set{ vcf_fasttree_whg_location_combo }

// git 5.6
// apply sample filter, subset and convert genotypes
process subset_vcf_by_location_whg {
	label "L_28g5h_subset_vcf_whg"

	input:
	set val( loc ), vcfId, file( vcf ), val( mode ), val( sample_mode ) from vcf_fasttree_whg_location_combo

	output:
	set val( mode ), val( loc ), val( sample_mode ), file( "${loc}.${mode}.${sample_mode}.whg.geno.gz" ) into snp_geno_tree_whg

	script:
	"""
	DROP_CHRS=" "

	# check if samples need to be dropped based on location
	if [ "${loc}" == "all" ];then
		vcfsamplenames ${vcf[0]} > prep.pop
	else
		vcfsamplenames ${vcf[0]} | \
			grep ${loc}  > prep.pop
	fi

	# check if outgroups need to be dropped
	if [ "${sample_mode}" == "all" ];then
		mv prep.pop ${loc}.pop
	else
		cat prep.pop | \
			grep -v tor | \
			grep -v tab > ${loc}.pop
	fi

	# check if diverged LGs need to be dropped
	if [ "${mode}" == "no_musks" ];then
		DROP_CHRS="--not-chr LG04 --not-chr LG07 --not-chr LG08 --not-chr LG09 --not-chr LG12 --not-chr LG17 --not-chr LG23"
	fi

	vcftools --gzvcf ${vcf[0]} \
		--keep ${loc}.pop \
		\$DROP_CHRS \
		--mac 3 \
		--recode \
		--stdout | gzip > ${loc}.${mode}.${sample_mode}.vcf.gz

	python \$SFTWR/genomics_general/VCF_processing/parseVCF.py \
		-i  ${loc}.${mode}.${sample_mode}.vcf.gz | gzip > ${loc}.${mode}.${sample_mode}.whg.geno.gz
	"""
}

// git 5.7
// convert genotypes to fasta
process fasttree_whg_prep {
	label 'L_190g4h_fasttree_whg_prep'
	tag "${mode} - ${loc} - ${sample_mode}"

	input:
	set val( mode ), val( loc ), val( sample_mode ), file( geno ) from snp_geno_tree_whg

	output:
	set val( mode ), val( loc ), val( sample_mode ), file( "all_samples.${loc}.${mode}.${sample_mode}.whg.SNP.fa" ) into ( fasttree_whg_prep_ch )

	script:
	"""
	python \$SFTWR/genomics_general/genoToSeq.py -g ${geno} \
		-s  all_samples.${loc}.${mode}.${sample_mode}.whg.SNP.fa \
		-f fasta \
		--splitPhased
	"""
}

// git 5.8
// create phylogeny
process fasttree_whg_run {
	label 'L_300g30h_fasttree_run'
	tag "${mode} - ${loc} - ${sample_mode}"
	publishDir "../../2_analysis/fasttree/", mode: 'copy'

	input:
	set val( mode ), val( loc ), val( sample_mode ), file( fa ) from fasttree_whg_prep_ch

	output:
	file( "${sample_mode}.${loc}.${mode}.SNP.tree" ) into ( fasttree_whg_output )

	script:
	"""
	fasttree -nt ${fa} > ${sample_mode}.${loc}.${mode}.SNP.tree
	"""
}

// git 5.9
// initialize the locations for topology weighting
Channel
	.from( "bel", "hon" )
	.set{ locations_ch }

// git 5.10
locations_ch
	.combine( vcf_locations )
	.set{ vcf_location_combo }

// git 5.11
// initialize LGs
Channel
	.from( ('01'..'09') + ('10'..'19') + ('20'..'24') )
	.map{ "LG" + it }
	.set{ lg_twisst }

// git 5.12
// subset the genotypes by location
process subset_vcf_by_location {
	label "L_20g2h_subset_vcf"

	input:
	set val( loc ), vcfId, file( vcf ) from vcf_location_combo

	output:
	set val( loc ), file( "${loc}.vcf.gz" ), file( "${loc}.pop" ) into ( vcf_loc_twisst )

	script:
	"""
	vcfsamplenames ${vcf[0]} | \
		grep ${loc} | \
		grep -v tor | \
		grep -v tab > ${loc}.pop

	vcftools --gzvcf ${vcf[0]} \
		--keep ${loc}.pop \
		--mac 3 \
		--recode \
		--stdout | gzip > ${loc}.vcf.gz
	"""
}

// ---------------------------------------------------------------
// Unfortunately the twisst preparation did not work on the cluster
// ('in place'), so I had to setup the files locally and then plug
// them into this workflow.
// Below is the originally intended clean workflow (commented out),
// while the plugin version picks up at git 5.19.
// ---------------------------------------------------------------

/* MUTE:
// git 5.13
// add the lg channel to the genotype subset
vcf_loc_twisst
	.combine( lg_twisst )
	.set{ vcf_loc_lg_twisst }
*/

/* MUTE: python thread conflict - run locally and feed into ressources/plugin
// git 5.14
// subset genotypes by LG
process vcf2geno_loc {
	label 'L_20g15h_vcf2geno'

	input:
	set val( loc ), file( vcf ), file( pop ), val( lg ) from vcf_loc_lg_twisst

	output:
	set val( loc ), val( lg ), file( "${loc}.${lg}.geno.gz" ), file( pop ) into snp_geno_twisst

	script:
	"""
	vcftools \
		--gzvcf ${vcf} \
		--chr ${lg} \
		--recode \
		--stdout |
		gzip > intermediate.vcf.gz

	python \$SFTWR/genomics_general/VCF_processing/parseVCF.py \
	  -i intermediate.vcf.gz | gzip > ${loc}.${lg}.geno.gz
	"""
}
*/
/* MUTE: python thread conflict - run locally and feed into ressources/plugin
// git 5.15
// initialize SNP window size
Channel.from( 50, 200 ).set{ twisst_window_types }
*/
/* MUTE: python thread conflict - run locally and feed into ressources/plugin
// git 5.16
// add the SNP window size to the genotype subset
snp_geno_twisst.combine( twisst_window_types ).set{ twisst_input_ch }
*/
/* MUTE: python thread conflict - run locally and feed into ressources/plugin
// git 5.17
// create the phylogenies along the sliding window
process twisst_prep {
  label 'L_G120g40h_prep_twisst'
  	publishDir "../../2_analysis/twisst/positions/${loc}/", mode: 'copy'

  input:
  set val( loc ), val( lg ), file( geno ), file( pop ), val( twisst_w ) from twisst_input_ch.filter { it[0] != 'pan' }

	output:
	set val( loc ), val( lg ), file( geno ), file( pop ), val( twisst_w ), file( "*.trees.gz" ), file( "*.data.tsv" ) into twisst_prep_ch

  script:
   """
	module load intel17.0.4 intelmpi17.0.4

   mpirun \$NQSII_MPIOPTS -np 1 \
	python \$SFTWR/genomics_general/phylo/phyml_sliding_windows.py \
      -g ${geno} \
      --windType sites \
      -w ${twisst_w} \
      --prefix ${loc}.${lg}.w${twisst_w}.phyml_bionj \
      --model HKY85 \
      --optimise n \
		--threads 1
	 """
}
*/
/* MUTE: python thread conflict - run locally and feed into ressources/plugin
// git 5.18
// run the topology weighting on the  phylogenies
process twisst_run {
	label 'L_G120g40h_run_twisst'
	publishDir "../../2_analysis/twisst/weights/", mode: 'copy'

	input:
	set val( loc ), val( lg ), file( geno ), file( pop ), val( twisst_w ), file( tree ), file( data ) from twisst_prep_ch

	output:
	set val( loc ), val( lg ), val( twisst_w ), file( "*.weights.tsv.gz" ), file( "*.data.tsv" ) into ( twisst_output )

	script:
	"""
	module load intel17.0.4 intelmpi17.0.4

	awk '{print \$1"\\t"\$1}' ${pop} | \
	sed 's/\\(...\\)\\(...\\)\$/\\t\\1\\t\\2/g' | \
	cut -f 1,3 | \
	awk '{print \$1"_A\\t"\$2"\\n"\$1"_B\\t"\$2}' > ${loc}.${lg}.twisst_pop.txt

	TWISST_POPS=\$( cut -f 2 ${loc}.${lg}.twisst_pop.txt | sort | uniq | paste -s -d',' | sed 's/,/ -g /g; s/^/-g /' )

	mpirun \$NQSII_MPIOPTS -np 1 \
	python \$SFTWR/twisst/twisst.py \
	  --method complete \
	  -t ${tree} \
	  -T 1 \
	  \$TWISST_POPS \
	  --groupsFile ${loc}.${lg}.twisst_pop.txt | \
	  gzip > ${loc}.${lg}.w${twisst_w}.phyml_bionj.weights.tsv.gz
	"""
}
*/

// git 5.19
// emulate setting
Channel
	.from(50, 200)
	.combine( vcf_loc_twisst )
	.combine( lg_twisst )
	.set{ twisst_modes }

// git 5.20
// run the topology weighting on the  phylogenies
process twisst_plugin {
	label 'L_G120g40h_twisst_plugin'
	publishDir "../../2_analysis/twisst/weights/", mode: 'copy'
	tag "${loc}-${lg}-${mode}"

	input:
	set val( mode ), val( loc ), file( vcf ), file( pop ), val( lg ) from twisst_modes

	output:
	set val( loc ), val( lg ), file( "*.weights.tsv.gz" ) into ( twisst_output )

	script:
	"""
	module load intel17.0.4 intelmpi17.0.4

	awk '{print \$1"\\t"\$1}' ${pop} | \
	sed 's/\\(...\\)\\(...\\)\$/\\t\\1\\t\\2/g' | \
	cut -f 1,3 | \
	awk '{print \$1"_A\\t"\$2"\\n"\$1"_B\\t"\$2}' > ${loc}.${lg}.twisst_pop.txt

	TWISST_POPS=\$( cut -f 2 ${loc}.${lg}.twisst_pop.txt | sort | uniq | paste -s -d',' | sed 's/,/ -g /g; s/^/-g /' )

	mpirun \$NQSII_MPIOPTS -np 1 \
	python \$SFTWR/twisst/twisst.py \
	  --method complete \
	  -t \$BASE_DIR/ressources/plugin/trees/${loc}/${loc}.${lg}.w${mode}.phyml_bionj.trees.gz \
	  \$TWISST_POPS \
	  --groupsFile ${loc}.${lg}.twisst_pop.txt | \
	  gzip > ${loc}.${lg}.w${mode}.phyml_bionj.weights.tsv.gz
	"""
}
