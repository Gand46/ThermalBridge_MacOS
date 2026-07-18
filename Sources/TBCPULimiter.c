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
#include <time.h>
#include <unistd.h>

#ifdef __APPLE__
#include <mach/kern_return.h>
#include <mach/mach_time.h>
#endif

#define TB_MAX_TREE_PIDS 16384
#define TB_MODE_BURST 0
#define TB_MODE_AUDIO_SAFE 1
#define TB_CONTROL_REFRESH_NS 100000000ULL
#define TB_TREE_REFRESH_NS 250000000ULL
#define TB_IDLE_REFRESH_NS 20000000ULL

typedef struct {
    pid_t pid;
    pid_t parent_pid;
    uid_t uid;
} ProcessRecord;

typedef struct {
    long activity_percent;
    long pulse_mode;
} ControlSettings;

static volatile sig_atomic_t keep_running = 1;
static pid_t controlled_root_pid = -1;
static uint64_t controlled_root_start_id = 0;
static uid_t controlled_uid = 0;

#ifdef __APPLE__
static mach_timebase_info_data_t timebase = {0};
#endif

static void stop_handler(int signal_number) {
    (void)signal_number;
    keep_running = 0;
}

static uint64_t monotonic_now_ns(void) {
#ifdef __APPLE__
    if (timebase.denom == 0) {
        (void)mach_timebase_info(&timebase);
    }
    const uint64_t ticks = mach_absolute_time();
    const __uint128_t ns = (__uint128_t)ticks * timebase.numer / timebase.denom;
    return (uint64_t)ns;
#else
    struct timespec now = {0};
    (void)clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000000000ULL + (uint64_t)now.tv_nsec;
#endif
}

static void sleep_until_ns(uint64_t deadline_ns) {
#ifdef __APPLE__
    if (timebase.denom == 0) {
        (void)mach_timebase_info(&timebase);
    }
    const __uint128_t ticks128 = (__uint128_t)deadline_ns * timebase.denom / timebase.numer;
    const uint64_t ticks = (uint64_t)ticks128;
    while (keep_running) {
        kern_return_t result = mach_wait_until(ticks);
        if (result == KERN_SUCCESS) {
            break;
        }
        if (result != KERN_ABORTED) {
            break;
        }
    }
#else
    struct timespec deadline = {
        .tv_sec = (time_t)(deadline_ns / 1000000000ULL),
        .tv_nsec = (long)(deadline_ns % 1000000000ULL)
    };
    while (keep_running && clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &deadline, NULL) == EINTR) {
    }
#endif
}

static void sleep_precise_ns(uint64_t duration_ns, uint64_t *deadline_ns) {
    uint64_t now = monotonic_now_ns();
    if (*deadline_ns < now || now - *deadline_ns > 50000000ULL) {
        *deadline_ns = now;
    }
    *deadline_ns += duration_ns;
    sleep_until_ns(*deadline_ns);
}

static ControlSettings read_control_settings(const char *path, ControlSettings fallback) {
    if (path == NULL || path[0] == '\0') {
        return fallback;
    }

    FILE *file = fopen(path, "r");
    if (file == NULL) {
        return fallback;
    }

    long activity = fallback.activity_percent;
    long mode = fallback.pulse_mode;
    const int matched = fscanf(file, "%ld %ld", &activity, &mode);
    fclose(file);

    if (matched < 1 || activity < 10 || activity > 100) {
        return fallback;
    }
    if (matched < 2) {
        mode = fallback.pulse_mode;
    }
    if (mode != TB_MODE_BURST && mode != TB_MODE_AUDIO_SAFE) {
        mode = fallback.pulse_mode;
    }
    return (ControlSettings){ .activity_percent = activity, .pulse_mode = mode };
}

static uint64_t start_id_for_pid(pid_t pid, uid_t *uid_out) {
    struct proc_bsdinfo bsd = {0};
    int bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd));
    if (bytes != (int)sizeof(bsd)) {
        return 0;
    }
    if (uid_out != NULL) {
        *uid_out = bsd.pbi_uid;
    }
    return ((uint64_t)bsd.pbi_start_tvsec * 1000000ULL) + (uint64_t)bsd.pbi_start_tvusec;
}

static bool root_identity_matches(void) {
    uid_t uid = 0;
    uint64_t start_id = start_id_for_pid(controlled_root_pid, &uid);
    return start_id != 0 && start_id == controlled_root_start_id && uid == controlled_uid;
}

static bool controller_is_gone(pid_t controller_pid) {
    return kill(controller_pid, 0) != 0 && errno == ESRCH;
}

static bool pid_is_in_list(pid_t pid, const pid_t *list, size_t count) {
    for (size_t index = 0; index < count; index++) {
        if (list[index] == pid) {
            return true;
        }
    }
    return false;
}

/// Collects the root process and all currently visible descendants belonging to
/// the same user. CrossOver games often spread work across several child
/// processes, so controlling only the selected PID is not sufficient.
static size_t collect_process_tree(pid_t root_pid, uid_t uid, pid_t *output, size_t capacity) {
    if (root_pid <= 0 || output == NULL || capacity == 0) {
        return 0;
    }

    int bytes_needed = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes_needed <= 0) {
        output[0] = root_pid;
        return 1;
    }

    size_t pid_capacity = (size_t)bytes_needed / sizeof(pid_t) + 64U;
    pid_t *pids = calloc(pid_capacity, sizeof(pid_t));
    ProcessRecord *records = calloc(pid_capacity, sizeof(ProcessRecord));
    if (pids == NULL || records == NULL) {
        free(pids);
        free(records);
        output[0] = root_pid;
        return 1;
    }

    int bytes_read = proc_listpids(PROC_ALL_PIDS, 0, pids, (int)(pid_capacity * sizeof(pid_t)));
    if (bytes_read <= 0) {
        free(pids);
        free(records);
        output[0] = root_pid;
        return 1;
    }

    int pid_count = bytes_read / (int)sizeof(pid_t);
    size_t record_count = 0;
    for (int index = 0; index < pid_count && record_count < pid_capacity; index++) {
        pid_t pid = pids[index];
        if (pid <= 0) {
            continue;
        }
        struct proc_bsdinfo bsd = {0};
        int info_bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd));
        if (info_bytes != (int)sizeof(bsd) || bsd.pbi_uid != uid) {
            continue;
        }
        records[record_count++] = (ProcessRecord){
            .pid = pid,
            .parent_pid = (pid_t)bsd.pbi_ppid,
            .uid = bsd.pbi_uid
        };
    }

    size_t output_count = 0;
    output[output_count++] = root_pid;

    bool changed = true;
    while (changed && output_count < capacity) {
        changed = false;
        for (size_t index = 0; index < record_count && output_count < capacity; index++) {
            pid_t pid = records[index].pid;
            if (pid == root_pid || pid_is_in_list(pid, output, output_count)) {
                continue;
            }
            if (pid_is_in_list(records[index].parent_pid, output, output_count)) {
                output[output_count++] = pid;
                changed = true;
            }
        }
    }

    free(pids);
    free(records);
    return output_count;
}

static void signal_primary(pid_t root_pid, int signal_number) {
    if (root_pid > 0) {
        (void)kill(root_pid, signal_number);
    }
}

static void signal_tree(const pid_t *tree, size_t count, int signal_number) {
    if (tree == NULL) {
        return;
    }

    if (signal_number == SIGSTOP) {
        // Stop descendants first, then the root. This reduces the window in
        // which a child can enqueue more work while the root is already paused.
        for (size_t index = count; index > 0; index--) {
            (void)kill(tree[index - 1], signal_number);
        }
    } else {
        // Resume root first and then its descendants.
        for (size_t index = 0; index < count; index++) {
            (void)kill(tree[index], signal_number);
        }
    }
}

static void resume_controlled_tree(void) {
    if (controlled_root_pid <= 0 || !root_identity_matches()) {
        return;
    }
    pid_t tree[TB_MAX_TREE_PIDS] = {0};
    size_t count = collect_process_tree(controlled_root_pid, controlled_uid, tree, TB_MAX_TREE_PIDS);
    signal_tree(tree, count, SIGCONT);
}

static void audio_safe_timings(long activity_percent, uint64_t *run_ns, uint64_t *stop_ns) {
    long activity = activity_percent;
    if (activity < 25) {
        activity = 25;
    }
    if (activity >= 100) {
        *run_ns = TB_IDLE_REFRESH_NS;
        *stop_ns = 0;
        return;
    }

    // Dos milisegundos mantienen cada silencio muy por debajo del antiguo
    // bloque de 26 ms a 35%, pero reducen la cantidad de SIGSTOP/SIGCONT frente
    // a pulsos de 0,75-1 ms. En modo protegido solo se detiene el host principal.
    const uint64_t stop_us = 2000ULL;
    const uint64_t denominator = (uint64_t)(100 - activity);
    uint64_t run_us = (stop_us * (uint64_t)activity) / denominator;
    if (run_us < 250ULL) {
        run_us = 250ULL;
    }
    if (run_us > 40000ULL) {
        run_us = 40000ULL;
    }
    *run_ns = run_us * 1000ULL;
    *stop_ns = stop_us * 1000ULL;
}

int main(int argc, char *argv[]) {
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
        const long activities[] = {25, 35, 50, 65, 80, 95};
        for (size_t index = 0; index < sizeof(activities) / sizeof(activities[0]); index++) {
            uint64_t run_ns = 0;
            uint64_t stop_ns = 0;
            audio_safe_timings(activities[index], &run_ns, &stop_ns);
            if (run_ns < 250000ULL || run_ns > 40000000ULL ||
                stop_ns == 0 || stop_ns > 2000000ULL) {
                fprintf(stderr, "TBCPULimiter self-test failed at %ld%%\n", activities[index]);
                return 1;
            }
            const uint64_t total_ns = run_ns + stop_ns;
            const uint64_t realized_milli_percent = (run_ns * 100000ULL) / total_ns;
            const uint64_t expected_milli_percent = (uint64_t)activities[index] * 1000ULL;
            const uint64_t error = realized_milli_percent > expected_milli_percent
                ? realized_milli_percent - expected_milli_percent
                : expected_milli_percent - realized_milli_percent;
            if (error > 50ULL) {
                fprintf(stderr, "TBCPULimiter ratio self-test failed at %ld%%\n", activities[index]);
                return 1;
            }
        }
        puts("TBCPULimiter audio-safe self-test: OK");
        return 0;
    }

    if (argc != 8) {
        fprintf(stderr,
                "Usage: TBCPULimiter <controller-pid> <root-pid> <root-start-id> <activity-percent> <cycle-ms> <pulse-mode> <control-file>\n");
        return 64;
    }

    pid_t controller_pid = (pid_t)strtol(argv[1], NULL, 10);
    pid_t root_pid = (pid_t)strtol(argv[2], NULL, 10);
    uint64_t root_start_id = strtoull(argv[3], NULL, 10);
    long activity_percent = strtol(argv[4], NULL, 10);
    long cycle_ms = strtol(argv[5], NULL, 10);
    long pulse_mode = strtol(argv[6], NULL, 10);
    const char *control_file = argv[7];

    uid_t root_uid = 0;
    uint64_t actual_start_id = start_id_for_pid(root_pid, &root_uid);
    if (controller_pid <= 0 || root_pid <= 0 || root_start_id == 0 ||
        actual_start_id != root_start_id || root_uid != geteuid() ||
        activity_percent < 10 || activity_percent > 100 ||
        cycle_ms < 4 || cycle_ms > 500 ||
        (pulse_mode != TB_MODE_BURST && pulse_mode != TB_MODE_AUDIO_SAFE) ||
        control_file == NULL || control_file[0] == '\0') {
        return 64;
    }

    controlled_root_pid = root_pid;
    controlled_root_start_id = root_start_id;
    controlled_uid = root_uid;

    signal(SIGTERM, stop_handler);
    signal(SIGINT, stop_handler);
    signal(SIGHUP, stop_handler);
    atexit(resume_controlled_tree);

    const uint64_t burst_cycle_ns = (uint64_t)cycle_ms * 1000000ULL;
    ControlSettings settings = {
        .activity_percent = activity_percent,
        .pulse_mode = pulse_mode
    };
    pid_t tree[TB_MAX_TREE_PIDS] = {0};
    size_t tree_count = 0;
    uint64_t next_control_refresh_ns = 0;
    uint64_t next_tree_refresh_ns = 0;
    uint64_t deadline_ns = monotonic_now_ns();
    long previous_pulse_mode = -1;

    while (keep_running) {
        if (controller_is_gone(controller_pid) || !root_identity_matches()) {
            break;
        }

        uint64_t now_ns = monotonic_now_ns();
        if (next_control_refresh_ns == 0 || now_ns >= next_control_refresh_ns) {
            settings = read_control_settings(control_file, settings);
            next_control_refresh_ns = now_ns + TB_CONTROL_REFRESH_NS;
        }
        if (tree_count == 0 || next_tree_refresh_ns == 0 || now_ns >= next_tree_refresh_ns) {
            tree_count = collect_process_tree(root_pid, root_uid, tree, TB_MAX_TREE_PIDS);
            next_tree_refresh_ns = now_ns + TB_TREE_REFRESH_NS;
        }
        if (tree_count == 0) {
            break;
        }

        if (settings.pulse_mode != previous_pulse_mode) {
            // Un cambio de modo nunca puede dejar descendientes detenidos por el
            // modo anterior. También reinicia la fase del reloj monotónico.
            signal_tree(tree, tree_count, SIGCONT);
            deadline_ns = monotonic_now_ns();
            previous_pulse_mode = settings.pulse_mode;
        }

        uint64_t run_ns = 0;
        uint64_t stop_ns = 0;
        if (settings.pulse_mode == TB_MODE_AUDIO_SAFE) {
            audio_safe_timings(settings.activity_percent, &run_ns, &stop_ns);

            // No se detiene todo el árbol: los ayudantes separados que mantienen
            // audio, red o servicios de CrossOver pueden seguir atendiendo sus
            // buffers. El proceso raíz sigue incluyendo todos sus propios hilos,
            // por lo que el riesgo no puede eliminarse por completo.
            signal_primary(root_pid, SIGCONT);
            sleep_precise_ns(run_ns > 0 ? run_ns : 250000ULL, &deadline_ns);

            if (!keep_running || controller_is_gone(controller_pid) || !root_identity_matches()) {
                break;
            }

            if (stop_ns > 0) {
                signal_primary(root_pid, SIGSTOP);
                sleep_precise_ns(stop_ns, &deadline_ns);
                signal_primary(root_pid, SIGCONT);
            }
        } else {
            run_ns = (burst_cycle_ns * (uint64_t)settings.activity_percent) / 100ULL;
            stop_ns = burst_cycle_ns > run_ns ? burst_cycle_ns - run_ns : 0;

            signal_tree(tree, tree_count, SIGCONT);
            sleep_precise_ns(run_ns > 0 ? run_ns : 250000ULL, &deadline_ns);

            if (!keep_running || controller_is_gone(controller_pid) || !root_identity_matches()) {
                break;
            }

            if (stop_ns > 0) {
                signal_tree(tree, tree_count, SIGSTOP);
                sleep_precise_ns(stop_ns, &deadline_ns);
                signal_tree(tree, tree_count, SIGCONT);
            }
        }
    }

    resume_controlled_tree();
    return 0;
}
