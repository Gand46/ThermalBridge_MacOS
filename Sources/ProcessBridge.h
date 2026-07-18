#ifndef THERMALBRIDGE_PROCESSBRIDGE_H
#define THERMALBRIDGE_PROCESSBRIDGE_H

#include <stdint.h>

#define TB_PROCESS_NAME_MAX 256
#define TB_PROCESS_PATH_MAX 1024
#define TB_PROCESS_COMMAND_MAX 4096

#define TB_RESOURCE_HAS_QOS_COUNTERS      (1U << 0)
#define TB_RESOURCE_HAS_DIRECT_ENERGY     (1U << 1)
#define TB_RESOURCE_HAS_BILLED_ENERGY     (1U << 2)

typedef struct {
    int32_t pid;
    int32_t parent_pid;
    uint32_t uid;
    int32_t nice_value;
    uint64_t start_id;
    uint64_t user_time_ns;
    uint64_t system_time_ns;
    uint64_t resident_size;
    uint32_t rusage_version;
    uint32_t resource_flags;
    uint64_t energy_nj;
    uint64_t billed_energy_nj;
    uint64_t serviced_energy_nj;
    uint64_t qos_default_ns;
    uint64_t qos_maintenance_ns;
    uint64_t qos_background_ns;
    uint64_t qos_utility_ns;
    uint64_t qos_legacy_ns;
    uint64_t qos_user_initiated_ns;
    uint64_t qos_user_interactive_ns;
    char name[TB_PROCESS_NAME_MAX];
    char path[TB_PROCESS_PATH_MAX];
    char command[TB_PROCESS_COMMAND_MAX];
} TBProcessInfo;

/// Returns the number of records written, or -1 on failure.
int32_t tb_list_user_processes(TBProcessInfo *buffer, int32_t capacity, uint32_t uid);

/// Sends a POSIX signal to a process. Returns 0 on success, otherwise errno.
int32_t tb_send_signal(int32_t pid, int32_t signal_number);

/// Applies a nice value. Increasing the numeric nice value is normally allowed
/// for same-user processes; restoring it may require administrator privileges.
/// Returns 0 on success, otherwise errno.
int32_t tb_set_nice(int32_t pid, int32_t nice_value);

/// Returns 1 when the PID still belongs to the same process identity, 0 otherwise.
int32_t tb_identity_matches(int32_t pid, uint64_t start_id);

/// Enables or revokes Darwin Background for an existing same-user process.
/// This is the native equivalent of taskpolicy -b/-B and does not require the
/// /usr/bin/taskpolicy executable. Returns 0 on success, otherwise errno.
int32_t tb_set_darwin_background(int32_t pid, int32_t enabled);

/// Sets task override QoS tiers for an existing process. Pass -1 for the
/// unspecified tier (restore/no override), or 0...5 for a concrete tier.
/// Returns KERN_SUCCESS (0) on success, otherwise a Mach error code.
int32_t tb_set_qos_tiers(int32_t pid, int32_t latency_tier, int32_t throughput_tier);

/// Returns 1 when the launch-time QoS clamp symbol is available in libSystem.
int32_t tb_qos_clamp_supported(void);

/// Returns 1 when the private IOReport sampling symbols required for a future
/// optional sampler are present. This probe does not create a subscription.
int32_t tb_ioreport_capability(void);

/// Launches an executable with a launch-time QoS clamp (1 utility, 2 background,
/// 3 maintenance). When new_process_group is nonzero the child receives its own
/// process group. Returns 0 on success, otherwise a POSIX error code.
int32_t tb_spawn_with_qos_clamp(const char *executable_path,
                                int32_t clamp,
                                int32_t new_process_group,
                                int32_t *out_pid);

/// Returns the current effective UID.
uint32_t tb_current_uid(void);

#endif
