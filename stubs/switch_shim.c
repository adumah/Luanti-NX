/* Link-time shims for POSIX bits missing from devkitA64's newlib on Horizon.
 * Compiled by build.sh and linked into Luanti via stubs/switch.cmake. */
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <strings.h>
#include <sys/types.h>
#include <iconv.h>
#include <spawn.h>
#include <dirent.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/iosupport.h>
#include <switch.h>
#include <sqlite3.h>

/* libnx calls these weak hooks around main(). Sockets are required even for
 * singleplayer (client and built-in server talk over loopback UDP). nxlinkStdio()
 * sends stdout/stderr to `nxlink -s` on the PC; harmless when not launched via nxlink. */
static int nxlink_sock = -1;

/* Horizon has no /dev/null and /tmp (sdmc:/tmp) usually doesn't exist; Luanti then
 * needs a temp file per Lua environment (and temp dirs in the main menu).
 * TMPDIR must start with '/'; it resolves on sdmc:, the default device. */
#define SWITCH_TMPDIR "/switch/luanti/tmp"

static void remove_tree_contents(const char *dir)
{
	DIR *d = opendir(dir);
	struct dirent *e;
	if (!d)
		return;
	while ((e = readdir(d))) {
		char path[PATH_MAX];
		struct stat st;
		if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, ".."))
			continue;
		snprintf(path, sizeof(path), "%s/%s", dir, e->d_name);
		if (stat(path, &st) == 0 && S_ISDIR(st.st_mode)) {
			remove_tree_contents(path);
			rmdir(path);
		} else {
			unlink(path);
		}
	}
	closedir(d);
}

/* "null:" device standing in for /dev/null (build.sh patches s_security.cpp to use
 * "null:/"). A real file can't replace it: Luanti opens it for reading and writing at
 * the same time, which Horizon's filesystem refuses. */
static int null_open(struct _reent *r, void *fs, const char *path, int flags, int mode)
{ (void)r; (void)fs; (void)path; (void)flags; (void)mode; return 0; }
static int null_close(struct _reent *r, void *fd) { (void)r; (void)fd; return 0; }
static ssize_t null_write(struct _reent *r, void *fd, const char *ptr, size_t len)
{ (void)r; (void)fd; (void)ptr; return len; }
static ssize_t null_read(struct _reent *r, void *fd, char *ptr, size_t len)
{ (void)r; (void)fd; (void)ptr; (void)len; return 0; }
static off_t null_seek(struct _reent *r, void *fd, off_t pos, int dir)
{ (void)r; (void)fd; (void)pos; (void)dir; return 0; }
static int null_fstat(struct _reent *r, void *fd, struct stat *st)
{ (void)r; (void)fd; memset(st, 0, sizeof(*st)); st->st_mode = S_IFCHR | 0666; return 0; }
static int null_stat(struct _reent *r, const char *file, struct stat *st)
{ (void)file; return null_fstat(r, NULL, st); }

static const devoptab_t null_devoptab = {
	.name = "null",
	.structSize = sizeof(int),
	.open_r = null_open,
	.close_r = null_close,
	.write_r = null_write,
	.read_r = null_read,
	.seek_r = null_seek,
	.fstat_r = null_fstat,
	.stat_r = null_stat,
};

/* SQLite VFS for Horizon, based on the built-in "unix-none":
 * - "unix" locks with fcntl(F_SETLK), which Horizon's filesystem doesn't support;
 *   "unix-none" is the same VFS without locking (only Luanti opens these files).
 * - Its xFullPathname treats any path not starting with '/' as relative and
 *   prefixes the cwd, mangling "sdmc:/..." into "sdmc:/cwd/sdmc:/...". Paths with
 *   a device prefix are already absolute, so pass them through unchanged.
 * - SQLite reads past EOF on purpose and expects a short read; Horizon fails such
 *   reads, libnx maps the unknown error to EIO, and SQLite reports EIO as
 *   "database disk image is malformed". Clamp reads to the file size instead.
 * - libnx's stat() opens the file to read its size, which Horizon refuses while the
 *   file is open for writing, so SQLite's stat() of its own open database (done
 *   when creating the -journal) fails with SQLITE_IOERR_FSTAT. Treat such a file
 *   as an existing regular file; SQLite only needs the type and mode there. */
static sqlite3_vfs switch_vfs;
static int (*unix_full_pathname)(sqlite3_vfs *, const char *, int, char *);
static int (*unix_open)(sqlite3_vfs *, sqlite3_filename, sqlite3_file *, int, int *);
static const sqlite3_io_methods *unix_io;
static sqlite3_io_methods switch_io;

static int switch_read(sqlite3_file *f, void *buf, int amt, sqlite3_int64 off)
{
	sqlite3_int64 size;
	if (unix_io->xFileSize(f, &size) == SQLITE_OK && off + amt > size) {
		int avail = off < size ? (int)(size - off) : 0;
		if (avail > 0) {
			int rc = unix_io->xRead(f, buf, avail, off);
			if (rc != SQLITE_OK)
				return rc;
		}
		memset((char *)buf + avail, 0, amt - avail);
		return SQLITE_IOERR_SHORT_READ;
	}
	return unix_io->xRead(f, buf, amt, off);
}

static int switch_open(sqlite3_vfs *vfs, sqlite3_filename name, sqlite3_file *f,
		int flags, int *out_flags)
{
	int rc = unix_open(vfs, name, f, flags, out_flags);
	if (rc != SQLITE_OK || !f->pMethods)
		return rc;
	if (!unix_io) {
		unix_io = f->pMethods;
		switch_io = *unix_io;
		switch_io.xRead = switch_read;
	}
	if (f->pMethods == unix_io)
		f->pMethods = &switch_io;
	return rc;
}

static int switch_full_pathname(sqlite3_vfs *vfs, const char *path, int n_out, char *out)
{
	if (strchr(path, ':')) {
		if ((int)strlen(path) >= n_out)
			return SQLITE_CANTOPEN;
		strcpy(out, path);
		return SQLITE_OK;
	}
	return unix_full_pathname(vfs, path, n_out, out);
}

/* SQLite's error log names the failing syscall, errno and path ("disk I/O error"
 * alone doesn't). Separate file: Luanti keeps debug.txt open, and Horizon refuses a
 * second handle to a file that is open for writing. */
static void switch_sqlite_log(void *arg, int code, const char *msg)
{
	FILE *f;
	(void)arg;
	/* Expected on every commit: Horizon can't open a directory to fsync it, and
	 * SQLite ignores that. Don't log it (each line is an SD card write). */
	if ((code & 0xff) == SQLITE_CANTOPEN &&
			(strstr(msg, "openDirectory") || !strncmp(msg, "cannot open file at line", 24)))
		return;
	fprintf(stderr, "SQLite (%d): %s\n", code, msg);
	f = fopen("sdmc:/switch/luanti/sqlite_log.txt", "a");
	if (f) {
		fprintf(f, "SQLite (%d): %s\n", code, msg);
		fclose(f);
	}
}

static int switch_stat(const char *path, struct stat *st)
{
	if (stat(path, st) == 0)
		return 0;
	if (errno == ENOENT || errno == ENOTDIR)
		return -1;
	memset(st, 0, sizeof(*st));
	st->st_mode = S_IFREG | 0644;
	st->st_nlink = 1;
	return 0;
}

static void switch_sqlite_vfs_init(void)
{
	/* Must precede the first SQLite call (sqlite3_vfs_find initializes it). */
	sqlite3_config(SQLITE_CONFIG_LOG, switch_sqlite_log, NULL);

	sqlite3_vfs *base = sqlite3_vfs_find("unix-none");
	if (!base)
		return;
	switch_vfs = *base;
	switch_vfs.pNext = NULL;
	switch_vfs.zName = "switch";
	unix_full_pathname = base->xFullPathname;
	switch_vfs.xFullPathname = switch_full_pathname;
	unix_open = base->xOpen;
	switch_vfs.xOpen = switch_open;
	/* Replaces stat() in SQLite's shared unix syscall table. */
	base->xSetSystemCall(base, "stat", (sqlite3_syscall_ptr)switch_stat);
	sqlite3_vfs_register(&switch_vfs, 1);
}

void userAppInit(void)
{
	AddDevice(&null_devoptab);
	switch_sqlite_vfs_init();

	if (R_SUCCEEDED(socketInitializeDefault()))
		nxlink_sock = nxlinkStdio();

	mkdir("/switch", 0777);
	mkdir("/switch/luanti", 0777);
	mkdir(SWITCH_TMPDIR, 0777);
	/* Temp files can't always be unlinked while open, so clear leftovers. */
	remove_tree_contents(SWITCH_TMPDIR);
	setenv("TMPDIR", SWITCH_TMPDIR, 1);
}

void userAppExit(void)
{
	if (nxlink_sock >= 0)
		close(nxlink_sock);
	socketExit();
}

/* System keyboard for Luanti's text fields (called from the patched
 * GUIModalMenu::preprocessEvent). Blocks until the user is done.
 * type: 0 = single line, 1 = multi-line, 2 = password.
 * Returns 1 and fills `out` if the user confirmed, 0 if cancelled/failed. */
int switch_keyboard_show(const char *initial, int type, char *out, size_t out_size)
{
	SwkbdConfig kbd;
	Result rc;

	if (!out || out_size == 0 || R_FAILED(swkbdCreate(&kbd, 0)))
		return 0;
	if (type == 2)
		swkbdConfigMakePresetPassword(&kbd);
	else
		swkbdConfigMakePresetDefault(&kbd);
	if (type == 1)
		swkbdConfigSetTextDrawType(&kbd, SwkbdTextDrawType_Box);
	if (initial && type != 2)
		swkbdConfigSetInitialText(&kbd, initial);
	rc = swkbdShow(&kbd, out, out_size);
	swkbdClose(&kbd);
	return R_SUCCEEDED(rc) ? 1 : 0;
}

/* SQLite's unix VFS references these in its syscall table. */
int fchown(int fd, uid_t owner, gid_t group) { (void)fd; (void)owner; (void)group; return 0; }
uid_t geteuid(void) { return 0; }

/* Luanti's open_uri() uses this for xdg-open; no processes on Horizon. */
int posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *fa,
		const posix_spawnattr_t *attr, char *const argv[], char *const envp[])
{
	(void)pid; (void)file; (void)fa; (void)attr; (void)argv; (void)envp;
	return ENOSYS;
}

/* Minimal iconv: only UTF-8 <-> UTF-32LE, which is all Luanti's
 * utf8_to_wide/wide_to_utf8 need (wchar_t is 4 bytes on AArch64). */
enum { CONV_UTF8_TO_UTF32 = 1, CONV_UTF32_TO_UTF8 = 2 };

static int is_utf8(const char *s) { return !strcasecmp(s, "UTF-8") || !strcasecmp(s, "UTF8"); }
static int is_utf32(const char *s)
{
	return !strcasecmp(s, "UTF-32LE") || !strcasecmp(s, "UTF-32") ||
		!strcasecmp(s, "WCHAR_T");
}

iconv_t iconv_open(const char *to, const char *from)
{
	intptr_t mode = 0;
	if (is_utf32(to) && is_utf8(from))
		mode = CONV_UTF8_TO_UTF32;
	else if (is_utf8(to) && is_utf32(from))
		mode = CONV_UTF32_TO_UTF8;
	if (!mode) {
		errno = EINVAL;
		return (iconv_t)-1;
	}
	return (iconv_t)mode;
}

int iconv_close(iconv_t cd) { (void)cd; return 0; }

static size_t shim_utf8_to_utf32(char **in, size_t *inleft, char **out, size_t *outleft)
{
	while (*inleft) {
		const unsigned char *s = (const unsigned char *)*in;
		uint32_t cp;
		size_t n;
		if (s[0] < 0x80) { cp = s[0]; n = 1; }
		else if ((s[0] & 0xE0) == 0xC0) { cp = s[0] & 0x1F; n = 2; }
		else if ((s[0] & 0xF0) == 0xE0) { cp = s[0] & 0x0F; n = 3; }
		else if ((s[0] & 0xF8) == 0xF0) { cp = s[0] & 0x07; n = 4; }
		else { errno = EILSEQ; return (size_t)-1; }
		if (n > *inleft) { errno = EINVAL; return (size_t)-1; }
		for (size_t i = 1; i < n; i++) {
			if ((s[i] & 0xC0) != 0x80) { errno = EILSEQ; return (size_t)-1; }
			cp = (cp << 6) | (s[i] & 0x3F);
		}
		if ((n == 2 && cp < 0x80) || (n == 3 && cp < 0x800) ||
				(n == 4 && cp < 0x10000) || cp > 0x10FFFF ||
				(cp >= 0xD800 && cp <= 0xDFFF)) {
			errno = EILSEQ;
			return (size_t)-1;
		}
		if (*outleft < 4) { errno = E2BIG; return (size_t)-1; }
		memcpy(*out, &cp, 4);
		*out += 4; *outleft -= 4;
		*in += n; *inleft -= n;
	}
	return 0;
}

static size_t shim_utf32_to_utf8(char **in, size_t *inleft, char **out, size_t *outleft)
{
	while (*inleft) {
		uint32_t cp;
		unsigned char buf[4];
		size_t n;
		if (*inleft < 4) { errno = EINVAL; return (size_t)-1; }
		memcpy(&cp, *in, 4);
		if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) { errno = EILSEQ; return (size_t)-1; }
		if (cp < 0x80) { buf[0] = cp; n = 1; }
		else if (cp < 0x800) { buf[0] = 0xC0 | (cp >> 6); buf[1] = 0x80 | (cp & 0x3F); n = 2; }
		else if (cp < 0x10000) {
			buf[0] = 0xE0 | (cp >> 12); buf[1] = 0x80 | ((cp >> 6) & 0x3F);
			buf[2] = 0x80 | (cp & 0x3F); n = 3;
		} else {
			buf[0] = 0xF0 | (cp >> 18); buf[1] = 0x80 | ((cp >> 12) & 0x3F);
			buf[2] = 0x80 | ((cp >> 6) & 0x3F); buf[3] = 0x80 | (cp & 0x3F); n = 4;
		}
		if (*outleft < n) { errno = E2BIG; return (size_t)-1; }
		memcpy(*out, buf, n);
		*out += n; *outleft -= n;
		*in += 4; *inleft -= 4;
	}
	return 0;
}

size_t iconv(iconv_t cd, char **__restrict in, size_t *__restrict inleft,
		char **__restrict out, size_t *__restrict outleft)
{
	/* Reset call (no state to reset) */
	if (!in || !*in)
		return 0;
	switch ((intptr_t)cd) {
	case CONV_UTF8_TO_UTF32: return shim_utf8_to_utf32(in, inleft, out, outleft);
	case CONV_UTF32_TO_UTF8: return shim_utf32_to_utf8(in, inleft, out, outleft);
	default: errno = EBADF; return (size_t)-1;
	}
}
