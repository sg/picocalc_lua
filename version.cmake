# the boot banner and sys.version show this string: a tagged checkout
# reads v0.6.0, later commits v0.6.0-5-g9e11580 and local edits add a +
execute_process(COMMAND git describe --tags --always --dirty=+
	OUTPUT_VARIABLE GIT_DESC ERROR_QUIET)
string(STRIP "${GIT_DESC}" GIT_DESC)

if ("${GIT_DESC}" STREQUAL "")
	set(GIT_DESC "unknown")
endif()

set(VERSION "const char* GIT_DESC=\"${GIT_DESC}\";\n")

# rewriting an unchanged file would relink the firmware on every build
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/version.c)
	file(READ ${CMAKE_CURRENT_SOURCE_DIR}/version.c VERSION_)
else()
	set(VERSION_ "")
endif()

if (NOT "${VERSION}" STREQUAL "${VERSION_}")
	file(WRITE ${CMAKE_CURRENT_SOURCE_DIR}/version.c "${VERSION}")
endif()
