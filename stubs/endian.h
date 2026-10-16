#ifndef SWITCH_ENDIAN_STUB_H
#define SWITCH_ENDIAN_STUB_H
#ifndef __LITTLE_ENDIAN
#define __LITTLE_ENDIAN 1234
#endif
#ifndef __BIG_ENDIAN
#define __BIG_ENDIAN 4321
#endif
#ifndef __BYTE_ORDER
#define __BYTE_ORDER __LITTLE_ENDIAN
#endif
#ifndef LITTLE_ENDIAN
#define LITTLE_ENDIAN __LITTLE_ENDIAN
#endif
#ifndef BIG_ENDIAN
#define BIG_ENDIAN __BIG_ENDIAN
#endif
#ifndef BYTE_ORDER
#define BYTE_ORDER __BYTE_ORDER
#endif
#ifndef be16toh
#define be16toh(x) __builtin_bswap16(x)
#define htobe16(x) __builtin_bswap16(x)
#define le16toh(x) (x)
#define htole16(x) (x)
#endif
#ifndef be32toh
#define be32toh(x) __builtin_bswap32(x)
#define htobe32(x) __builtin_bswap32(x)
#define le32toh(x) (x)
#define htole32(x) (x)
#endif
#ifndef be64toh
#define be64toh(x) __builtin_bswap64(x)
#define htobe64(x) __builtin_bswap64(x)
#define le64toh(x) (x)
#define htole64(x) (x)
#endif
#endif
