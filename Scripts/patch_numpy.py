#!/usr/bin/env python

# patch_numpy.py
import numpy as np

# Monkeypatch deprecated NumPy aliases
np.object = object
np.bool = bool
np.string = str
np.integer = int

