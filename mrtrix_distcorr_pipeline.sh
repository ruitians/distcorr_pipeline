#!/bin/bash
# the script to run mrtrix commands for 12 direction DTI with distortion correction,
# Ray Song
# Jan, 2020

# example ./mrtrixdistcorr_pipeline.sh ProjDir MRN ExamDate TimePoint LE (0 or 1) THREADS

set -e
set -u

# copy hcpmmp1.mgz file from cortical_thickness/MRN folder (recon-all was performed in the folder for total 16)

display_usage() {
   echo "This script runs the mrtrix pipeline for DTI connectome with distortion through registration"
   echo " use mrtrix_distcorr_pipeline.sh ProjDir MRN TimePoint LE (0 or 1) THREADS "
   }

if [ $# -ne 5 ] 
then
   echo $#set
   display_usage$#
   exit 1
fi

ProjDir=$1	# project name, for path
MRN=$2		# medical number, for path
TP=$3		# time point, for path
LE=$4		# Leuko patching (1) or not (0)
THREADS=$5	# Specify threads number that match bsub
TI=900
TE=150

# Define Environment Variables for appropriate execution
export ANTSPATH=/opt/ants/bin
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$THREADS

echo " I'm processing $MRN-$TP "
echo "Using $THREADS Cores"

# change to your own folder
myDir=/wer/$ProjDir/mrtrix_test/$MRN-$TP/DWI/

scrtDir=~/Repositories/mrtrix/github

cd $myDir

echo "		#1. cancatenate all b-images"
dwi=dwi_raw.mif
if [ ! -f $dwi ]; then
	mrcat -nthreads $THREADS  *DT*/ $dwi -axis 3
	mrinfo $dwi -export_grad_mrtrix grad.txt -export_pe_table pe.txt  -force
fi

# remove DTI dicom folders
#rm -f -r *DT* 


echo "		#2.  denoising"
dwi_den=dwi_den.mif
if  [ ! -f  $dwi_den ]; then
    dwidenoise -nthreads $THREADS $dwi $dwi_den -noise noise.mif
fi


echo "		#3 remove ring artifact"
dwi_den_unr=dwi_den_unr.mif
if [ ! -f $dwi_den_unr ]; then
    mrdegibbs -nthreads $THREADS $dwi_den $dwi_den_unr -axes 0,1
fi


echo "		#4 Eddy current correction "
dwi_den_unr_preproc=dwi_den_unr_preproc.mif
if [ ! -f $dwi_den_unr_preproc ]; then
	dwipreproc_new -nthreads $THREADS $dwi_den_unr $dwi_den_unr_preproc -rpe_header -eddy_options " --slm=linear --data_is_shelled " 
fi


echo "		#5 extract b0 images and take mean"
mean_b0_preproc=mean_b0_preprocessed.nii.gz
if [ ! -f $mean_b0_preproc ]; then
	dwiextract -nthreads $THREADS $dwi_den_unr_preproc - -bzero | mrmath -nthreads $THREADS - mean $mean_b0_preproc -axis 3 -force
fi


echo "		#6 mask estimation (remember to check the mask after this)"
mean_b0_preproc_unb=mean_b0_preprocessed_unb.nii.gz
mean_b0_preproc_unb_masked=mean_b0_preprocessed_unb_bet.nii.gz
if [ ! -f $mean_b0_preproc_unb ]; then
	N4BiasFieldCorrection -d 3 -i $mean_b0_preproc -o $mean_b0_preproc_unb
	bet $mean_b0_preproc_unb $mean_b0_preproc_unb_masked -f 0.3 -m -R
fi


echo "          #7 convert mean b0 mif to nii.gz files"
# convert T1.mgz to other formats
#T1=T1.mgz
T1_raw=T1_raw_sz1.nii.gz
#T1_raw_unb=T1_raw_sz1_unb.nii.gz
T1_raw_unb_masked=T1_raw_bet_unb.nii.gz
brain=brain.mgz
brain_raw=brain.nii.gz
#mrconvert $T1 $T1_raw 

# use ANTS to do biase field correction,
#[ ! -f $T1_raw_unb ] && N4BiasFieldCorrection -d 3 -i $T1_raw -o $T1_raw_unb
mrconvert  $brain $brain_raw -force
[ ! -f $T1_raw_unb_masked ] && N4BiasFieldCorrection -d 3 -i $brain_raw -o $T1_raw_unb_masked

echo "          #8 patch T1 image if leuko exists"
Fivett_nocoreg=5tt_nocoreg.mif

# rsong made change for correcting 5tt cropping to much problem
if [ $LE -eq 1 ]; then
	T1_raw_final0=T1_raw_patched_nocoreg.mif	
	[ ! -f $T1_raw_final0 ] && ${scrtDir}/patch_T1_new.sh $T1_raw_unb_masked $T1_raw_final0 $THREADS || echo "$T1_raw_final0 exists!" 
else
	T1_raw_final0=$T1_raw_unb_masked	
fi

# convert T1 to T2-like image
T2w0=T2w_mimic0.nii.gz
${scrtDir}/T1toT2.sh  $brain $T2w0 $TI $TE 0


# 5ttgen sometime generates a inaccurate 5tt images which doesn't cover the whole brain.	
# I crop images here to solve the problem.
# assumption: brain.mgz was generated from freesurfer with matrix size 256x256x256.
# you may need to change the crop size depending on your dataset.
x0=40
x1=230
y0=20
y1=220
z0=50
z1=220
crop_T1_raw=T1_raw.nii.gz
crop_T1_raw_masked=T1_raw_bet.nii.gz
T2w=T2w_mimic.nii.gz
#mrcrop  $T1 $crop_T1_raw -axis 0 $x0 $x1 -axis 1 $y0 $y1 -axis 2 $z0 $z1 -force
mrcrop  $brain $crop_T1_raw_masked -axis 0 $x0 $x1 -axis 1 $y0 $y1 -axis 2 $z0 $z1 -force
mrcrop  $T2w0 $T2w -axis 0 $x0 $x1 -axis 1 $y0 $y1 -axis 2 $z0 $z1 -force

# rsong crop T1_raw_final0 image and 5tt
T1_raw_final=brain_for_5tt.mif
mrcrop -nthreads $THREADS $T1_raw_final0 $T1_raw_final -axis 0 $x0 $x1 -axis 1 $y0 $y1 -axis 2 $z0 $z1 -force
echo "		#9 create 5tt-image"
if [ ! -f $Fivett_nocoreg ]; then
	5ttgen -nthreads $THREADS fsl -premasked $T1_raw_final $Fivett_nocoreg -force
fi
#####################

echo "		#10 flirt to generate coregistration matrix diff2struct coregstration matrix"
b02T1_mat=diff2struct_fsl.mat
if [ ! -f $b02T1_mat ]; then
	flirt -in $mean_b0_preproc_unb_masked -ref $T2w -interp sinc -dof 6 -omat $b02T1_mat  # use T2_mimic image
fi


echo "		#11 find the coregistration matrix of diff2struct"
b02T1_txt=diff2struct_mrtrix.txt
if [ ! -f $b02T1_txt ]; then
	transformconvert -nthreads $THREADS $b02T1_mat $mean_b0_preproc_unb_masked $T2w flirt_import $b02T1_txt -force
fi


echo "		#12 convert and generate hcpmmp1 files" 
parcels_nocoreg=hcpmmp1_parcels_nocoreg.mif
parcels=hcpmmp1.mgz
parcels_raw=hcpmmp1.mif
if [ ! -f $parcels_nocoreg ]; then
[ ! -f $parcels_raw ] && mrconvert -nthreads $THREADS -datatype uint32 $parcels $parcels_raw -force
labelconvert -nthreads $THREADS $parcels_raw /opt/mrtrix3/share/mrtrix3/labelconvert/hcpmmp1_original.txt /opt/mrtrix3/share/mrtrix3/labelconvert/hcpmmp1_ordered.txt $parcels_nocoreg
fi


echo "		#13 registration"
parcels_coreg=hcpmmp1_parcels_coreg.mif
#T1_coreg=T1_raw_coreg.mif
T1_coreg_masked=T1_raw_bet_coreg.mif
Fivett_coreg=5tt_coreg.mif
T2w_coreg=T2w_mimic_coreg.nii.gz
if [ ! -f $parcels_coreg ]; then
	#mrtransform -nthreads $THREADS $crop_T1_raw -linear $b02T1_txt -inverse $T1_coreg -force
	mrtransform -nthreads $THREADS $crop_T1_raw_masked -linear $b02T1_txt -inverse $T1_coreg_masked -force
	mrtransform -nthreads $THREADS $parcels_nocoreg -linear $b02T1_txt -inverse $parcels_coreg -force
	mrtransform -nthreads $THREADS $Fivett_nocoreg -linear $b02T1_txt -inverse $Fivett_coreg -force
	
	#mrtransform -nthreads $THREADS $T2w -linear $b02T1_txt -inverse $T2w_coreg -force
	${scrtDir}/T1toT2.sh  $T1_coreg_masked $T2w_coreg $TI $TE 1
	#5tt2vis -nthreads $THREADS $Fivett_coreg 5tt_vis_coreg.nii.gz -force
fi


echo "		#14 preparing a mask - - grey matter and white matter boundary (seeds)"
seeds=gmwmSeed_coreg.mif
dwi_den_unr_preproc_nii=dwi_den_unr_preproc.nii.gz
dwi_inter_corr=dwi_raw_distcorr_hwsinc.nii.gz
dwi_inter0=dwi_raw_distcorr_0.mif
dwi_corr=dwi_raw_distcorr.nii.gz
mask_dwi_corr=mask_dwi_den_unr_preproc_sz1.mif
if [ ! -f $seeds ]; then
	5tt2gmwmi -nthreads $THREADS $Fivett_coreg $seeds
fi

mrconvert -nthreads $THREADS $dwi_den_unr_preproc $dwi_den_unr_preproc_nii -force -datatype float64 # -datatype uint32 causes some bright voxels.

# distortion correction
oStr=D2T_
interp=HammingWindowedSinc #BSpline
${scrtDir}/antsDWIReg.sh 3  $mean_b0_preproc_unb_masked $T2w_coreg  $oStr $interp 
antsApplyTransforms -d 3 -e 3 -i $dwi_den_unr_preproc_nii -r $T2w_coreg -o $dwi_inter_corr -t [${oStr}0GenericAffine.mat,1] -t ${oStr}1InverseWarp.nii.gz --interpolation $interp 


# chop off abormally large and small (negative) values
mrcalc -nthreads $THREADS $dwi_inter_corr 4600 -lt $dwi_inter_corr 0 -if $dwi_inter0 -force
mrcalc -nthreads $THREADS $dwi_inter0 0 -gt $dwi_inter0 0 -if $dwi_corr -force

# create a mask
#mrcalc  ${oStr}_InverseWarped.nii.gz 1 -gt $mask_dwi_corr -force
mrthreshold -abs 0.9 ${oStr}InverseWarped.nii.gz $mask_dwi_corr -force # change the threshold if needed


echo "		#15 computing white matter response function"
wm=wm.txt
gm=gm.txt
csf=csf.txt
if [ ! -f $wm ]; then
	dwi2response -nthreads $THREADS dhollander  $dwi_corr -grad grad.txt -mask $mask_dwi_corr $wm $gm $csf -voxels voxels.mif  -force
fi


echo "		#16 Fiber orientation distribution estimation"
wmfod=wmfod.mif
gmfod=gmfod.mif
csffod=csffod.mif
if [ ! -f $wmfod ]; then
	dwi2fod -nthreads $THREADS msmt_csd -grad grad.txt $dwi_corr -mask $mask_dwi_corr $wm $wmfod $gm $gmfod $csf $csffod -force
fi


echo "		#17 intensity normalization"
wmfod_norm=wmfod_norm.mif
if [ ! -f $wmfod_norm ]; then
	mtnormalise -nthreads $THREADS $wmfod $wmfod_norm -mask $mask_dwi_corr -force
fi


echo "		#18 create streamlines ($THREADS used)"
tracks=tracks_20mio.tck
if [ ! -f $tracks ]; then
	tckgen -nthreads $THREADS -act  $Fivett_coreg -backtrack -seed_gmwmi $seeds -select 20000000 $wmfod_norm $tracks -force
fi


echo "		#19 SIFT2........."
sift2=sift2_wfactor.txt
if [ ! -f $sift2 ]; then
	tcksift2 -nthreads $THREADS $tracks $wmfod_norm $sift2 -act $Fivett_coreg -proc_mask $mask_dwi_corr -force
fi
tckedit $tracks -number 200k SIFT2_200k.tck -tck_weights_in $sift2 -force


echo "		#20 track to connectivity: 379x379 matrix : "
csv=hcpmmp2.csv
if [ ! -f $csv ]; then
	tck2connectome -nthreads $THREADS -symmetric -zero_diagonal -scale_invnodevol -tck_weights_in $sift2  $tracks $parcels_coreg $csv -out_assignment assignments_hcpmmp2.csv
fi


# clean house
mv D2T2_tso_Warped.nii.gz mean_b0_distcorr.nii.gz
rm -f $dwi_den $dwi_den_unr D2T2_tso_* $wmfod $gmfod $csffod $mean_b0_preproc $mean_b0_preproc_unb_masked $T1 $T1_raw $T1_raw_unb_masked $brain $Fivett_nocoreg  $T2w0 $crop_T1_raw $crop_T1_raw_masked $T2w $parcels_nocoreg $parcels $parcels_raw $dwi_den_unr_preproc_nii $dwi_inter_corr $dwi_inter0
# rm -f $brain_raw $T1_raw_unb
