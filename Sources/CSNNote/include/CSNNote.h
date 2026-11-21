#if !defined(__cplusplus) && __STDC_VERSION__ < 202311L
#include <stdbool.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wc23-extensions"
#include <assert.h>
#define constexpr static const
#include "snnote/snnote.h"
#undef constexpr
#pragma clang diagnostic pop
#else
#include "snnote/snnote.h"
#endif
