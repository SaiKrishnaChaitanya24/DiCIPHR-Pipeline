#!/bin/bash

pipeline_name="DTI_Preprocess"
source $PROJECT_DIR/bin/Scripts/pipeline_utils.sh

# GETOPTS 
usage() { 
    echo "Run DTI preprocessing with options for topup or no distortion correction" 
    echo "$0 -s subject -d dwi.nii [ -o outdir ] [ -m mask.nii ]"
    echo "      [ -t reversePE_dwi.nii ] [ -p pe_dir=AP ]"
    echo "      [ -T readout_time=0.062 ] [ -w workdir ]" 
}
pe_dir="AP"
readout_time="0.062"
denoise="N"
gibbs="N"
dti_option=""
synbo=""

while getopts "hus:d:o:y:p:t:T:m:w:g:n:z:" opt; do
  case ${opt} in
      [h,u])
          usage;;
      s)
          subject="$OPTARG" ;;
      d)
          dwi="$OPTARG" ;;
      t)
          topup="$OPTARG" ;;
      y)
          synbo="$OPTARG" ;;
      m)
          mask="$OPTARG" ;;
      o)
          outdir="$OPTARG" ;;
      p)
          pe_dir="$OPTARG" ;;
      T)
          readout_time="$OPTARG" ;;
      w) 
          workdir="True" ;;
      g)
          gibbs=$OPTARG ;;
      n) 
          denoise=$OPTARG ;;
      z) 
          dti_option=$OPTARG ;;
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

# Check for required options subject, dwi
if [ -z "$subject" ] || [ -z "$dwi" ]; then
    usage
    echo "Provide all required inputs" 1>&2 
    exit 1 
fi

# Set up necessary directories, log file 
if [ -z "$outdir" ] ; then 
    outdir=$PROJECT_DIR/Output/$pipeline_name/${subject}
fi 
mkdir -p $outdir
setup_logging
setup_workdir 
log_info "Subject: $subject"
log_info "DWI: $dwi"
log_info "outdir: $outdir"

echo $gibbs
echo $denoise

# Check all necessary inputs
log_info "Check inputs" 
checkexist "$dwi" || exit 1 
if [ -n "$topup" ]; then
    log_info "topup: $topup"
    log_info "pe_dir: $pe_dir"
    checkexist "$topup" || exit 1 
    topupflag="-t $topup -p $pe_dir"
fi 

if [ -n "$synbo" ]; then
    log_info "synbo: $synbo"
    checkexist "$synbo" || exit 1
    synboflag="--synbo $synbo "
fi

if [ -n "$mask" ]; then
    log_info "mask: $mask"
    checkexist "$mask" || exit 1 
    maskflag="-m $mask"
fi

echo $outdir

base_outdir="${outdir%/DTI_Preprocess*}"

echo $base_outdir

if [ "$denoise" == "s" ] && [ "$gibbs" == "N" ]; then
    if [ "$dti_option" -eq 0 ]; then
        log_run /usr/local/lib/python3.12/dist-packages/diciphr/scripts/dti_preprocess.py -s $subject --no-denoise -d $dwi -o $outdir -T $readout_time --logfile $logfile --workdir $tmpdir $topupflag $maskflag $synboflag
        # Remove eddy input and outlier free data
        log_run rm -f $outdir/${subject}_eddy.eddy_outlier_free_data*
        log_run rm -f $outdir/${subject}_eddy_input_data*

        if [ "$cleanup" == "True" ]; then
            log_info "Clean up"
            log_run rm -rf $tmpdir
        fi
        exit 0
    fi
fi



if [ "$gibbs" == "s" ] && [ "$denoise" == "N" ]; then
    if [ "$dti_option" -eq 2 ]; then
        log_run /usr/local/lib/python3.12/dist-packages/diciphr/scripts/dti_preprocess.py -s $subject --gibbs -d $dwi -o $outdir -T $readout_time --logfile $logfile --workdir $tmpdir $topupflag $maskflag $synboflag
        log_run rm -f $outdir/${subject}_eddy.eddy_outlier_free_data*
        log_run rm -f $outdir/${subject}_eddy_input_data*

        if [ "$cleanup" == "True" ]; then
            log_info "Clean up"
            log_run rm -rf $tmpdir
        fi
        exit 0
    fi
fi

if [ "$gibbs" == "N" ] && [ "$denoise" == "N" ]; then
    if [ "$dti_option" -eq 1 ]; then
        log_run /usr/local/lib/python3.12/dist-packages/diciphr/scripts/dti_preprocess.py -s $subject -d $dwi -o $outdir -T $readout_time --logfile $logfile --workdir $tmpdir $topupflag $maskflag $synboflag
        log_run rm -f $outdir/${subject}_eddy.eddy_outlier_free_data*
        log_run rm -f $outdir/${subject}_eddy_input_data*

        if [ "$cleanup" == "True" ]; then
            log_info "Clean up"
            log_run rm -rf $tmpdir
        fi
        exit 0
    fi
fi
