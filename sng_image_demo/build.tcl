set demo_dir [file dirname [file normalize [info script]]]
set build_dir [file join $demo_dir build]
file mkdir $build_dir
cd $build_dir
create_project -force sng_image $build_dir -part xc7a100tcsg324-1
foreach lut {lut_a.mem lut_b.mem} {
    set original [file join $demo_dir $lut]
    if {![file exists $original]} {error "Copy $lut from your project's Python_Code folder into $demo_dir"}
    add_files -norecurse $original
    set_property file_type {Memory Initialization Files} [get_files $original]
}
add_files -norecurse [list [file join $demo_dir image_top.sv] [file join $demo_dir demo_uart.sv]]
add_files -fileset constrs_1 -norecurse [file join $demo_dir image_demo.xdc]
set_property top image_top [current_fileset]
update_compile_order -fileset sources_1
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
set bitstream [file join [get_property DIRECTORY [get_runs impl_1]] image_top.bit]
if {![file exists $bitstream]} {error "Bitstream generation failed. See the synth_1 and impl_1 run logs."}
file copy -force $bitstream [file join $demo_dir image_top.bit]
puts "PROGRAM THIS FILE: [file join $demo_dir image_top.bit]"
