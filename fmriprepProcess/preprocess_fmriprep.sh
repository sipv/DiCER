#!/bin/bash

# This file performs high pass filtering

func=$1
file_output=$2
folder_input=$3
mask_epi=$4

# ------------------------------ Temporal processing ------------------------------
# Now off to do the processing in time -- work on using AFNI's detrend and hpf
3dTproject -input $func -prefix $folder_input/prepro_func -passband 0.005 Inf -cenmode NTRP -mask $mask_epi
# file_name=${input_dbscan::-7}_detrended_hpf.nii.gz

# get qform code
codeVal=$(fslval $func qform_code)
if [ "$codeVal" -eq 1 ];then
   3dcopy $folder_input/prepro_func+orig $file_output
elif [ "$codeVal" -eq 2 ]
then
	3dcopy $folder_input/prepro_func+tlrc $file_output   
else
   echo "Unknown sform code, something has gone wrong, check your nifti"
fi


# Turn nans to zero (need to check this again later..)
fslmaths $file_output -nan $file_output
# ------------------------------ Temporal processing ------------------------------

# Remove the AFNI stuff
rm -rf $folder_input/prepro_func*