#include <errno.h>
#include <libproc.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define TB_MAX_TREE_PIDS 16384

typedef struct {
    pid_t pid;
    pid_t parent_pid;
} ProcessRecord;

static pid_t target_pid = -1;
static uint64_t target_start_id = 0;
static uid_t target_uid = 0;

static uint64_t start_id_for_pid(pid_t pid, uid_t *uid_out) {
    struct proc_bsdinfo bsd = {0};
    int bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd));
    if (bytes != (int)sizeof(bsd)) {
        return 0;
    }
    if (uid_out != NULL) {
        *uid_out = bsd.pbi_uid;
    }
    return ((uint64_t)bsd.pbi_start_tvsec * 1000000ULL)
        + (uint64_t)bsd.pbi_start_tvusec;
}

static bool pid_is_in_list(pid_t pid, const pid_t *list, size_t count) {
    for (size_t index = 0; index < count; index++) {
        if (list[index] == pid) {
            return true;
        }
    }
    return false;
}

static size_t collect_process_tree(pid_t root, uid_t uid,
                                   pid_t *output, size_t capacity) {
    if (root <= 0 || output == NULL || capacity == 0) {
        return 0;
    }
    output[0] = root;
    size_t output_count = 1;

    int bytes_needed = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes_needed <= 0) {
        return output_count;
    }
    size_t capacity_needed = (size_t)bytes_needed / sizeof(pid_t) + 64U;
    pid_t *pids = calloc(capacity_needed, sizeof(pid_t));
    ProcessRecord *records = calloc(capacity_needed, sizeof(ProcessRecord));
    if (pids == NULL || records == NULL) {
        free(pids);
        free(records);
        return output_count;
    }

    int bytes_read = proc_listpids(PROC_ALL_PIDS, 0, pids,
                                  (int)(capacity_needed * sizeof(pid_t)));
    size_t record_count = 0;
    if (bytes_read > 0) {
        int pid_count = bytes_read / (int)sizeof(pid_t);
        for (int index = 0; index < pid_count && record_count < capacity_needed; index++) {
            struct proc_bsdinfo bsd = {0};
            pid_t pid = pids[index];
            int info_bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0,
                                         &bsd, sizeof(bsd));
            if (pid > 0 && info_bytes == (int)sizeof(bsd) && bsd.pbi_uid == uid) {
                records[record_count++] = (ProcessRecord){
                    .pid = pid,
                    .parent_pid = (pid_t)bsd.pbi_ppid
                };
            }
        }
    }

    bool changed = true;
    while (changed && output_count < capacity) {
        changed = false;
        for (size_t index = 0; index < record_count && output_count < capacity; index++) {
            if (!pid_is_in_list(records[index].pid, output, output_count)
                && pid_is_in_list(records[index].parent_pid, output, output_count)) {
                output[output_count++] = records[index].pid;
                changed = true;
            }
        }
    }
    free(pids);
    free(records);
    return output_count;
}

static bool target_identity_matches(void) {
    uid_t uid = 0;
    uint64_t start_id = start_id_for_pid(target_pid, &uid);
    return start_id != 0 && start_id == target_start_id && uid == target_uid;
}

static void resume_target_tree(void) {
    if (!target_identity_matches()) {
        return;
    }
    pid_t tree[TB_MAX_TREE_PIDS] = {0};
    size_t count = collect_process_tree(target_pid, target_uid,
                                        tree, TB_MAX_TREE_PIDS);
    for (size_t index = 0; index < count; index++) {
        (void)kill(tree[index], SIGCONT);
    }
}

static bool process_is_gone_or_reused(pid_t pid, uint64_t start_id) {
    if (pid <= 0 || start_id == 0) {
        return true;
    }
    if (kill(pid, 0) != 0 && errno == ESRCH) {
        return true;
    }
    return start_id_for_pid(pid, NULL) != start_id;
}

int main(int argc, char *argv[]) {
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
        if (process_is_gone_or_reused(getpid(), start_id_for_pid(getpid(), NULL))) {
            return 1;
        }
        pid_t child = fork();
        if (child < 0) return 2;
        if (child == 0) {
            for (;;) pause();
        }
        struct timespec settle = {.tv_sec = 0, .tv_nsec = 10000000L};
        (void)nanosleep(&settle, NULL);
        target_pid = child;
        target_start_id = start_id_for_pid(child, &target_uid);
        if (target_start_id == 0 || kill(child, SIGSTOP) != 0) {
            (void)kill(child, SIGKILL);
            (void)waitpid(child, NULL, 0);
            return 3;
        }
        resume_target_tree();
        (void)kill(child, SIGTERM);
        for (int attempt = 0; attempt < 20; attempt++) {
            int status = 0;
            if (waitpid(child, &status, WNOHANG) == child) {
                puts("TBLimiterGuardian resume self-test: OK");
                return 0;
            }
            struct timespec interval = {.tv_sec = 0, .tv_nsec = 10000000L};
            (void)nanosleep(&interval, NULL);
        }
        (void)kill(child, SIGCONT);
        (void)kill(child, SIGKILL);
        (void)waitpid(child, NULL, 0);
        return 4;
    }
    if (argc != 5) {
        fprintf(stderr,
                "Usage: TBLimiterGuardian <controller-pid> <limiter-pid> <target-pid> <target-start-id>\n");
        return 64;
    }

    pid_t controller_pid = (pid_t)strtol(argv[1], NULL, 10);
    pid_t limiter_pid = (pid_t)strtol(argv[2], NULL, 10);
    target_pid = (pid_t)strtol(argv[3], NULL, 10);
    target_start_id = strtoull(argv[4], NULL, 10);
    uint64_t limiter_start_id = start_id_for_pid(limiter_pid, NULL);
    uint64_t controller_start_id = start_id_for_pid(controller_pid, NULL);
    uint64_t actual_target_start = start_id_for_pid(target_pid, &target_uid);

    if (controller_pid <= 0 || limiter_pid <= 0 || target_pid <= 0
        || controller_start_id == 0 || limiter_start_id == 0
        || target_start_id == 0 || actual_target_start != target_start_id
        || target_uid != geteuid()) {
        return 64;
    }

    for (;;) {
        if (!target_identity_matches()) {
            return 0;
        }
        if (process_is_gone_or_reused(controller_pid, controller_start_id)
            || process_is_gone_or_reused(limiter_pid, limiter_start_id)) {
            resume_target_tree();
            return 0;
        }
        struct timespec interval = {.tv_sec = 0, .tv_nsec = 5000000L};
        while (nanosleep(&interval, &interval) != 0 && errno == EINTR) {
        }
    }
}
