set current_dir [file normalize [file dirname [info script]]]
set repo_dir [file dirname $current_dir]
set proj_dir [file join $repo_dir proj]

set input_data_path [file join $repo_dir sim input_data.txt]
if {![file exists $input_data_path]} {
    error "sim/input_data.txt not found at $input_data_path. Run scripts/generate_fifo_data.py first."
}

set xpr_files [glob -nocomplain [file join $proj_dir *.xpr]]
if {[llength $xpr_files] == 0} {
    error "No Vivado project found in $proj_dir. Run create.tcl first."
}
if {[current_project -quiet] eq ""} {
    open_project [lindex $xpr_files 0]
}

# Close a simulation left open by a previous run so the new one can launch
if {[current_sim -quiet] ne ""} {
    close_sim -force
}

# The testbench reads input_data.txt at time 0, so copy it in before launching
set proj_name [get_property NAME [current_project]]
set sim_run_dir [file join $proj_dir "$proj_name.sim" sim_1 behav xsim]
file mkdir $sim_run_dir
file copy -force $input_data_path $sim_run_dir

launch_simulation -simset sim_1 -mode behavioral

run all

set results_path [file join $sim_run_dir test_results.txt]
if {[file exists $results_path]} {
    file copy -force $results_path [file join $repo_dir sim test_results.txt]
}
