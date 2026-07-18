#include <errno.h>
#include <libproc.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/proc_info.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

static uint64_t start_id_for_pid(pid_t pid) {
    struct proc_bsdinfo bsd = {0};
    int bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd));
    if (bytes != (int)sizeof(bsd)) {
        return 0;
    }
    return ((uint64_t)bsd.pbi_start_tvsec * 1000000ULL) + (uint64_t)bsd.pbi_start_tvusec;
}

int main(int argc, char *argv[]) {
    if (argc != 5) {
        fprintf(stderr, "Usage: TBWatchdog <controller-pid> <target-pid> <target-start-id> <timeout-seconds>\n");
        return 64;
    }

    pid_t controller_pid = (pid_t)strtol(argv[1], NULL, 10);
    pid_t target_pid = (pid_t)strtol(argv[2], NULL, 10);
    uint64_t target_start_id = strtoull(argv[3], NULL, 10);
    long timeout_seconds = strtol(argv[4], NULL, 10);
    if (controller_pid <= 0 || target_pid <= 0 || target_start_id == 0 || timeout_seconds < 5) {
        return 64;
    }

    time_t started = time(NULL);
    for (;;) {
        if (start_id_for_pid(target_pid) != target_start_id) {
            return 0;
        }

        bool controller_gone = (kill(controller_pid, 0) != 0 && errno == ESRCH);
        bool timed_out = difftime(time(NULL), started) >= (double)timeout_seconds;
        if (controller_gone || timed_out) {
            (void)kill(target_pid, SIGCONT);
            return 0;
        }

        struct timespec interval = {.tv_sec = 1, .tv_nsec = 0};
        nanosleep(&interval, NULL);
    }
}
