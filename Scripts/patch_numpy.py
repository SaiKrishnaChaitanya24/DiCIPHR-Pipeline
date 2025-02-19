#!/usr/bin/env python

# patch_numpy.py
import numpy as np

np.object = object
np.bool = bool
np.string = str
np.integer = int

