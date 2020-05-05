#!/bin/bash

# patch leuko in the T1 image with mean wm value
# example patch_T1.sh T1_raw_patched_nocoreg.mif

set -e
set -u


display_usage() {
   echo "This script runs the mrtrix pipeline for 12 directions DWI "
   echo " use patch_T1.sh input, output, nthreads "
   }
   if [ $# -lt 1 ] || [ $# -gt 3 ]; 
	then echo $#set
       display_usage
	   exit 1
   fi
input=$1
patched_T1=$2
# To comply with resources requested on cluster, must specify that no multi-threading is used
THREADS=0
if [ $# -eq 3 ];
 then
   THREADS=$3
fi



[ ! -f aparc+aseg.nii.gz ] && mrconvert -nthreads $THREADS aparc+aseg.mgz aparc+aseg.nii.gz

# create leuko patch mask  
parc_seg=aparc+aseg.mgz
mrcalc -nthreads $THREADS $parc_seg 77 -eq $parc_seg 78 -eq -add $parc_seg 79 -eq -add leuko_patch_nocoreg.mif -force

# create wm mask
#aparc_wm.sh aparc+aseg.mgz wm_mask.mif
mrcalc -nthreads $THREADS $parc_seg 2 -eq $parc_seg 41 -eq -add wm_mask.mif -force

# create masked wm image
mrcalc  -nthreads $THREADS $input wm_mask.mif -multiply wm_seg_T1_unb.nii.gz -force

# find mean of white matter
wm_mean=$(fslstats wm_seg_T1_unb.nii.gz -M)

leuko_threshold=$(mrcalc -nthreads $THREADS 1.1  $wm_mean -multi)

# extend leuko patch by including low singal intensity area in wm ( lower than mean value)
mrconvert wm_seg_T1_unb.nii.gz wm_seg_T1_unb.mif -force
mrcalc -nthreads $THREADS wm_seg_T1_unb.mif 0 -eq 100000 -multi wm_seg_T1_unb.mif -add $leuko_threshold -lt leuko_patch_nocoreg.mif -add whole_leuko.mif -force -datatype uint16

maskfilter -nthreads $THREADS whole_leuko.mif erode - | maskfilter -nthreads $THREADS - dilate whole_leuko_clean.mif -force

# patched lauko in the white matter with wm_mean
mrconvert -nthreads $THREADS $input T1_raw_sz1_unb.mif -force
mrcalc -nthreads $THREADS whole_leuko_clean.mif $wm_mean -multi - | mrcalc -nthreads $THREADS - T1_raw_sz1_unb.mif -max $patched_T1 -datatype uint16 -force
rm -f wm_mask.mif leuko_patch_nocoreg.mif whole_leuko_clean.mif wm_seg_T1_unb.mif
