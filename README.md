#         DTI Distortion Correction Pipeline
The processing pipeline to perform distortion correction and Leukoencephalopathy (LE) patching for DTI structure connectome

### Prerequisites  
-Installed FSL 6.     
-Installed MRTrix3.   
-Installed ANTs.   

The scripts use following files:  
DWI files in dcm format under folder name included DTI   
brain.mgz : an extracted brain image generated by freesurfer.  
hcpmmp1.mgz and aparc+aseg.mgz.  

### Scripts   
mrtrixdistcorr_pipeline.sh is the main script.  
##### Usage:
1. mrtrixdistcorr_pipeline.sh ProjDir MRN ExamDate TimePoint LE(0 or 1) THREADS  
assuming the path is   
ProjDir/MRN-TimePoint/DWI    
LE patching (yes 1, no 0)   
THREADS: number of threads used in the calcualtion   

2. T1toT2.sh covert T1w image to T2w image   
T1toT2.sh $1(brain skull removed)  $2 (output) $3 (TI value)  $4 TE $5 (coreg? 0 no, 1 yes)   

3. patch_T1_new.sh  patch LE hypointensive T1w image or not.    
patch_T1_new.sh $1(input T1 image) $2(output, patched T1 image)   

-----------
The scripts are for research use purpose only without any kind of warranty.  Use at your own risk.
