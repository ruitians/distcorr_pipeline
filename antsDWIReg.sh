#! /bin/bash
set -e
set -u

#scipt to coregister T1 to b0 image
# usage dwiRegistration.sh dimension fixed_image moving_iamge output_prefix
# usage: antsDWIReg.sh dim FI MI
DIM=$1
FI=$2
MI=$3
OUTPUTNAME=$4
INTERP=$5
#fMASK=$6
#mMASK=$7

antsRegistration \
--verbose 1 \
--dimensionality $DIM \
--float 0 \
--collapse-output-transforms 1 \
--output [ ${OUTPUTNAME},${OUTPUTNAME}Warped.nii.gz,${OUTPUTNAME}InverseWarped.nii.gz ] \
--interpolation ${INTERP} \
--restrict-deformation 0x1x0 \
--use-histogram-matching 1 \
--winsorize-image-intensities [ 0.005,0.995 ] \
--initial-moving-transform [ $FI,$MI,1 ] \
--transform Rigid[ 0.1 ] \
--metric MI[ $FI,$MI,1,32,Regular,0.25 ] \
--convergence [ 1000x500x250x0,1e-6,10 ] \
--shrink-factors 8x4x2x1 \
--smoothing-sigmas 3x2x1x0vox \
--transform Affine[ 0.1 ] \
--metric MI[ $FI,$MI,1,32,Regular,0.25 ] \
--convergence [ 1000x500x250x0,1e-6,10 ] \
--shrink-factors 8x4x2x1 \
--smoothing-sigmas 3x2x1x0vox \
--transform SyN[ 0.1,3,0.5 ] \
--metric CC[$FI,$MI,1,8] \
--convergence [ 100x70x50x0,1e-6,10 ] \
--shrink-factors 8x4x2x1 \
--smoothing-sigmas 2x0.5x0x0vox 
#--masks [$fMASK, $mMASK] 

echo "antsRegistration done: fixed iamge: $FI; moving image: $MI; output: $OUTPUTNAME interpolation: ${INTERP}"
#--transform Similarity[ 0.1,3,0.5 ] \
#--transform SyN[ 0.1,3,0.5 ] \
#-metric CC[ $FI,$MI,1,8] \
#--metric MI[ $FI,$MI,1,40] \
#--interpolation HammingWindowedSinc \
# --smoothing-sigmas 3x2x1x0vox \ for tranform Rigid
#--write-composite-transform 1 \
#--initialize-transforms-per-stage 1 \
