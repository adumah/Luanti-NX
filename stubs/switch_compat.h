#ifndef SWITCH_COMPAT_H
#define SWITCH_COMPAT_H
#ifdef __cplusplus
#include <cstddef>
#include <pthread.h>
#include <sched.h>
static inline int pthread_getschedparam(pthread_t, int *policy, struct sched_param *param)
{ *policy = 0; param->sched_priority = 0; return 0; }
static inline int pthread_setschedparam(pthread_t, int, const struct sched_param *)
{ return 0; }
static inline int sched_get_priority_min(int) { return 0; }
static inline int sched_get_priority_max(int) { return 0; }
// libnx hardware CSPRNG, used by the patched porting::secure_rand_fill_buf.
// Declared here rather than including <switch.h> (its typedefs/macros clash).
extern "C" void randomGet(void *buf, size_t len);
// System keyboard (stubs/switch_shim.c), used by patches/switch-keyboard.patch.
extern "C" int switch_keyboard_show(const char *initial, int type, char *out, size_t out_size);
#endif
#endif
