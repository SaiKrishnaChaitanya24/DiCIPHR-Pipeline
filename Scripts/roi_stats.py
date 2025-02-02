#! /usr/bin/env python

import numpy as np
np.float=float
np.int=int
import os, sys, shutil, logging, argparse, traceback
sys.path.append('/usr/local/lib/python3.8/dist-packages/diciphr')
from diciphr.utils import ( check_inputs, is_writable, 
                make_dir, protocol_logging, DiciphrException )
from diciphr.nifti_utils import ( read_nifti, write_nifti, 
                strip_nifti_ext, get_nifti_ext )
from diciphr.diffusion import is_tensor
from diciphr.statistics.roi_stats import sample_dti_roistats
import pandas as pd 
import glob
import tempfile

DESCRIPTION = '''
    Calculates ROI Statistics.
'''

PROTOCOL_NAME='ROI_Stats'

def buildArgsParser():
    p = argparse.ArgumentParser(description=DESCRIPTION)
    p.add_argument('-s', '--subjects', action='store', metavar='<csv>', dest='subjectfile',
                    type=str, required=True, 
                    help='A text file containing subject IDs'
                    )
    p.add_argument('-a', '--atlas', action='store', metavar='<nii>', dest='atlas_template',
                    type=str, required=True, 
                    help='Atlas file, or if atlases are in subject space, a template for the atlas with {s} to be replaced by subject ID.'
                    )
    p.add_argument('-f', '--filename', action='store', metavar='<nii>', dest='filename_template',
                    type=str, required=True,
                    help='A template for the data file, with {s} to be replaced by subject ID.'
                    )
    p.add_argument('-c', '--scalar', action='store', metavar='<str>', dest='scalar',
                    type=str, required=False, default='', 
                    help='The name of the scalar. Results will be written to {outdir}/ROIstats_{measure}_{scalar}.csv'
                    )
    p.add_argument('-o', '--outdir', action='store', metavar='<str>', dest='outdir',
                    type=str, required=False, default='.', 
                    help='The output directory'
                    )
    p.add_argument('-l', '--lut', action='store', metavar='<nii>', dest='atlas_lut',
                    type=str, required=False, default=None,
                    help='Atlas lookup csv'
                    ) 
    p.add_argument('-m', '--measures', action='store', metavar='<str>', dest='measures',
                    type=str, required=False, default=['mean'], nargs="*", 
                    help='The ROI measures, one or more of mean, median, std, volume.'
                    )
    p.add_argument('--debug', action='store_true', dest='debug',
                    required=False, default=False,
                    help='Debug mode'
                    )
    p.add_argument('--logfile', action='store', metavar='log', dest='logfile',
                    type=str, required=False, default=None,
                    help='A log file. If not provided will print to stderr.'
                    )
    return p

def get_labels_from_lut(lutfn):
    lut = pd.read_csv(lutfn)
    lblcol = lut.columns[0]
    namecol = lut.columns[1]
    # number of digits needed to represent all columns 
    maxroi = len(str(np.max([int(a) for a in lut[lblcol]])))
    roi_template = 'r{0:0' + str(maxroi) +'d}_{1}'
    roi_names = [roi_template.format(i,n) for i,n in zip(lut[lblcol], lut[namecol])]
    labels = list(lut[lblcol])
    return labels, roi_names     

def main(argv):
    parser = buildArgsParser()
    args = parser.parse_args(argv)
    make_dir(args.outdir, recursive=True, pass_if_exists=True)
    protocol_logging(PROTOCOL_NAME, args.logfile, debug=args.debug)
    # read lut if it exists
    labels = None
    roi_names = None
    if args.atlas_lut is not None:
        labels, roi_names = get_labels_from_lut(args.atlas_lut)
    if os.path.exists(args.subjectfile):
        cohort = pd.DataFrame(index = [a.strip() for a in open(args.subjectfile, 'r').readlines()])
    else:
        cohort = pd.DataFrame(index=[args.subjectfile])
    logging.info('Read subject IDs, n = {0}'.format(len(cohort)))
    logging.info('Scalar filename template: '+args.filename_template)
    logging.info('Scalar atlas template: '+args.atlas_template)
    cohort['datafile'] = [args.filename_template.format(s=s) for s in cohort.index]
    cohort['atlasfile'] = [args.atlas_template.format(s=s) for s in cohort.index]
    exists = np.logical_and(np.array([os.path.exists(fn) for fn in cohort['datafile']]), np.array([os.path.exists(fn) for fn in cohort['atlasfile']]))
    cohort = cohort.loc[exists, :]
    subjects = list(cohort.index)
    if len(subjects) == 0:
        logging.error('Found data and atlases for {} subjects'.format(len(subjects)))
        sys.exit(1)
    else:
        logging.info('Found data and atlases for {} subjects'.format(len(subjects)))
    atlasfiles = [ args.atlas_template.format(s=s) for s in subjects ]   
    datafiles = [ args.filename_template.format(s=s) for s in subjects ]
    logging.info('Calculate ROI stats')
    R = sample_dti_roistats(datafiles, atlasfiles, measures=args.measures, 
                    index=subjects, labels=labels, roi_names=roi_names)
    for m in args.measures:    
        output = '{outdir}/ROIstats_{measure}_{scalar}.csv'.format(outdir=args.outdir, measure=m, scalar=args.scalar)
        R[m].to_csv(output, index_label='Subject')
        logging.info(output)
    
    
if __name__ == '__main__':
    main(sys.argv[1:])
