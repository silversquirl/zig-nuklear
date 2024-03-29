// Header with all Nuklear config options defined

#include <stddef.h> // For size_t

// Use Zig implementations of these functions
#define NK_ASSERT zig_nuklear_assert
#define NK_MEMSET zig_nuklear_memset
#define NK_MEMCPY zig_nuklear_memcpy
#define NK_INV_SQRT zig_nuklear_inv_sqrt
#define NK_SIN zig_nuklear_sin
#define NK_COS zig_nuklear_cos
// TODO
// #define NK_STRTOD zig_nuklear_strtod
// #define NK_DTOA zig_nuklear_dtoa

extern void zig_nuklear_assert(_Bool x);
extern void *zig_nuklear_memset(void *s, int c, size_t n);
extern void *zig_nuklear_memcpy(void *dest, const void *src, size_t n);
extern float zig_nuklear_inv_sqrt(float x);
extern float zig_nuklear_sin(float x);
extern float zig_nuklear_cos(float x);

// We never ever ever want to use `vsprintf`, it is horribly unsafe.
// Nuklear should autodetect that we have `vsnprintf` available, but we'll
// pass in an option for it too, just in case.
//
// If the build script hasn't provided the options to tell Nuklear to use stdio,
// it'll use its own impl regardless of whether or not this is
// defined.
#define NK_VSNPRINTF vsnprintf

// Include build config
#include "config.h"

// Include upstream Nuklear
#include "vendor/nuklear.h"
