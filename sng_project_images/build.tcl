# Run in full Vivado, not Vivado Lab Edition. Use a fresh session.
set root [file dirname [file normalize [info script]]]
set out [file join $root build]
file mkdir $out
create_project -force sng_project_images $out -part xc7a100tcsg324-1
foreach f {nexys4ddr_image_top.sv demo_uart.sv sng_experiment.sv sng_controller.sv sng.sv sng_lut.sv sng_comparator.sv lfsr_shuffle.sv} {
    add_files -norecurse [file join $root $f]
}
foreach f {lut_a.mem lut_b.mem lut_s.mem} {
    set path [file join $root $f]
    add_files -norecurse $path
    set_property file_type {Memory Initialization Files} [get_files $path]
}
add_files -fileset constrs_1 -norecurse [file join $root image_project.xdc]
set_property top nexys4ddr_image_top [current_fileset]
update_compile_order -fileset sources_1
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
set bit [file join [get_property DIRECTORY [get_runs impl_1]] nexys4ddr_image_top.bit]
if {![file exists $bit]} {error "Build failed: inspect synthesis/implementation logs."}
open_run impl_1
report_timing_summary -file [file join $root timing_summary.txt]
report_drc -file [file join $root drc_report.txt]
file copy -force $bit [file join $root nexys4ddr_image_top.bit]
puts "PROGRAM: [file join $root nexys4ddr_image_top.bit]"
puts "Review timing_summary.txt and drc_report.txt before hardware use."
