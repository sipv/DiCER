# Kevin Aquino
# Brain and Mental Health Research Hub
# 2019
#
# This is a python script to generate a carpet plot from given arguments.

import warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)
warnings.filterwarnings("ignore", category=FutureWarning)

# Import the right things.
import sys
import os
import numpy as np
from scipy import stats
import nibabel as nib

# Take a signal, then reorder using this.

def main(raw_args=None):
    CIFTI_SIZE = 98301
    FWD_DIM_TARGET = (7, 4681, 3)
    BWD_DIM_TARGET = (32767, 3, 1)

    assert np.product(FWD_DIM_TARGET) == np.product(BWD_DIM_TARGET) == CIFTI_SIZE     # Just to be sure

    # Parse in inputs
    from argparse import ArgumentParser
    parser = ArgumentParser(epilog="reshapeSurfaceNifti.py -- A function to reshape a surface nifti so that all dimensions have a size >1 . Kevin Aquino 2018 BMH")
    parser.add_argument("-f", dest="func",
                        help="functional MRI time series", metavar="fMRI.nii.gz")
    parser.add_argument("-o", dest="outputFileName",
                        help="output of functional MRI time series", metavar="out.nii.gz")

    group = parser.add_mutually_exclusive_group()
    group.add_argument('--forward',  action='store_const', dest='mode', const='forward', default='forward')
    group.add_argument('--backward', action='store_const', dest='mode', const='backward')


    args = parser.parse_args(raw_args)
    data = nib.load(args.func).get_fdata()

    if np.product(data.shape[:-1]) == CIFTI_SIZE:
        if args.mode == 'forward':
            print('CIFTI-like NIFTI detected! i.e. total length is %u. Reshaping to fill in all dimensions!' % (CIFTI_SIZE))
            data_reshaped = np.reshape(data, (*FWD_DIM_TARGET, -1))
            img = nib.Nifti1Image(data_reshaped, np.eye(4))
            nib.save(img, args.outputFileName)

        elif args.mode == 'backward':
            print('CIFTI-like NIFTI detected! i.e. total length is %u. Reshaping to original size!' % (CIFTI_SIZE))
            data_reshaped = np.reshape(data, (*BWD_DIM_TARGET, -1))
            img = nib.Nifti1Image(data_reshaped, np.eye(4))
            nib.save(img, args.outputFileName)



if __name__ == '__main__':
        main()
