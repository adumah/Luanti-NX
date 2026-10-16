#ifndef SWITCH_UTSNAME_STUB_H
#define SWITCH_UTSNAME_STUB_H
#include <string.h>
#ifdef __cplusplus
extern "C" {
#endif
struct utsname {
	char sysname[32];
	char nodename[32];
	char release[32];
	char version[32];
	char machine[32];
};
static inline int uname(struct utsname *u)
{
	strcpy(u->sysname, "Horizon");
	strcpy(u->nodename, "switch");
	strcpy(u->release, "1");
	strcpy(u->version, "1");
	strcpy(u->machine, "aarch64");
	return 0;
}
#ifdef __cplusplus
}
#endif
#endif
