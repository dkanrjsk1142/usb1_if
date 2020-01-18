# --------------------------------------------------------
# File Name   : copy_lib.py
# Description : copy library file for simulation from Quartus.
#               "QUARTUS_ROOTDIR" variables is necessery.
# --------------------------------------------------------
# Ver     Date       Author              Comment
# 0.01    2020.01.18 I.Yang              Create New
# --------------------------------------------------------

import os
import shutil

quartus_dir = os.environ['QUARTUS_ROOTDIR']

sim_lib_dir = os.path.join(quartus_dir, 'eda', 'sim_lib')

with open('./lib_list.txt', 'r') as f:
	for line in f:
		lib_file = line.replace('\n','')
		print(lib_file)
		shutil.copy(os.path.join(sim_lib_dir, lib_file), os.getcwd())
