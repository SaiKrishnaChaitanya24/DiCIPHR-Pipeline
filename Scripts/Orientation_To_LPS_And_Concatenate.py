#! /usr/bin/env python

import os
import argparse
import sys

# Add the path to your functions module to the system path
sys.path.append('~/.local/lib/python3.6/site-packages/diciphr/scripts')

def rename_files(directory):
    for filename in os.listdir(directory):
        # Remove spaces and replace with underscores, and capitalize the first letter of each word
        new_filename = '_'.join(word.capitalize() for word in filename.split(' '))
        old_file = os.path.join(directory, filename)
        new_file = os.path.join(directory, new_filename)
        os.rename(old_file, new_file)
        print(f'Renamed: {old_file} to {new_file}')

def main():
    parser = argparse.ArgumentParser(description='Process files and execute functions.')
    parser.add_argument('--directory', required=True, help='Path to the directory containing the files')
    parser.add_argument('--file', required=True, help='Path to the file for additional functions')
    args = parser.parse_args()

    rename_files(args.directory)
    concatenate_dwis.py -d $DWI1 $DWI2 -o $DWI_CONCATENATED
    reorient_nifti.py -i $DWI_CONCATENATED -o $DWI_LPS -r LPS

if __name__ == '__main__':
    main()

