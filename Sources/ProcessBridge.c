#include "ProcessBridge.h"

#include <errno.h>
#include <dlfcn.h>
#include <libproc.h>
#include <mach/mach.h>
#include <mach/task_policy.h>
#include <signal.h>
#include <spawn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>

extern char **environ;

#ifndef POSIX_SPAWN_PROC_CLAMP_UTILITY
#define POSIX_SPAWN_PROC_CLAMP_UTILITY 1
#define POSIX_SPAWN_PROC_CLAMP_BACKGROUND 2
#define POSIX_SPAWN_PROC_CLAMP_MAINTENANCE 3
#endif

// La función existe desde macOS 10.10, pero su declaración vive en un header
// privado. weak_import permite compilar con SDKs que no exponen ese header y
// desactivar la función limpiamente si Apple elimina el símbolo.
extern int posix_spawnattr_set_qos_clamp_np(const posix_spawnattr_t *attr,
                                             uint64_t clamp)
    __attribute__((weak_import));

static uint64_t tb_start_id_from_bsd(const struct proc_bsdinfo *bsd) {
    return ((uint64_t)bsd->pbi_start_tvsec * 1000000ULL) + (uint64_t)bsd->pbi_start_tvusec;
}

static void tb_append_argument(char *output, size_t capacity, const char *argument) {
    if (output == NULL || argument == NULL || capacity == 0) {
        return;
    }

    size_t used = strnlen(output, capacity);
    if (used >= capacity - 1) {
        return;
    }

    if (used > 0) {
        output[used++] = ' ';
        output[used] = '\0';
    }

    int needs_quotes = strpbrk(argument, " \t") != NULL;
    if (needs_quotes && used < capacity - 1) {
        output[used++] = '"';
        output[used] = '\0';
    }

    for (const char *cursor = argument; *cursor != '\0' && used < capacity - 1; cursor++) {
        char value = *cursor == '"' ? '\'' : *cursor;
        output[used++] = value;
    }

    if (needs_quotes && used < capacity - 1) {
        output[used++] = '"';
    }
    output[used] = '\0';
}

static void tb_read_process_command(pid_t pid, char *output, size_t capacity) {
    if (output == NULL || capacity == 0) {
        return;
    }
    output[0] = '\0';

    int mib[3] = { CTL_KERN, KERN_PROCARGS2, pid };
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0 || size <= sizeof(int) || size > (4U * 1024U * 1024U)) {
        return;
    }

    char *arguments = malloc(size);
    if (arguments == NULL) {
        return;
    }

    if (sysctl(mib, 3, arguments, &size, NULL, 0) != 0 || size <= sizeof(int)) {
        free(arguments);
        return;
    }

    int argc = 0;
    memcpy(&argc, arguments, sizeof(argc));
    if (argc <= 0 || argc > 4096) {
        free(arguments);
        return;
    }

    char *cursor = arguments + sizeof(argc);
    char *end = arguments + size;

    while (cursor < end && *cursor != '\0') {
        cursor++;
    }
    while (cursor < end && *cursor == '\0') {
        cursor++;
    }

    for (int index = 0; index < argc && cursor < end; index++) {
        size_t remaining = (size_t)(end - cursor);
        size_t length = strnlen(cursor, remaining);
        if (length == remaining) {
            break;
        }
        tb_append_argument(output, capacity, cursor);
        cursor += length + 1;
    }

    // KERN_PROCARGS2 coloca el entorno inmediatamente después de argv. En
    // CrossOver, WINEPREFIX/CX_BOTTLE suelen ser la única forma estable de
    // identificar la botella cuando argv del .exe está temporalmente oculto.
    while (cursor < end) {
        while (cursor < end && *cursor == '\0') {
            cursor++;
        }
        if (cursor >= end) {
            break;
        }
        size_t remaining = (size_t)(end - cursor);
        size_t length = strnlen(cursor, remaining);
        if (length == remaining) {
            break;
        }
        if (strncmp(cursor, "WINEPREFIX=", 11) == 0
                || strncmp(cursor, "CX_BOTTLE=", 10) == 0
                || strncmp(cursor, "CX_BOTTLE_PATH=", 15) == 0
                || strncmp(cursor, "CX_ROOT=", 8) == 0) {
            tb_append_argument(output, capacity, cursor);
        }
        cursor += length + 1;
    }

    free(arguments);
}

static int tb_contains_case_insensitive(const char *haystack, const char *needle) {
    if (haystack == NULL || needle == NULL || *needle == '\0') {
        return 0;
    }
    size_t needle_length = strlen(needle);
    for (const char *cursor = haystack; *cursor != '\0'; cursor++) {
        if (strncasecmp(cursor, needle, needle_length) == 0) {
            return 1;
        }
    }
    return 0;
}

static int tb_has_suffix_case_insensitive(const char *value, const char *suffix) {
    if (value == NULL || suffix == NULL) {
        return 0;
    }
    size_t value_length = strlen(value);
    size_t suffix_length = strlen(suffix);
    if (value_length < suffix_length) {
        return 0;
    }
    return strcasecmp(value + value_length - suffix_length, suffix) == 0;
}

static int tb_should_capture_command(const TBProcessInfo *item) {
    if (item == NULL) {
        return 0;
    }
    return tb_contains_case_insensitive(item->path, "CrossOver")
        || tb_contains_case_insensitive(item->path, "/Bottles/")
        || tb_contains_case_insensitive(item->path, "/wine/")
        || tb_contains_case_insensitive(item->path, "wine64-preloader")
        || tb_contains_case_insensitive(item->path, "wine-preloader")
        || tb_contains_case_insensitive(item->name, "wine")
        || tb_contains_case_insensitive(item->name, "CrossOver")
        || tb_has_suffix_case_insensitive(item->name, ".exe")
        || tb_contains_case_insensitive(item->name, "cxstart");
}

static int tb_has_crossover_ancestor(const TBProcessInfo *items,
                                     int32_t count,
                                     const TBProcessInfo *item) {
    if (items == NULL || item == NULL || count <= 0) {
        return 0;
    }
    int32_t parent_pid = item->parent_pid;
    int depth = 0;
    while (parent_pid > 0 && depth < 32) {
        const TBProcessInfo *parent = NULL;
        for (int32_t index = 0; index < count; index++) {
            if (items[index].pid == parent_pid) {
                parent = &items[index];
                break;
            }
        }
        if (parent == NULL) {
            return 0;
        }
        if (tb_should_capture_command(parent)) {
            return 1;
        }
        parent_pid = parent->parent_pid;
        depth++;
    }
    return 0;
}

int32_t tb_list_user_processes(TBProcessInfo *buffer, int32_t capacity, uint32_t uid) {
    if (buffer == NULL || capacity <= 0) {
        errno = EINVAL;
        return -1;
    }

    int bytes_needed = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes_needed <= 0) {
        return -1;
    }

    // El número de procesos puede crecer entre la consulta de tamaño y la
    // lectura. La versión anterior reservaba margen pero no lo entregaba a
    // proc_listpids, lo que permitía muestras truncadas y listas parpadeantes.
    size_t pid_capacity = (size_t)bytes_needed / sizeof(pid_t) + 512U;
    size_t pid_buffer_bytes = pid_capacity * sizeof(pid_t);
    if (pid_buffer_bytes > (size_t)INT32_MAX) {
        errno = EOVERFLOW;
        return -1;
    }
    pid_t *pids = calloc(pid_capacity, sizeof(pid_t));
    if (pids == NULL) {
        errno = ENOMEM;
        return -1;
    }

    int bytes_read = proc_listpids(PROC_ALL_PIDS, 0, pids, (int)pid_buffer_bytes);
    if (bytes_read <= 0) {
        free(pids);
        return -1;
    }

    int pid_count = bytes_read / (int)sizeof(pid_t);
    int32_t written = 0;

    for (int index = 0; index < pid_count && written < capacity; index++) {
        pid_t pid = pids[index];
        if (pid <= 0) {
            continue;
        }

        struct proc_bsdinfo bsd = {0};
        int bsd_bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd));
        if (bsd_bytes != (int)sizeof(bsd) || bsd.pbi_uid != uid) {
            continue;
        }

        int usage_ok = -1;
        int usage_version = 0;
#if defined(RUSAGE_INFO_V6)
        struct rusage_info_v6 usage_v6 = {0};
        usage_ok = proc_pid_rusage(pid, RUSAGE_INFO_V6, (rusage_info_t *)&usage_v6);
        if (usage_ok == 0) {
            usage_version = 6;
        }
#endif
#if defined(RUSAGE_INFO_V3)
        struct rusage_info_v3 usage_v3 = {0};
        if (usage_ok != 0) {
            usage_ok = proc_pid_rusage(pid, RUSAGE_INFO_V3, (rusage_info_t *)&usage_v3);
            if (usage_ok == 0) {
                usage_version = 3;
            }
        }
#endif
        struct rusage_info_v2 usage_v2 = {0};
        if (usage_ok != 0) {
            usage_ok = proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&usage_v2);
            if (usage_ok == 0) {
                usage_version = 2;
            }
        }

        struct proc_taskinfo task = {0};
        // proc_pid_rusage ya contiene CPU y memoria. PROC_PIDTASKINFO es solo
        // la degradación para sistemas o procesos que rechacen todas las
        // versiones de rusage; evitarlo en la ruta normal elimina una llamada
        // al kernel por proceso y por muestra sin cambiar los datos publicados.
        if (usage_ok != 0) {
            int task_bytes = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, sizeof(task));
            if (task_bytes != (int)sizeof(task)) {
                memset(&task, 0, sizeof(task));
            }
        }

        TBProcessInfo *item = &buffer[written];
        memset(item, 0, sizeof(*item));
        item->pid = (int32_t)pid;
        item->parent_pid = (int32_t)bsd.pbi_ppid;
        item->uid = bsd.pbi_uid;
        item->nice_value = bsd.pbi_nice;
        item->start_id = tb_start_id_from_bsd(&bsd);
#if defined(RUSAGE_INFO_V6)
        if (usage_version == 6) {
            item->rusage_version = 6;
            item->resource_flags = TB_RESOURCE_HAS_QOS_COUNTERS
                | TB_RESOURCE_HAS_DIRECT_ENERGY
                | TB_RESOURCE_HAS_BILLED_ENERGY;
            item->user_time_ns = usage_v6.ri_user_time;
            item->system_time_ns = usage_v6.ri_system_time;
            item->resident_size = usage_v6.ri_resident_size;
            item->energy_nj = usage_v6.ri_energy_nj;
            item->billed_energy_nj = usage_v6.ri_billed_energy;
            item->serviced_energy_nj = usage_v6.ri_serviced_energy;
            item->qos_default_ns = usage_v6.ri_cpu_time_qos_default;
            item->qos_maintenance_ns = usage_v6.ri_cpu_time_qos_maintenance;
            item->qos_background_ns = usage_v6.ri_cpu_time_qos_background;
            item->qos_utility_ns = usage_v6.ri_cpu_time_qos_utility;
            item->qos_legacy_ns = usage_v6.ri_cpu_time_qos_legacy;
            item->qos_user_initiated_ns = usage_v6.ri_cpu_time_qos_user_initiated;
            item->qos_user_interactive_ns = usage_v6.ri_cpu_time_qos_user_interactive;
        } else
#endif
#if defined(RUSAGE_INFO_V3)
        if (usage_version == 3) {
            item->rusage_version = 3;
            item->resource_flags = TB_RESOURCE_HAS_QOS_COUNTERS;
            item->user_time_ns = usage_v3.ri_user_time;
            item->system_time_ns = usage_v3.ri_system_time;
            item->resident_size = usage_v3.ri_resident_size;
            item->qos_default_ns = usage_v3.ri_cpu_time_qos_default;
            item->qos_maintenance_ns = usage_v3.ri_cpu_time_qos_maintenance;
            item->qos_background_ns = usage_v3.ri_cpu_time_qos_background;
            item->qos_utility_ns = usage_v3.ri_cpu_time_qos_utility;
            item->qos_legacy_ns = usage_v3.ri_cpu_time_qos_legacy;
            item->qos_user_initiated_ns = usage_v3.ri_cpu_time_qos_user_initiated;
            item->qos_user_interactive_ns = usage_v3.ri_cpu_time_qos_user_interactive;
        } else
#endif
        if (usage_version == 2) {
            item->rusage_version = 2;
            item->user_time_ns = usage_v2.ri_user_time;
            item->system_time_ns = usage_v2.ri_system_time;
            item->resident_size = usage_v2.ri_resident_size;
        } else if (usage_ok != 0) {
            item->user_time_ns = task.pti_total_user;
            item->system_time_ns = task.pti_total_system;
            item->resident_size = task.pti_resident_size;
        }

        if (proc_name(pid, item->name, sizeof(item->name)) <= 0) {
            if (bsd.pbi_name[0] != '\0') {
                strlcpy(item->name, bsd.pbi_name, sizeof(item->name));
            } else {
                strlcpy(item->name, bsd.pbi_comm, sizeof(item->name));
            }
        }

        if (proc_pidpath(pid, item->path, sizeof(item->path)) <= 0) {
            item->path[0] = '\0';
        }

        written++;
    }

    // Segunda fase: ya conocemos todos los padres. Esto permite capturar argv
    // de hijos cuyo nombre no contiene «wine» ni «.exe», pero que pertenecen
    // inequívocamente a un árbol de CrossOver.
    for (int32_t index = 0; index < written; index++) {
        TBProcessInfo *item = &buffer[index];
        if (tb_should_capture_command(item)
                || tb_has_crossover_ancestor(buffer, written, item)) {
            tb_read_process_command((pid_t)item->pid,
                                    item->command,
                                    sizeof(item->command));
        }
    }

    free(pids);
    return written;
}

int32_t tb_send_signal(int32_t pid, int32_t signal_number) {
    if (pid <= 0) {
        return EINVAL;
    }
    if (kill((pid_t)pid, signal_number) == 0) {
        return 0;
    }
    return errno;
}

int32_t tb_set_nice(int32_t pid, int32_t nice_value) {
    if (pid <= 0 || nice_value < -20 || nice_value > 20) {
        return EINVAL;
    }
    if (setpriority(PRIO_PROCESS, (id_t)pid, nice_value) == 0) {
        return 0;
    }
    return errno;
}


int32_t tb_set_darwin_background(int32_t pid, int32_t enabled) {
    if (pid <= 0 || (enabled != 0 && enabled != 1)) {
        return EINVAL;
    }
    int value = enabled ? PRIO_DARWIN_BG : 0;
    if (setpriority(PRIO_DARWIN_PROCESS, (id_t)pid, value) == 0) {
        return 0;
    }
    return errno;
}

int32_t tb_identity_matches(int32_t pid, uint64_t start_id) {
    if (pid <= 0) {
        return 0;
    }
    struct proc_bsdinfo bsd = {0};
    int bytes = proc_pidinfo((pid_t)pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd));
    if (bytes != (int)sizeof(bsd)) {
        return 0;
    }
    return tb_start_id_from_bsd(&bsd) == start_id ? 1 : 0;
}

static task_latency_qos_t tb_latency_qos_tier(int32_t tier) {
    switch (tier) {
        case -1: return LATENCY_QOS_TIER_UNSPECIFIED;
        case 0: return LATENCY_QOS_TIER_0;
        case 1: return LATENCY_QOS_TIER_1;
        case 2: return LATENCY_QOS_TIER_2;
        case 3: return LATENCY_QOS_TIER_3;
        case 4: return LATENCY_QOS_TIER_4;
        case 5: return LATENCY_QOS_TIER_5;
        default: return (task_latency_qos_t)-1;
    }
}

static task_throughput_qos_t tb_throughput_qos_tier(int32_t tier) {
    switch (tier) {
        case -1: return THROUGHPUT_QOS_TIER_UNSPECIFIED;
        case 0: return THROUGHPUT_QOS_TIER_0;
        case 1: return THROUGHPUT_QOS_TIER_1;
        case 2: return THROUGHPUT_QOS_TIER_2;
        case 3: return THROUGHPUT_QOS_TIER_3;
        case 4: return THROUGHPUT_QOS_TIER_4;
        case 5: return THROUGHPUT_QOS_TIER_5;
        default: return (task_throughput_qos_t)-1;
    }
}

int32_t tb_set_qos_tiers(int32_t pid, int32_t latency_tier, int32_t throughput_tier) {
    if (pid <= 0 || latency_tier < -1 || latency_tier > 5
            || throughput_tier < -1 || throughput_tier > 5) {
        return KERN_INVALID_ARGUMENT;
    }

    task_latency_qos_t latency = tb_latency_qos_tier(latency_tier);
    task_throughput_qos_t throughput = tb_throughput_qos_tier(throughput_tier);
    if (latency == (task_latency_qos_t)-1 || throughput == (task_throughput_qos_t)-1) {
        return KERN_INVALID_ARGUMENT;
    }

    mach_port_t task = MACH_PORT_NULL;
    kern_return_t result = task_name_for_pid(mach_task_self(), (pid_t)pid, &task);
    if (result != KERN_SUCCESS) {
        return result;
    }

    struct task_qos_policy policy = {
        .task_latency_qos_tier = latency,
        .task_throughput_qos_tier = throughput
    };
    result = task_policy_set((task_t)task,
                             TASK_OVERRIDE_QOS_POLICY,
                             (task_policy_t)&policy,
                             TASK_QOS_POLICY_COUNT);
    mach_port_deallocate(mach_task_self(), task);
    return result;
}


int32_t tb_qos_clamp_supported(void) {
    return posix_spawnattr_set_qos_clamp_np != NULL ? 1 : 0;
}

int32_t tb_ioreport_capability(void) {
    static const char *required_symbols[] = {
        "IOReportCopyChannelsInGroup",
        "IOReportCreateSubscription",
        "IOReportCreateSamples",
        "IOReportCreateSamplesDelta"
    };
    void *handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (handle == NULL) {
        return 0;
    }

    int32_t available = 1;
    const size_t symbol_count = sizeof(required_symbols) / sizeof(required_symbols[0]);
    for (size_t index = 0; index < symbol_count; index++) {
        if (dlsym(handle, required_symbols[index]) == NULL) {
            available = 0;
            break;
        }
    }
    dlclose(handle);
    return available;
}

int32_t tb_spawn_with_qos_clamp(const char *executable_path,
                                int32_t clamp,
                                int32_t new_process_group,
                                int32_t *out_pid) {
    if (executable_path == NULL || executable_path[0] == '\0' || out_pid == NULL) {
        return EINVAL;
    }
    if (clamp < POSIX_SPAWN_PROC_CLAMP_UTILITY ||
        clamp > POSIX_SPAWN_PROC_CLAMP_MAINTENANCE) {
        return EINVAL;
    }
    if (posix_spawnattr_set_qos_clamp_np == NULL) {
        return ENOTSUP;
    }
    if (access(executable_path, X_OK) != 0) {
        return errno != 0 ? errno : EACCES;
    }

    posix_spawnattr_t attr;
    posix_spawn_file_actions_t actions;
    int result = posix_spawnattr_init(&attr);
    if (result != 0) {
        return result;
    }
    result = posix_spawn_file_actions_init(&actions);
    if (result != 0) {
        posix_spawnattr_destroy(&attr);
        return result;
    }

    result = posix_spawnattr_set_qos_clamp_np(&attr, (uint64_t)clamp);
    if (result == 0 && new_process_group) {
        result = posix_spawnattr_setpgroup(&attr, 0);
        if (result == 0) {
            result = posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
        }
    }

    if (result == 0) {
        // Una aplicación GUI no debe heredar descriptores interactivos de
        // ThermalBridge. stdin/stdout/stderr se aíslan en /dev/null.
        result = posix_spawn_file_actions_addopen(&actions, STDIN_FILENO,
                                                  "/dev/null", O_RDONLY, 0);
    }
    if (result == 0) {
        result = posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO,
                                                  "/dev/null", O_WRONLY, 0);
    }
    if (result == 0) {
        result = posix_spawn_file_actions_addopen(&actions, STDERR_FILENO,
                                                  "/dev/null", O_WRONLY, 0);
    }

    pid_t child = 0;
    if (result == 0) {
        char *const argv[] = { (char *)executable_path, NULL };
        result = posix_spawn(&child, executable_path, &actions, &attr, argv, environ);
    }

    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attr);
    if (result != 0) {
        return result;
    }
    *out_pid = (int32_t)child;
    return 0;
}

uint32_t tb_current_uid(void) {
    return (uint32_t)geteuid();
}
