// Uncaught C++ exceptions otherwise kill Luanti on Horizon without leaving a
// trace. Write the exception message to crash.txt (and stderr/nxlink) first.
// Not debug.txt: Luanti keeps it open, and Horizon refuses a second handle.
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <typeinfo>

static void switch_terminate()
{
	const char *what = "unknown (not a std::exception)";
	const char *type = "?";
	if (std::exception_ptr ep = std::current_exception()) {
		try {
			std::rethrow_exception(ep);
		} catch (const std::exception &e) {
			what = e.what();
			type = typeid(e).name();
		} catch (...) {
		}
	} else {
		what = "std::terminate() called without an active exception";
	}
	std::fprintf(stderr, "FATAL: uncaught exception [%s]: %s\n", type, what);
	if (FILE *f = std::fopen("sdmc:/switch/luanti/crash.txt", "a")) {
		std::fprintf(f, "FATAL: uncaught exception [%s]: %s\n", type, what);
		std::fclose(f);
	}
	std::abort();
}

static const bool installed = (std::set_terminate(switch_terminate), true);
