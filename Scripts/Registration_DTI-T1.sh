#! /bin/bash

pipeline_name="Registration_DTI-T1"
source $PROJECT_DIR/bin/Scripts/pipeline_utils.sh 

usage() {
    cat << EOF
Usage: $0  -s subject -d dwi -m DWI_MASK -t T1 [ -o OUTDIR ] [ -x T1_MASK ] 
          [ -w ] [ -T TRANSFORM_TYPE=r ] [ -p PHASE_ENCONDING=AP ] [ -F 0.7 ] [ -G 0.3 ] 
Required arguments:
    -s    <str>    Subject ID, a prefix for output files
    -d    <nii>    DWI, bval/bvec files must be named correspondingly, i.e. dwi.nii.gz, dwi.bval, dwi.bvecs
    -m    <nii>    DWI space mask
    -t    <nii>    T1 image
Optional arguments:
    -o    <path>   Output directory of the registration pipelines, if not provided will 
                   default to $PROJECT_DIR/Protocols/Registration
    -x    <nii>    T1 mask, if T1 passed is not itself skull-stripped, this is required.
    -T    <str>    Transformation type. Options are: r (Default - rigid), s(SyN with restricted deformation)
    -w             Use a temporary directory within the output directory and do not delete it after completion.
SyN with restricted deformation mode options:
    -p    <str>    Phase encoding direction of the dwi data. Options are AP, or LR.
    -F    <float>  Weight (0-1) of the B0/T1 image pair in SyN registration step. Default=0.7
    -G    <float>  Weight (0-1) of the FA/T1 image pair in SyN registration step. Default=0.3
EOF
    exit 1 
}

#### PARAMETERS AND GETOPT  ##################
phase_encoding="AP"
transform_type="r"
F=0.7
G=0.3
initialxfmfile=""
while getopts ":s:d:t:m:o:x:p:T:F:G:whu" opt; do
    case ${opt} in
        h,u) usage;; 
        s)
            subject=$OPTARG ;;
        d)
            dwi=$OPTARG ;;
        t)
            t1=$OPTARG ;;
        m)
            mask=$OPTARG ;; 
        o)
            outdir=$OPTARG ;;
        x)
            t1_mask=$OPTARG ;;
        p)
            phase_encoding=$OPTARG ;;
        T) 
            transform_type=$OPTARG ;; 
        F)
            F=$OPTARG;;
        G)  
            G=$OPTARG;; 
        w)
            workdir="True" ;; 
        \?)
          log_error "Invalid option: $OPTARG" 1>&2
          usage
          ;;
        :)
          log_error "Invalid option: $OPTARG requires an argument" 1>&2
          usage 
          ;;
    esac
done

##### ENSURE ALL ARGUMENTS ###############
if [ -z "$dwi" ] || [ -z "$t1" ] || [ -z "$subject" ] || [ -z "$mask" ]; then 
    log_error "Provide all required options"
    usage 
fi
if [ -z "$outdir" ]; then 
    outdir="$PROJECT_DIR/Protocols/Registration/${pipeline_name}/${subject}"
else
    outdir="$outdir"
fi 
mkdir -p $outdir
setup_logging
setup_workdir
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$SLURM_CPUS_PER_TASK
log_info "ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS: $ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS"
log_info "Subject: $subject"
log_info "dwi: $dwi"
log_info "t1: $t1"
log_info "phase_encoding: $phase_encoding"

if [ "$phase_encoding" == "AP" ] || [ "$phase_encoding" == "PA" ]; then
    restrict_deformation="0.1x1.0x0.1"
elif [ "$phase_encoding" == "LR" ] || [ "$phase_encoding" == "RL" ]; then 
    restrict_deformation="1.0x0.1x0.1"
elif [ "$phase_encoding" == "SI" ] || [ "$phase_encoding" == "IS" ]; then 
    restrict_deformation="0.1x0.1x1.0"
else
    log_error "Phase encoding direction $phase_encoding not recognized"
    exit 1 
fi 
if [ "$transform_type" == "a" ] || [ "$transform_type" == "r" ] || [ "$transform_type" == "s" ]; then   
    log_info "transform_type: $transform_type"
else
    log_error "Transform type $transform_type not recognized"
    exit 1 
fi

#################################################
log_info "Checking for required input files"
checkexist "$t1" "$dwi" || exit 1
if [ -n "$mask" ]; then 
    checkexist "$mask" || exit 1 
fi

#################################################
##########           BEGIN           ############
#################################################

# If t1 mask was not provided, assume t1 is skull-stripped already and create it 
if [ -z "$t1_mask" ]; then
    t1_mask=$tmpdir/t1_mask.nii.gz 
    log_run fslmaths $t1 -bin $t1_mask 
fi 
checkexist $t1_mask || exit 1  

# T1 preprocessing steps
log_info "Resample the T1 to 1mm, bias correct the t1 and mask"
log_run /usr/local/lib/python3.12/dist-packages/diciphr/scripts/resample_image.py -i $t1 -o $tmpdir/t1_1mm.nii.gz -r 1 -n Linear 
log_run /usr/local/lib/python3.12/dist-packages/diciphr/scripts/resample_image.py -i $t1_mask -o $tmpdir/t1_mask_1mm.nii.gz -m $tmpdir/t1_1mm.nii.gz -n GenericLabel 

if [ ! -e "$tmpdir/t1_bias.nii.gz" ]; then 
    log_run N4BiasFieldCorrection -d 3 -i $tmpdir/t1_1mm.nii.gz  \
        -o [$tmpdir/t1_n4_1mm.nii.gz,$tmpdir/t1_bias.nii.gz] \
        -x $tmpdir/t1_mask_1mm.nii.gz \
        -b [180,3] -c [50x50x50x50, 0.0] \
        -v 1 
fi 
log_run fslmaths $tmpdir/t1_mask_1mm.nii.gz -bin -mul $tmpdir/t1_1mm.nii.gz $tmpdir/t1_1mm_masked.nii.gz

# DTI Preprocessing steps
log_info "Extract the B0"  
log_run /usr/local/lib/python3.12/dist-packages/diciphr/scripts/extract_b0.py -d $dwi -o $tmpdir/b0.nii.gz
if [ -z "$mask" ]; then 
    log_info "No DTI space mask provided. Running BET on B0" 
    log_run bet2 $tmpdir/b0.nii.gz $tmpdir/b0 -nm -f 0.2 -g 0.0 
else
    # Binarize in case an FA map or something is passed as mask... 
    log_run fslmaths $mask -bin $tmpdir/b0_mask.nii.gz
fi   
log_info "Calculate FA" 
log_run /usr/local/lib/python3.12/dist-packages/diciphr/scripts/dti_estimate.py -d $dwi -m $tmpdir/b0_mask.nii.gz -o $tmpdir/orig

log_info "Resample B0 and FA to 1mm" 
log_run /usr/local/lib/python3.12/dist-packages/diciphr/scripts/resample_image.py -i $tmpdir/b0.nii.gz -o $tmpdir/b0_1mm.nii.gz -r 1 -n Linear 
log_run /usr/local/lib/python3.12/dist-packages/diciphr/scripts/resample_image.py -i $tmpdir/orig_tensor_FA.nii.gz -o $tmpdir/fa_1mm.nii.gz -m $tmpdir/b0_1mm.nii.gz -n Linear 
log_run /usr/local/lib/python3.12/dist-packages/diciphr/scripts/resample_image.py -i $tmpdir/b0_mask.nii.gz -o $tmpdir/b0_mask_1mm.nii.gz -m $tmpdir/b0_1mm.nii.gz -n GenericLabel 

log_info "Bias correct the B0" 
if [ ! -e "$tmpdir/bias.nii.gz" ]; then 
    log_run N4BiasFieldCorrection -d 3 -i $tmpdir/b0_1mm.nii.gz \
        -o [$tmpdir/b0_1mm_n4.nii.gz,$tmpdir/bias.nii.gz] \
        -x $tmpdir/b0_mask_1mm.nii.gz \
        -b [180,3] -c [50x50x50x50, 0.0] \
        -v 1 
fi 
log_info "Mask the B0" 
log_run fslmaths $tmpdir/b0_mask_1mm.nii.gz -bin -mul $tmpdir/b0_1mm_n4.nii.gz $tmpdir/b0_1mm_masked.nii.gz
log_run fslmaths $tmpdir/b0_mask_1mm.nii.gz -bin -mul $tmpdir/fa_1mm.nii.gz $tmpdir/fa_1mm_masked.nii.gz

################################
#####   REGISTRATION       #####
dicoPrefix=$outdir/${subject}_dico-
dico_warp=${dicoPrefix}0Warp.nii.gz
dico_invwarp=${dicoPrefix}0InverseWarp.nii.gz
affineDTItoT1Prefix=$outdir/${subject}_DTI-T1-
affineDTItoT1=${affineDTItoT1Prefix}0GenericAffine.mat

t1_target="$tmpdir/t1_1mm_masked.nii.gz"
b0_target="$tmpdir/b0_1mm_masked.nii.gz"

# ants AI - get quick estimate of the best B0 -> T1 rigid registration 
log_info "Initialize B0->T1 with antsAI" 
log_run antsAI \
    -d 3 \
    -t Rigid \
    -m Mattes[$t1_target,$b0_target,32,Regular,0.25] \
    -p 0 \
    -o $tmpdir/antsAI_rigid.mat \
    -v 1 
    
log_run antsApplyTransforms -d 3 -i $b0_target -o $tmpdir/b0-t1_antsAI.nii.gz \
    -r $t1_target -t $tmpdir/antsAI_rigid.mat --float -v 1 

# antsRegistration - do b0 -> T1 registration, initializing from antsAI 
log_run antsRegistration \
    --verbose 1 --dimensionality 3 --float 0 --collapse-output-transforms 1 \
    --output [$affineDTItoT1Prefix,$tmpdir/AffineB0-T1_1_Warped.nii.gz,$tmpdir/AffineB0-T1_1_InverseWarped.nii.gz] \
    --initial-moving-transform $tmpdir/antsAI_rigid.mat \
    --interpolation Linear --use-histogram-matching 0 --winsorize-image-intensities [0.025,0.975] \
    --transform Rigid[0.1] \
    --metric MI[$t1_target,$b0_target,1,32,Regular,0.25] \
    --convergence [1000x500x250x100,1e-6,10] \
    --shrink-factors 8x4x2x1 --smoothing-sigmas 3x2x1x0vox

# if SyN registration, 
# # 1.) SyN registration in DTI space, initialized by inverse of b0->t1 rigid, restricted to AP direction 
# # 2.) re-do b0->T1 registration 
if [ "$transform_type" == "s" ]; then
    ## SyN registration in DTI space, restricted to AP direction
    log_run antsRegistration \
        --verbose 1 --dimensionality 3 --float 0 --collapse-output-transforms 1 \
        --initial-fixed-transform [$affineDTItoT1,1] \
        --interpolation Linear --use-histogram-matching 0 --winsorize-image-intensities [0.025,0.975] \
        --convergence [100x70x50x20,1e-6,10] --shrink-factors 8x4x2x1 --smoothing-sigmas 3x2x1x0vox \
        --transform SyN[0.1,3,0] -g "$restrict_deformation" \
        --output [$dicoPrefix,$tmpdir/fa-Warped.nii.gz] \
        --metric MI[$tmpdir/t1_1mm_masked.nii.gz,$tmpdir/fa_1mm_masked.nii.gz,$G,32] \
        --metric MI[$tmpdir/t1_1mm_masked.nii.gz,$tmpdir/b0_1mm_masked.nii.gz,$F,32]
    
    b0_target=$tmpdir/b0_dico.nii.gz
    log_run antsApplyTransforms -d 3 -i $tmpdir/b0_1mm_masked.nii.gz -o $b0_target \
        -r $tmpdir/b0_1mm_masked.nii.gz -t $dico_warp -n Linear --float -v 1 
        
    # re-run rigid with distortion corrected b0 
    log_run antsRegistration \
        --verbose 1 --dimensionality 3 --float 0 --collapse-output-transforms 1 \
        --output [$affineDTItoT1Prefix,$tmpdir/AffineB0-T1_2_Warped.nii.gz,$tmpdir/AffineB0-T1_2_InverseWarped.nii.gz] \
        --initial-moving-transform $tmpdir/antsAI_rigid.mat \
        --interpolation Linear --use-histogram-matching 0 --winsorize-image-intensities [0.025,0.975] \
        --transform Rigid[0.1] \
        --metric MI[$t1_target,$b0_target,1,32,Regular,0.25] \
        --convergence [1000x500x250x100,1e-6,10] \
        --shrink-factors 8x4x2x1 --smoothing-sigmas 3x2x1x0vox
fi 

## Bring t1 to native res DTI space 
if [ "$transform_type" == "s" ]; then
    log_run antsApplyTransforms -d 3 -i $t1 -o $outdir/${subject}_T1-DTI.nii.gz \
        -r $tmpdir/orig_tensor_FA.nii.gz -t $dico_invwarp [$affineDTItoT1,1] -n Linear --float -v 1 
else
    log_run antsApplyTransforms -d 3 -i $t1 -o $outdir/${subject}_T1-DTI.nii.gz \
        -r $tmpdir/orig_tensor_FA.nii.gz -t [$affineDTItoT1,1] -n Linear --float -v 1 
fi 

if [ "$cleanup" == "True" ]; then 
    log_info "Cleaning up" 
    rm -rf $tmpdir 
fi 

log_info "Done" 
