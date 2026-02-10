#include "timestamp_win.h"
#include <windows.h>

uint64_t get_unix_timestamp_ns()
{
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    uint64_t intervals = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    const uint64_t EPOCH_BIAS = 116444736000000000ULL;
    if (intervals < EPOCH_BIAS)
        return 0;
    return (intervals - EPOCH_BIAS) * 100;
}