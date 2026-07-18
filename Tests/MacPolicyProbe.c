#include <errno.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

#ifndef POSIX_SPAWN_PROC_CLAMP_UTILITY
#define POSIX_SPAWN_PROC_CLAMP_UTILITY 1
#endif

extern int posix_spawnattr_set_qos_clamp_np(const posix_spawnattr_t *attr,
                                             uint64_t clamp)
    __attribute__((weak_import));

static int run_taskpolicy(int throughput, int latency) {
    char command[256];
    int length = snprintf(command,
                          sizeof(command),
                          "/usr/bin/taskpolicy -t %d -l %d -p %d >/dev/null 2>&1",
                          throughput,
                          latency,
                          (int)getpid());
    if (length <= 0 || (size_t)length >= sizeof(command)) {
        return -1;
    }
    int status = system(command);
    if (status == -1) {
        return -1;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128;
}

int main(void) {
    int degraded = 0;
    int skipped = 0;
    int failures = 0;
    int background_ok = 0;
    errno = 0;
    if (setpriority(PRIO_DARWIN_PROCESS, (id_t)getpid(), PRIO_DARWIN_BG) == 0) {
        if (setpriority(PRIO_DARWIN_PROCESS, (id_t)getpid(), 0) == 0) {
            background_ok = 1;
            puts("MacPolicyProbe: PASS Darwin Background nativo y restauración");
        } else {
            failures++;
            printf("MacPolicyProbe: FAIL se aplicó Darwin Background, pero la restauración devolvió errno %d.\n", errno);
        }
    } else {
        degraded++;
        printf("MacPolicyProbe: DEGRADED Darwin Background nativo devolvió errno %d.\n", errno);
    }

    int clamp_ok = 0;
    if (posix_spawnattr_set_qos_clamp_np != NULL) {
        posix_spawnattr_t attr;
        int result = posix_spawnattr_init(&attr);
        if (result == 0) {
            result = posix_spawnattr_set_qos_clamp_np(&attr,
                                                      POSIX_SPAWN_PROC_CLAMP_UTILITY);
            posix_spawnattr_destroy(&attr);
        }
        if (result == 0) {
            posix_spawnattr_t launch_attr;
            int launch_attr_initialized = 0;
            result = posix_spawnattr_init(&launch_attr);
            if (result == 0) {
                launch_attr_initialized = 1;
                result = posix_spawnattr_set_qos_clamp_np(&launch_attr,
                                                          POSIX_SPAWN_PROC_CLAMP_UTILITY);
            }
            if (result == 0) {
                result = posix_spawnattr_setpgroup(&launch_attr, 0);
            }
            if (result == 0) {
                result = posix_spawnattr_setflags(&launch_attr,
                                                  POSIX_SPAWN_SETPGROUP);
            }
            pid_t child = 0;
            char *const argv[] = { "/usr/bin/true", NULL };
            if (result == 0) {
                result = posix_spawn(&child,
                                     "/usr/bin/true",
                                     NULL,
                                     &launch_attr,
                                     argv,
                                     environ);
            }
            if (launch_attr_initialized) {
                posix_spawnattr_destroy(&launch_attr);
            }
            if (result == 0) {
                int child_status = 0;
                if (waitpid(child, &child_status, 0) != child ||
                    !WIFEXITED(child_status) || WEXITSTATUS(child_status) != 0) {
                    result = ECHILD;
                }
            }
        }
        if (result == 0) {
            clamp_ok = 1;
            puts("MacPolicyProbe: PASS clamp QoS y lanzamiento de proceso");
        } else {
            degraded++;
            printf("MacPolicyProbe: DEGRADED clamp QoS de lanzamiento devolvió %d.\n", result);
        }
    } else {
        skipped++;
        puts("MacPolicyProbe: SKIP libSystem no publica el clamp QoS de lanzamiento");
    }

    if (access("/usr/bin/taskpolicy", X_OK) != 0) {
        skipped++;
        puts("MacPolicyProbe: SKIP /usr/bin/taskpolicy no está disponible; los tiers son opcionales");
    } else {
        int apply = run_taskpolicy(4, 4);
        int restore = apply == 0 ? run_taskpolicy(-1, -1) : apply;
        if (apply == 0 && restore == 0) {
            puts("MacPolicyProbe: PASS tiers taskpolicy y restauración a no especificado");
        } else if (apply == 0) {
            failures++;
            printf("MacPolicyProbe: FAIL taskpolicy se aplicó, pero no se restauró (código=%d).\n",
                   restore);
        } else {
            degraded++;
            printf("MacPolicyProbe: DEGRADED tiers taskpolicy no disponibles (código=%d).\n",
                   apply);
        }
    }

    printf("MacPolicyProbe: resumen DarwinBG=%s, LaunchQoS=%s, degraded=%d, skipped=%d, failures=%d\n",
           background_ok ? "sí" : "no",
           clamp_ok ? "sí" : "no",
           degraded,
           skipped,
           failures);
    if (failures > 0) {
        return 1;
    }
    return degraded > 0 ? 2 : 0;
}
