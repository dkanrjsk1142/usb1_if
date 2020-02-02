
echo "Library compile"                               >  comp_lib.log
echo "RTL compile"                                   >  comp_rtl.log

# --------------------------
# Library
# --------------------------
rm -rf work
vlib work

rm -rf alib
#mkdir alib

#vlib alib/altera_mf

#vmap altera_mf     alib/altera_mf

#vlog -work altera_mf     ../modelsim_lib/altera_mf.v >> comp_lib.log    

# --------------------------
# Copy .mif data
# --------------------------
cp ../source/*.mif .

# --------------------------
# Compile
# --------------------------

# --RTL
vlog ../source/usb_phy.v                             >> comp_rtl.log
vlog ../source/buffer.v                              >> comp_rtl.log

# --bench
vlog ../testbench/TB_USB1_IF_TOP.v                   >> comp_rtl.log
vlog ../testbench/tb_clk.v                           >> comp_rtl.log
vlog ../testbench/tb_usb_phy.v                       >> comp_rtl.log

# --------------------------
# Simulation
# --------------------------

# test pattern
if [ -z $1 ] ; then
	ctl="0_sim.ctl"
else
	ctl=$1"_sim.ctl"
fi

# MODE = -c | -gui
if [ -z $2 ] ; then
	MODE="-gui"
else
	MODE=$2
fi


vsim TB_USB1_IF_TOP -t ps -do $ctl $MODE -GSIM_MODE=1

mkdir result
mkdir result/$1

for f in $($ls 1*.do) ; do cp $f result/$1/ ; done
for f in $($ls 1*.ctl) ; do cp $f result/$1/ ; done
cp vsim.wlf   result/$1/$1.wlf
cp transcript result/$1/$1.log

# --------------------------
# Remove TEMP file
# --------------------------
rm ./*.mif
rm ./*.ver
