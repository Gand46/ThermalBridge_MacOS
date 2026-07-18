#include <libproc.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/resource.h>
#include <unistd.h>

int main(void) {
    int result = -1;
    int version = 0;
#if defined(RUSAGE_INFO_V6)
    struct rusage_info_v6 v6 = {0};
    result = proc_pid_rusage(getpid(), RUSAGE_INFO_V6, (rusage_info_t *)&v6);
    if (result == 0) {
        version = 6;
        volatile uint64_t direct_energy = v6.ri_energy_nj;
        volatile uint64_t effective_qos = v6.ri_cpu_time_qos_maintenance;
        (void)direct_energy;
        (void)effective_qos;
    }
#endif
#if defined(RUSAGE_INFO_V3)
    if (result != 0) {
        struct rusage_info_v3 v3 = {0};
        result = proc_pid_rusage(getpid(), RUSAGE_INFO_V3, (rusage_info_t *)&v3);
        if (result == 0) {
            version = 3;
            volatile uint64_t effective_qos = v3.ri_cpu_time_qos_maintenance;
            (void)effective_qos;
        }
    }
#endif
    if (result != 0) {
        struct rusage_info_v2 v2 = {0};
        result = proc_pid_rusage(getpid(), RUSAGE_INFO_V2, (rusage_info_t *)&v2);
        if (result == 0) version = 2;
    }
    if (result != 0 || version == 0) {
        fputs("ProcessResourceProbe: FAIL proc_pid_rusage\n", stderr);
        return 1;
    }
    printf("ProcessResourceProbe: PASS rusage V%d\n", version);
    return 0;
}
