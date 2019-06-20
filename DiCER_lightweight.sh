#!/bin/bash

# This here is a lightweight version of DiCER, this does not assume you have run fmriprep, it just takes your own preprocessing, 
# and then applies DiCER to the result.

# This does require some inputs though:
# These inputs are needed all to make the report and to perform DiCER


print_usage() {
  printf "DiCER_lightweight\n
This tool performs (Di)ffuse (C)luster (E)stimation and (R)egression on data without fmriprep preprocessing. Here, we take fmri data that has NOT been detrended or demeaned (important!) and either a tissue tissue classification which is a file that has the same dimensions as the functional image with the following labels: 1=CSF,2=GM,3=WM,4=Restricted GM this restricted GM just takes the GM mask and takes the top 70 percent of signals (i.e. top 70 relative to the mean) to estimate noisy signals.\n
Usage with tissue map: DiCER_lightweights.sh -i input_nifti -t tissue_file -w output_folder -s subjectID -c confounds.tsv\n\n
Usage without tissue map: DiCER_lightweights.sh -i input_nifti -a T1w -w output_folder -s subjectID -c confounds.tsv\n\n
Optional (and recommonded) flag is -d, this detrends and high-pass filters the data. This allows better estimation of regressors, and is a very light cleaning of your data.\n
Kevin Aquino. 2019, email: kevin.aquino@monash.edu\n\n\nDiCER website: https://github.com/BMHLab/DiCER \n\n"

}

tissue=""
detrend="false"
makeTissueMap="false"
use_confounds="false"

# Everything will be in g-zipped niftis
FSLOUTPUTTYPE=NIFTI_GZ

# Have to make options if you need to generate a tissue file do so i.e. only if you specifiy the tissue file
while getopts 'i:t:a:w:s:c:dh' flag; do
  case "${flag}" in
    i)  input_file="${OPTARG}" ;;  
    t)  tissue="${OPTARG}" ;;  
	a)  anatomical="${OPTARG}" 
		makeTissueMap="true";;  
    w) 	output_folder="${OPTARG}" ;;    
	s)  subject="${OPTARG}" ;;  
	c) 	confounds="${OPTARG}" 
		use_confounds="true";;  
	d) 	detrend="true" ;;  
	h) print_usage 
		exit 1;;
    *) print_usage
       exit 1 ;;
  esac
done

# Make a temporary folder if it doesnt exist for all the segmentation and errata outputs
if [ ! -d "$output_folder/tmp_dir/" ]; then
          mkdir -p $output_folder/tmp_dir/
fi



# Setting up extra variables once you have everything!
folder=$output_folder #this is the working directory.
input=$output_folder$input_file
tissue_mask=$output_folder$tissue
confounds=$output_folder$confounds



# Make the tissue map if you have specificed the tissue map!
# 
# TISSUE SEGMENTATION!
# 
if $makeTissueMap;then
	echo "\n\nPeforming FAST tissue segmentation with anatomical image $anatomical\n"
	# Perform FAST segmentation:
	fast -o $output_folder"/tmp_dir/"$subject $output_folder"/"$anatomical

	# Get the segmentation file:
	segmentation_file=$output_folder"/tmp_dir/"$subject"_seg"

	# Now apply the flirt command to get the segmentation into the func space:
	seg_temp=$output_folder"/tmp_dir/"$subject"_seg_temp"
	flirt -in $segmentation_file -ref $input -out $seg_temp -applyxfm -interp nearestneighbour -usesqform

	# Now using the standard convention in FAST we generate the tissue types
	# GM - be a little more conservative above what FAST gives out in its hard segmentation:
	flirt -in $output_folder"/tmp_dir/"$subject"_pve_1.nii.gz" -out $output_folder"/tmp_dir/"$subject"_ds_gm.nii.gz" -ref $input -applyxfm -usesqform
	gm_mask_tmp=$output_folder"/tmp_dir/"$subject"_gm_mask"
	fslmaths $output_folder"/tmp_dir/"$subject"_ds_gm.nii.gz" -thr 0.5 -bin $gm_mask_tmp	
	# Use the probability mask and threshold that one
	# fslmaths $seg_temp -thr 2 -uthr 2 -bin $gm_mask_tmp

	# Generate masks for GM to make it more restrictive:
	mean_ts=$output_folder"/tmp_dir/"$subject"_mean_ts"
	fslmaths $input -Tmean $mean_ts
	# Taking the mean ts image, and just focusing in on grey matter
	fslmaths $mean_ts -mul $gm_mask_tmp $mean_ts

	# Now find the min/max
	read min max <<< $(fslstats $mean_ts -r)

	# Normalize the image and threshold the map to make a mask of epi of the top 60% of image intensity
	gm_mask_restrictive=$output_folder"/tmp_dir/"$subject"_mask_restrictive"
	fslmaths $mean_ts -div $max -thr 0.3 -bin $gm_mask_restrictive
	fslmaths $gm_mask_restrictive -mul $gm_mask_tmp -mul 2 $gm_mask_restrictive

	# Now we have everything to work with and combine it all together now
	tissue_mask=$output_folder$subject"_dtissue_func.nii.gz"
	fslmaths $seg_temp -add $gm_mask_restrictive $tissue_mask

	echo "\n\nSaved tissue mask in functional space and saved as: $tissue_mask\n"	
fi

#  Detrending and high-pass filtering data::
if $detrend;then
	echo "\n\Detrending and high-pass filtering $input..\n\n\n"		
	base_input=`basename $input .nii.gz`
	output_detrended=$output_folder$base_input"_detrended_hpf.nii.gz"
	# Find a mask epi
	mask_epi=$output_folder"/tmp_dir/"$subject"_mask_epi.nii.gz"
	fslmaths $tissue_mask -bin $mask_epi
	sh fmriprepProcess/preprocess_fmriprep.sh $input $output_detrended $output_folder $mask_epi
	# Now change all the inputs to work on the deterended versions	
	input=$output_detrended	
fi


echo "\n\nPerfoming DiCER..\n\n\n"	


python carpetCleaning/clusterCorrect.py $tissue_mask '.' $input $folder $subject

# Regress out all the regressors
regressor_dbscan=$subject"_dbscan_liberal_regressors.csv"


base_dicer_o=`basename $input .nii.gz`
dicer_output=$output_folder$base_dicer_o"_dbscan.nii.gz"

echo "\n\nRegressing $input with DiCER signals and clean output is at $dicer_output \n\n\n"	
python carpetCleaning/vacuum_dbscan.py -f $input_file -db $regressor_dbscan -s $subject -d $folder

# Next stage: do the reporting, all done through "tapestry"


export MPLBACKEND="agg"

# Do the cluster re-ordering:
echo "\n\nPeforming Cluster re-ordering of $input \n\n\n"	
python fmriprepProcess/clusterReorder.py $tissue_mask '.' $input $folder $subject
cluster_tissue_ordering=$output_folder$base_dicer_o"_clusterorder.nii.gz"

# Run the automated report:
echo "\n\nRunning the carpet reports! This is to visualize the data in a way to evaluate the corrections \n\n\n"	


# Here is a way to use confounds in the report, if they are not called then they will NOT appear in the automated report
if $use_confounds;then
	python carpetReport/tapestry.py -f $input","$dicer_output -fl "INPUT,DICER"  -o $cluster_tissue_ordering -l "CLUST" -s $subject -d $output_folder -ts $tissue_mask -reg $output_folder$regressor_dbscan -cf $confounds
else
	python carpetReport/tapestry.py -f $input","$dicer_output -fl "INPUT,DICER"  -o $cluster_tissue_ordering -l "CLUST" -s $subject -d $output_folder -ts $tissue_mask
fi
