# Injected via CMAKE_PROJECT_luanti_INCLUDE (runs right after project(luanti)).
# Adds the Horizon shim objects to the luanti executable only. Not via
# LDFLAGS/CMAKE_EXE_LINKER_FLAGS: those also reach CMake's configure-time test
# programs (C tests don't link libstdc++ or SQLite) and break them. Not via
# link_libraries(): that also tags EngineCommon and duplicates the objects.
# As sources, the .o files are file dependencies, so editing a shim relinks.
# Deferred arguments are expanded when the call runs, so bake the path in now.
cmake_language(EVAL CODE "
	cmake_language(DEFER DIRECTORY \"${CMAKE_SOURCE_DIR}\" CALL
		target_sources luanti PRIVATE
		\"${CMAKE_CURRENT_LIST_DIR}/switch_shim.o\"
		\"${CMAKE_CURRENT_LIST_DIR}/switch_terminate.o\")
")
