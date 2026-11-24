# Compile the Nangate45 Liberty file into a Synopsys DB library.
set lib_name NangateOpenCellLibrary
set lib_file NangateOpenCellLibrary_typical.lib

read_lib $lib_file
write_lib $lib_name -format db -output NangateOpenCellLibrary_typical.db

exit
