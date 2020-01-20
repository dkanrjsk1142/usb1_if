# usb1_de0_nano
usb1.x interface in de0-nano FPGA board.

bus controller required.

real device test is by uart_de0_nano project.  
-> register setting & uart2usb flow testing

this project is based on Intel Quartus Prime 18.1 lite Edition.(free edition)  
(contain Modelsim - Intel FPGA Starter Edition 10.5b)


## directory description
  constraints : Quartus constraints files.  
  modelsim    : Modelsim simulation batch files.  
  modelsim_lib: Quartus library files for modelsim.  
*there is null file only(cannot compile)*  
*copy origin file from Intel Quartus Tools.*  
  source      : RTL source code.  
  testbench   : bench env for simulation(cannot synthesis).  
  .qpf        : Quartus Project File.  
  .qsf        : Quartus Settings File.  


## block diagram
*red marking is T.B.D*
<!-- ![Block dDiagram](block_diagram/top.png) -->

