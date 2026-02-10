#include "timestamp_win.h"
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>

int main()
{
    // 获取纳秒时间戳
    uint64_t ns_timestamp = get_unix_timestamp_ns();

    // 输出结果
    printf("Windows 高精度 Unix 时间戳获取:\n");
    printf("Total Nanoseconds: %" PRIu64 " ns\n", ns_timestamp);

    // 拆分显示，方便验证
    uint64_t seconds = ns_timestamp / 1000000000ULL;
    uint64_t nanos = ns_timestamp % 1000000000ULL;

    printf("Split: %" PRIu64 " seconds and %" PRIu64 " nanoseconds\n", seconds, nanos);

    return 0;
}