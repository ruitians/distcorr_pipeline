#!/bin/bash
# the script to convert T1 to T2 image
# T1 to pseudo T2, also consider proton density

set -e
set -u

# usage: T1toT2 $1(brain skull removed)  $2 (output) $3 (TI value)  $4 TE $5 (coreg? 0 no, 1 yes)

#smoothen T1 image ?

T1w=$1 # input brain T1 image
T2w=$2 # output T2w iamge 
TI=$3 # TI value of MPRAGE T=900
TE=$4 # TE of DTI EPI 84 for 64directions
bCoreg=$5

if [ $bCoreg -eq 1 ]; then
	strReg=coreg
else
	strReg=nocoreg
fi
# create masked wm and gm image

BTT5=B5tt_${strReg}.mif
TT5=5tt_${strReg}.mif

# create masked wm and gm mask
if [ $bCoreg -eq 1 ]; then
	mrtransform $TT5 -template $T1w - | mrthreshold -abs 0.4 - $BTT5 -force -quiet
	mrconvert -coord 3 0 $BTT5 gm_coreg_mask.mif -force  #gray matter  0
	mrconvert -coord 3 2 $BTT5 wm_coreg_mask.mif -force  #white matter 2
else
	# create masked wm image
	parc_seg=aparc+aseg.mgz
	[ ! -f input.mif ] && mrconvert $parc_seg input.mif
	# change to your freesurfer and mrtrix files
	[ ! -f indices.mif ] && labelconvert input.mif /wer/total16/Scripts/FreeSurferColorLUT.txt /opt/mrtrix3/share/mrtrix3/_5ttgen/FreeSurfer2ACT.txt indices.mif
	mrcalc indices.mif 1 -eq gm_${strReg}_mask.mif -force
	mrcalc indices.mif 3 -eq wm_${strReg}_mask.mif -force
fi

# find mean of white and gray matter
mrcalc  $T1w wm_${strReg}_mask.mif -multiply wm_seg_T1_${strReg}.nii.gz -force -quiet
mrcalc  $T1w gm_${strReg}_mask.mif -multiply gm_seg_T1_${strReg}.nii.gz -force -quiet
wm_mean=$(fslstats wm_seg_T1_${strReg}.nii.gz -M)
gm_mean=$(fslstats gm_seg_T1_${strReg}.nii.gz -M)

# find A and B
A=$(mrcalc $gm_mean -2.1 -multiply 3.5 $wm_mean -multiply -add)
B=$(mrcalc $gm_mean -4.8 -multiply 5.7 $wm_mean -multiply -add)
ratio=$(mrcalc $B $A -divide)

echo "A = $A ; B = $B"
echo " wm = $wm_mean   gm = $gm_mean "

#TI=-900
mask=brain_mask_${strReg}.nii.gz
mrthreshold -abs 0.001 $T1w $mask -force -quiet

# calculating T1 map: T1=-TI/ln[(A-S1)/B]
mrcalc $((-TI)) $A $T1w -subtract $B -divide -log -divide $mask -multiply -abs T10_mimic_${strReg}.mif -force -quiet
# chop off high values (4000), This may not be necessary. check your images
mrcalc T10_mimic_${strReg}.mif 4000 -gt 4000 T10_mimic_${strReg}.mif -if tmp.mif -force -quiet 
mrcalc tmp.mif 0 -lt 0 tmp.mif -if T1_mimic_${strReg}.mif -force
rm -f tmp.mif

mrcalc T1_mimic_${strReg}.mif 0.04 -multiply 26 -add -abs T2_mimic_${strReg}.mif -force -quiet

# find mean b0 images on wm and gray matter masks
# use fast to segment wm and gm in b0, not ideal, but good enough to estimate 
if [ bCoreg -eq 0 ]; then
	fast -t 2 -H 0.3 -R 0.5 -o b0 mean_b0_preprocessed_unb_bet.nii.gz 
	mrcalc b0_pve_1.nii.gz 0.5 -gt mean_b0_preprocessed_unb_bet.nii.gz  -multiply wm_seg_b0.nii.gz -force
	# gm mask also include some csf too
	mrcalc b0_pve_0.nii.gz 0.5 -gt mean_b0_preprocessed_unb_bet.nii.gz  -multiply gm_seg_b0.nii.gz -force 
	rm -f b0_pve_0.nii.gz b0_pve_1.nii.gz b0_pve_2.nii.gz
else
	mrtransform -template $T1w mean_b0_preprocessed_unb_bet.nii.gz mean_b0_preprocessed_unb_bet_sz1.nii.gz -force
	mrcalc mean_b0_preprocessed_unb_bet_sz1.nii.gz wm_${strReg}_mask.mif -multiply wm_seg_b0.nii.gz -force -quiet
	mrcalc mean_b0_preprocessed_unb_bet_sz1.nii.gz gm_${strReg}_mask.mif -multiply gm_seg_b0.nii.gz -force -quiet
fi
wm_mean_b0=$(fslstats wm_seg_b0.nii.gz -n -M)
gm_mean_b0=$(fslstats gm_seg_b0.nii.gz -n -M)



echo " wm_b0 = $wm_mean_b0   gm_b0 = $gm_mean_b0 "
ratio_b0=$(mrcalc $gm_mean_b0 $wm_mean_b0 -divide) # grey and white matter ratio

mrcalc  T2_mimic_${strReg}.mif wm_${strReg}_mask.mif -multiply wm_seg_T2_${strReg}.nii.gz -force -quiet
mrcalc  T2_mimic_${strReg}.mif gm_${strReg}_mask.mif  -multiply gm_seg_T2_${strReg}.nii.gz -force -quiet

# find A0(proton density) from T1. rho0 signal:wm:70, gm:78, csf:100
# A0=46.24+0.011*T1
mrcalc T1_mimic_${strReg}.mif 0.011 -multiply 46.24 -add A0.mif -force

# white matter segmentation of A0
mrcalc A0.mif wm_${strReg}_mask.mif -multiply wm_seg_A0_${strReg}.nii.gz -force 
wm_mean_A0=$(fslstats wm_seg_A0_${strReg}.nii.gz -n -M)
wm_mean_T2=$(fslstats wm_seg_T2_${strReg}.nii.gz -n -M)

scale=$(mrcalc $wm_mean_b0 $TE $wm_mean_T2 -divide -exp -multiply $wm_mean_A0 -divide)

 
mrcalc $scale A0.mif -multiply -$TE T2_mimic_${strReg}.mif -divide -exp -multiply $mask -multiply -abs T2w_mimic.mif -force -quiet
mrfilter T2w_mimic.mif smooth $T2w -force 

# clean up house
#rm -f A0.mif T2w_mimic_smooth.nii.gz T2w_mimic.mif T1_mimic.mif T2_mimic0.mif T10_mimic.mif $mask wm_seg_T1_unb.nii.gz gm_seg_T1_unb.nii.gz indices.mif gm_mask.mif

