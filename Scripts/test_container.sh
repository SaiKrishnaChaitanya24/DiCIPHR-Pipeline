#!/bin/bash
export TMPDIR=/tmp/test
mkdir -p $TMPDIR

# Run the first command
/usr/local/bin/Scripts/brainmage.sh -s IXI242 -i /usr/local/Input/IXI242/IXI242-HH-1722-T1.nii.gz -o $TMPDIR
status1=$?

# Run the second command
/usr/local/lib/python3.12/dist-packages/diciphr/scripts/dti_estimate.py -d /usr/local/Input/IXI242/IXI242-HH-1722-DTI.nii.gz -o $TMPDIR
status2=$?

# Check if both commands were successful
if [ $status1 -eq 0 ] && [ $status2 -eq 0 ]; then
    echo "Container Test Successful, Please Run the Container"
    echo "Maintainer: Drew Parker <william.parker@pennmedicine.upenn.edu> and Sai Krishna Chaitanya Annavazala <SaiKrishna.Annavazala@pennmedicine.upenn.edu>"
    echo "Version: 1.0.0"
else
    echo "One or both commands failed. Please check the error messages."
fi

