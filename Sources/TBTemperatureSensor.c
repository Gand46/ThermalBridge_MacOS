#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>

#include <errno.h>
#include <dlfcn.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

// Implementación mínima del protocolo AppleSMC usada para enumerar sensores
// térmicos. Basada en la disposición pública empleada por proyectos como macmon.

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCKeyDataVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t key;
    SMCKeyDataVersion version;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

typedef struct {
    char name[5];
    uint32_t key;
    SMCKeyInfoData info;
} TemperatureKey;

typedef struct {
    TemperatureKey *items;
    size_t count;
    size_t capacity;
} TemperatureKeyList;

typedef struct {
    bool valid;
    double maximum;
    double average;
    size_t count;
    char maximumSensor[128];
} TemperatureGroup;

static volatile sig_atomic_t g_running = 1;
static io_connect_t g_connection = IO_OBJECT_NULL;

static const uint32_t kSMCUserClientSelector = 2;
static const uint8_t kSMCReadKey = 5;
static const uint8_t kSMCGetKeyFromIndex = 8;
static const uint8_t kSMCGetKeyInfo = 9;
static const uint32_t kSMCFloatType = 0x666c7420U; // "flt "

// Interfaces IOHID usadas también por monitores Apple Silicon abiertos. Son
// privadas/no documentadas, por lo que el helper continúa funcionando solo con
// SMC si dejan de estar disponibles en una versión futura de macOS.
typedef const void *TBIOHIDEventSystemClientRef;
typedef const void *TBIOHIDServiceClientRef;
typedef const void *TBIOHIDEventRef;
typedef TBIOHIDEventSystemClientRef (*TBHIDCreateFn)(CFAllocatorRef);
typedef void (*TBHIDSetMatchingFn)(TBIOHIDEventSystemClientRef, CFDictionaryRef);
typedef CFArrayRef (*TBHIDCopyServicesFn)(TBIOHIDEventSystemClientRef);
typedef CFTypeRef (*TBHIDCopyPropertyFn)(TBIOHIDServiceClientRef, CFStringRef);
typedef TBIOHIDEventRef (*TBHIDCopyEventFn)(TBIOHIDServiceClientRef, int64_t, int32_t, int64_t);
typedef double (*TBHIDGetFloatValueFn)(TBIOHIDEventRef, int64_t);

typedef struct {
    TBHIDCreateFn create;
    TBHIDSetMatchingFn setMatching;
    TBHIDCopyServicesFn copyServices;
    TBHIDCopyPropertyFn copyProperty;
    TBHIDCopyEventFn copyEvent;
    TBHIDGetFloatValueFn getFloatValue;
} TBIOHIDAPI;

static TBIOHIDAPI g_hid_api = {0};
static void *g_hid_handle = NULL;
static TBIOHIDEventSystemClientRef g_hid_client = NULL;
static bool g_hid_initialization_attempted = false;

static const int32_t kTBHIDTemperatureEventType = 15;

static void load_hid_symbol(void *destination, const char *name) {
    *(void **)destination = dlsym(g_hid_handle, name);
}

static bool initialize_hid(void) {
    if (g_hid_initialization_attempted) {
        return g_hid_client != NULL;
    }
    g_hid_initialization_attempted = true;
    g_hid_handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",
                          RTLD_LAZY | RTLD_LOCAL);
    if (g_hid_handle == NULL) {
        fputs("IOHID no disponible; se mantiene la ruta SMC\n", stderr);
        return false;
    }
    load_hid_symbol(&g_hid_api.create, "IOHIDEventSystemClientCreate");
    load_hid_symbol(&g_hid_api.setMatching, "IOHIDEventSystemClientSetMatching");
    load_hid_symbol(&g_hid_api.copyServices, "IOHIDEventSystemClientCopyServices");
    load_hid_symbol(&g_hid_api.copyProperty, "IOHIDServiceClientCopyProperty");
    load_hid_symbol(&g_hid_api.copyEvent, "IOHIDServiceClientCopyEvent");
    load_hid_symbol(&g_hid_api.getFloatValue, "IOHIDEventGetFloatValue");
    TBHIDCreateFn create_client = g_hid_api.create;
    TBHIDSetMatchingFn set_matching = g_hid_api.setMatching;
    if (create_client == NULL || set_matching == NULL
        || g_hid_api.copyServices == NULL || g_hid_api.copyProperty == NULL
        || g_hid_api.copyEvent == NULL || g_hid_api.getFloatValue == NULL) {
        fputs("IOHID incompleto; se mantiene la ruta SMC\n", stderr);
        dlclose(g_hid_handle);
        g_hid_handle = NULL;
        memset(&g_hid_api, 0, sizeof(g_hid_api));
        return false;
    }

    int32_t usage_page = 0xff00;
    int32_t usage = 0x0005;
    CFNumberRef page_number = CFNumberCreate(kCFAllocatorDefault,
                                             kCFNumberSInt32Type, &usage_page);
    CFNumberRef usage_number = CFNumberCreate(kCFAllocatorDefault,
                                              kCFNumberSInt32Type, &usage);
    if (page_number == NULL || usage_number == NULL) {
        if (page_number != NULL) CFRelease(page_number);
        if (usage_number != NULL) CFRelease(usage_number);
        return false;
    }
    const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    const void *values[] = { page_number, usage_number };
    CFDictionaryRef matching = CFDictionaryCreate(kCFAllocatorDefault,
                                                  keys, values, 2,
                                                  &kCFTypeDictionaryKeyCallBacks,
                                                  &kCFTypeDictionaryValueCallBacks);
    CFRelease(page_number);
    CFRelease(usage_number);
    if (matching == NULL) return false;

    g_hid_client = create_client(kCFAllocatorDefault);
    if (g_hid_client != NULL) {
        set_matching(g_hid_client, matching);
    }
    CFRelease(matching);
    return g_hid_client != NULL;
}

static void close_hid(void) {
    if (g_hid_client != NULL) {
        CFRelease(g_hid_client);
        g_hid_client = NULL;
    }
    if (g_hid_handle != NULL) {
        dlclose(g_hid_handle);
        g_hid_handle = NULL;
    }
    memset(&g_hid_api, 0, sizeof(g_hid_api));
}

static void handle_signal(int signal_number) {
    (void)signal_number;
    g_running = 0;
}

static uint32_t key_from_name(const char name[4]) {
    return ((uint32_t)(uint8_t)name[0] << 24)
         | ((uint32_t)(uint8_t)name[1] << 16)
         | ((uint32_t)(uint8_t)name[2] << 8)
         | ((uint32_t)(uint8_t)name[3]);
}

static void name_from_key(uint32_t key, char output[5]) {
    output[0] = (char)((key >> 24) & 0xff);
    output[1] = (char)((key >> 16) & 0xff);
    output[2] = (char)((key >> 8) & 0xff);
    output[3] = (char)(key & 0xff);
    output[4] = '\0';
}

static bool is_valid_temperature(double value) {
    return value > 0.0 && value <= 150.0;
}

static bool key_equals(const char name[5], const char expected[5]) {
    return strncmp(name, expected, 4) == 0;
}

// Clasificación alineada con el helper MacThermal: Tp/Te/Ts son CPU y
// la familia TC contiene sensores CPU legado/agregados como TCMb. Se excluyen
// primero las excepciones TC conocidas como GPU para no mezclarlas con CPU.
static bool is_gpu_temperature_key(const char name[5]) {
    if (name[0] != 'T') return false;
    return name[1] == 'g' || name[1] == 'G'
        || key_equals(name, "TCGC")
        || key_equals(name, "TGDD");
}

static bool is_cpu_temperature_key(const char name[5]) {
    if (name[0] != 'T' || is_gpu_temperature_key(name)) return false;
    return name[1] == 'p' || name[1] == 'e' || name[1] == 's'
        || name[1] == 'C';
}

static kern_return_t smc_call(const SMCKeyData *input, SMCKeyData *output) {
    size_t output_size = sizeof(*output);
    memset(output, 0, sizeof(*output));
    kern_return_t result = IOConnectCallStructMethod(
        g_connection,
        kSMCUserClientSelector,
        input,
        sizeof(*input),
        output,
        &output_size
    );
    if (result != KERN_SUCCESS) {
        return result;
    }
    if (output->result != 0) {
        return kIOReturnError;
    }
    return KERN_SUCCESS;
}

static bool smc_open(void) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    CFMutableDictionaryRef matching = IOServiceMatching("AppleSMC");
    if (matching == NULL) {
        return false;
    }
    kern_return_t result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (result != KERN_SUCCESS) {
        return false;
    }

    io_service_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        io_name_t name = {0};
        if (IORegistryEntryGetName(service, name) == KERN_SUCCESS
            && strcmp(name, "AppleSMCKeysEndpoint") == 0) {
            result = IOServiceOpen(service, mach_task_self(), 0, &g_connection);
            IOObjectRelease(service);
            if (result == KERN_SUCCESS) {
                break;
            }
        } else {
            IOObjectRelease(service);
        }
    }
    IOObjectRelease(iterator);
    return g_connection != IO_OBJECT_NULL;
}

static void smc_close(void) {
    if (g_connection != IO_OBJECT_NULL) {
        IOServiceClose(g_connection);
        g_connection = IO_OBJECT_NULL;
    }
}

static bool read_key_info(uint32_t key, SMCKeyInfoData *info) {
    SMCKeyData input = {0};
    SMCKeyData output = {0};
    input.key = key;
    input.data8 = kSMCGetKeyInfo;
    if (smc_call(&input, &output) != KERN_SUCCESS) {
        return false;
    }
    *info = output.keyInfo;
    return true;
}

static bool read_key(uint32_t key, const SMCKeyInfoData *info, uint8_t bytes[32]) {
    SMCKeyData input = {0};
    SMCKeyData output = {0};
    input.key = key;
    input.data8 = kSMCReadKey;
    input.keyInfo = *info;
    if (smc_call(&input, &output) != KERN_SUCCESS) {
        return false;
    }
    memcpy(bytes, output.bytes, sizeof(output.bytes));
    return true;
}

static bool read_float_key(const TemperatureKey *sensor, double *value) {
    if (sensor->info.dataSize != 4 || sensor->info.dataType != kSMCFloatType) {
        return false;
    }
    uint8_t bytes[32] = {0};
    if (!read_key(sensor->key, &sensor->info, bytes)) {
        return false;
    }
    float result = 0.0f;
    memcpy(&result, bytes, sizeof(result));
    if (!is_valid_temperature((double)result)) {
        return false;
    }
    *value = (double)result;
    return true;
}

static bool read_key_count(uint32_t *count) {
    const char key_name[4] = {'#', 'K', 'E', 'Y'};
    uint32_t key = key_from_name(key_name);
    SMCKeyInfoData info = {0};
    if (!read_key_info(key, &info) || info.dataSize < 4) {
        return false;
    }
    uint8_t bytes[32] = {0};
    if (!read_key(key, &info, bytes)) {
        return false;
    }
    *count = ((uint32_t)bytes[0] << 24)
           | ((uint32_t)bytes[1] << 16)
           | ((uint32_t)bytes[2] << 8)
           | ((uint32_t)bytes[3]);
    return *count > 0;
}

static bool read_key_by_index(uint32_t index, uint32_t *key) {
    SMCKeyData input = {0};
    SMCKeyData output = {0};
    input.data8 = kSMCGetKeyFromIndex;
    input.data32 = index;
    if (smc_call(&input, &output) != KERN_SUCCESS) {
        return false;
    }
    *key = output.key;
    return true;
}

static bool append_key(TemperatureKeyList *list, const TemperatureKey *key) {
    if (list->count == list->capacity) {
        size_t next_capacity = list->capacity == 0 ? 16 : list->capacity * 2;
        TemperatureKey *next_items = realloc(list->items, next_capacity * sizeof(*next_items));
        if (next_items == NULL) {
            return false;
        }
        list->items = next_items;
        list->capacity = next_capacity;
    }
    list->items[list->count++] = *key;
    return true;
}

static bool discover_temperature_keys(TemperatureKeyList *cpu, TemperatureKeyList *gpu) {
    uint32_t count = 0;
    if (!read_key_count(&count)) {
        return false;
    }

    for (uint32_t index = 0; index < count; ++index) {
        uint32_t key = 0;
        if (!read_key_by_index(index, &key)) {
            continue;
        }
        char name[5];
        name_from_key(key, name);
        bool cpu_key = is_cpu_temperature_key(name);
        bool gpu_key = is_gpu_temperature_key(name);
        if (!cpu_key && !gpu_key) {
            continue;
        }

        SMCKeyInfoData info = {0};
        if (!read_key_info(key, &info)
            || info.dataSize != 4
            || info.dataType != kSMCFloatType) {
            continue;
        }

        TemperatureKey sensor = {0};
        memcpy(sensor.name, name, sizeof(sensor.name));
        sensor.key = key;
        sensor.info = info;

        double initial_value = 0.0;
        if (!read_float_key(&sensor, &initial_value)) {
            continue;
        }
        if (!(cpu_key ? append_key(cpu, &sensor) : append_key(gpu, &sensor))) {
            return false;
        }
    }
    return cpu->count > 0 || gpu->count > 0;
}

static TemperatureGroup sample_group(const TemperatureKeyList *list) {
    TemperatureGroup group = {0};
    double sum = 0.0;
    for (size_t index = 0; index < list->count; ++index) {
        double value = 0.0;
        if (!read_float_key(&list->items[index], &value)) {
            continue;
        }
        if (!group.valid || value > group.maximum) {
            group.maximum = value;
            strlcpy(group.maximumSensor, list->items[index].name, sizeof(group.maximumSensor));
        }
        group.valid = true;
        group.count += 1;
        sum += value;
    }
    if (group.count > 0) {
        group.average = sum / (double)group.count;
    }
    return group;
}

static bool string_has_prefix(const char *value, const char *prefix) {
    if (value == NULL || prefix == NULL) return false;
    return strncmp(value, prefix, strlen(prefix)) == 0;
}

static bool is_cpu_hid_sensor_name(const char *product) {
    return string_has_prefix(product, "pACC MTR Temp Sensor")
        || string_has_prefix(product, "eACC MTR Temp Sensor")
        || string_has_prefix(product, "mACC MTR Temp Sensor");
}

static bool is_gpu_hid_sensor_name(const char *product) {
    return string_has_prefix(product, "GPU MTR Temp Sensor");
}

static void add_group_reading(TemperatureGroup *group,
                              const char *sensor_name,
                              double value) {
    if (group == NULL || !is_valid_temperature(value)) return;
    double previous_sum = group->average * (double)group->count;
    if (!group->valid || value > group->maximum) {
        group->maximum = value;
        strlcpy(group->maximumSensor,
                sensor_name != NULL ? sensor_name : "HID",
                sizeof(group->maximumSensor));
    }
    group->valid = true;
    group->count += 1;
    group->average = (previous_sum + value) / (double)group->count;
}

static void sample_hid_groups(TemperatureGroup *cpu,
                              TemperatureGroup *gpu,
                              bool print_list) {
    if (!initialize_hid()) return;
    CFArrayRef services = g_hid_api.copyServices(g_hid_client);
    if (services == NULL) return;

    CFIndex service_count = CFArrayGetCount(services);
    for (CFIndex index = 0; index < service_count; ++index) {
        TBIOHIDServiceClientRef service = CFArrayGetValueAtIndex(services, index);
        if (service == NULL) continue;

        CFTypeRef product_value = g_hid_api.copyProperty(service, CFSTR("Product"));
        if (product_value == NULL || CFGetTypeID(product_value) != CFStringGetTypeID()) {
            if (product_value != NULL) CFRelease(product_value);
            continue;
        }
        char product[128] = {0};
        bool converted = CFStringGetCString((CFStringRef)product_value,
                                            product,
                                            sizeof(product),
                                            kCFStringEncodingUTF8);
        CFRelease(product_value);
        if (!converted) continue;

        bool is_cpu = is_cpu_hid_sensor_name(product);
        bool is_gpu = is_gpu_hid_sensor_name(product);
        if (!is_cpu && !is_gpu) continue;

        TBIOHIDEventRef event = g_hid_api.copyEvent(
            service,
            kTBHIDTemperatureEventType,
            0,
            0
        );
        if (event == NULL) continue;
        double value = g_hid_api.getFloatValue(
            event,
            kTBHIDTemperatureEventType << 16
        );
        CFRelease(event);
        if (!is_valid_temperature(value)) continue;

        if (is_cpu) {
            add_group_reading(cpu, product, value);
            if (print_list) printf("CPU HID:%s %.3f\n", product, value);
        } else {
            add_group_reading(gpu, product, value);
            if (print_list) printf("GPU HID:%s %.3f\n", product, value);
        }
    }

    CFRelease(services);
}

static void print_json_number_or_null(bool valid, double value) {
    if (valid) {
        printf("%.3f", value);
    } else {
        fputs("null", stdout);
    }
}

static void print_json_string_or_null(bool valid, const char *value) {
    if (valid && value != NULL && value[0] != '\0') {
        printf("\"%s\"", value);
    } else {
        fputs("null", stdout);
    }
}

static void print_sample(const TemperatureGroup *cpu, const TemperatureGroup *gpu) {
    struct timeval now = {0};
    gettimeofday(&now, NULL);
    double timestamp = (double)now.tv_sec + ((double)now.tv_usec / 1000000.0);

    printf("{\"timestamp_epoch\":%.6f,", timestamp);
    fputs("\"cpu_temp_max\":", stdout);
    print_json_number_or_null(cpu->valid, cpu->maximum);
    fputs(",\"gpu_temp_max\":", stdout);
    print_json_number_or_null(gpu->valid, gpu->maximum);
    fputs(",\"cpu_temp_avg\":", stdout);
    print_json_number_or_null(cpu->valid, cpu->average);
    fputs(",\"gpu_temp_avg\":", stdout);
    print_json_number_or_null(gpu->valid, gpu->average);
    fputs(",\"cpu_max_sensor\":", stdout);
    print_json_string_or_null(cpu->valid, cpu->maximumSensor);
    fputs(",\"gpu_max_sensor\":", stdout);
    print_json_string_or_null(gpu->valid, gpu->maximumSensor);
    printf(",\"cpu_sensor_count\":%zu,\"gpu_sensor_count\":%zu,\"iohid_available\":%s}\n",
           cpu->count, gpu->count, g_hid_client != NULL ? "true" : "false");
    fflush(stdout);
}

static unsigned parse_interval(int argc, char **argv) {
    unsigned interval = 1000;
    for (int index = 1; index + 1 < argc; ++index) {
        if (strcmp(argv[index], "--interval") == 0 || strcmp(argv[index], "-i") == 0) {
            char *end = NULL;
            errno = 0;
            unsigned long parsed = strtoul(argv[index + 1], &end, 10);
            if (errno == 0 && end != argv[index + 1] && *end == '\0') {
                if (parsed < 250) parsed = 250;
                if (parsed > 10000) parsed = 10000;
                interval = (unsigned)parsed;
            }
            break;
        }
    }
    return interval;
}

static unsigned parse_samples(int argc, char **argv) {
    unsigned samples = 0; // 0 = ejecución indefinida
    for (int index = 1; index + 1 < argc; ++index) {
        if (strcmp(argv[index], "--samples") == 0 || strcmp(argv[index], "-s") == 0) {
            char *end = NULL;
            errno = 0;
            unsigned long parsed = strtoul(argv[index + 1], &end, 10);
            if (errno == 0 && end != argv[index + 1] && *end == '\0') {
                if (parsed > 100000) parsed = 100000;
                samples = (unsigned)parsed;
            }
            break;
        }
    }
    return samples;
}

static bool has_argument(int argc, char **argv, const char *argument) {
    for (int index = 1; index < argc; ++index) {
        if (strcmp(argv[index], argument) == 0) return true;
    }
    return false;
}

static int run_classification_self_test(void) {
    const char *cpu_keys[] = {"TCMb", "Tp00", "Te04", "Ts0P"};
    const char *gpu_keys[] = {"Tg0U", "TG0D", "TCGC", "TGDD"};
    const char *other_keys[] = {"TB0T", "TH0x", "TAOL", "TCGC"};

    for (size_t index = 0; index < sizeof(cpu_keys) / sizeof(cpu_keys[0]); ++index) {
        if (!is_cpu_temperature_key(cpu_keys[index])) {
            fprintf(stderr, "self-test: %s no fue clasificado como CPU\n", cpu_keys[index]);
            return 10;
        }
    }
    for (size_t index = 0; index < sizeof(gpu_keys) / sizeof(gpu_keys[0]); ++index) {
        if (!is_gpu_temperature_key(gpu_keys[index])) {
            fprintf(stderr, "self-test: %s no fue clasificado como GPU\n", gpu_keys[index]);
            return 11;
        }
    }
    for (size_t index = 0; index < sizeof(other_keys) / sizeof(other_keys[0]); ++index) {
        if (strcmp(other_keys[index], "TCGC") == 0) {
            if (is_cpu_temperature_key(other_keys[index])) {
                fputs("self-test: TCGC fue mezclado incorrectamente con CPU\n", stderr);
                return 12;
            }
        } else if (is_cpu_temperature_key(other_keys[index])
                   || is_gpu_temperature_key(other_keys[index])) {
            fprintf(stderr, "self-test: %s no debía entrar en CPU/GPU\n", other_keys[index]);
            return 13;
        }
    }
    if (!is_cpu_hid_sensor_name("pACC MTR Temp Sensor 0")
            || !is_cpu_hid_sensor_name("eACC MTR Temp Sensor 1")
            || !is_cpu_hid_sensor_name("mACC MTR Temp Sensor 0")
            || !is_gpu_hid_sensor_name("GPU MTR Temp Sensor 0")
            || is_cpu_hid_sensor_name("GPU MTR Temp Sensor 0")) {
        fputs("self-test: clasificación IOHID incompatible con MacThermal\n", stderr);
        return 14;
    }
    puts("TBTemperatureSensor classification self-test: OK (TCMb=CPU, TCGC=GPU, ACC/HID=OK)");
    return 0;
}

static void print_sensor_list(const TemperatureKeyList *cpu,
                              const TemperatureKeyList *gpu) {
    for (size_t index = 0; index < cpu->count; ++index) {
        double value = 0.0;
        if (read_float_key(&cpu->items[index], &value)) {
            printf("CPU %s %.3f\n", cpu->items[index].name, value);
        }
    }
    for (size_t index = 0; index < gpu->count; ++index) {
        double value = 0.0;
        if (read_float_key(&gpu->items[index], &value)) {
            printf("GPU %s %.3f\n", gpu->items[index].name, value);
        }
    }
    TemperatureGroup hid_cpu = {0};
    TemperatureGroup hid_gpu = {0};
    sample_hid_groups(&hid_cpu, &hid_gpu, true);
}

int main(int argc, char **argv) {
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    signal(SIGHUP, handle_signal);

    if (has_argument(argc, argv, "--self-test")) {
        return run_classification_self_test();
    }

    if (sizeof(SMCKeyData) != 80) {
        fprintf(stderr, "disposición SMC inesperada: %zu bytes\n", sizeof(SMCKeyData));
        return 2;
    }
    bool smc_available = smc_open();
    TemperatureKeyList cpu = {0};
    TemperatureKeyList gpu = {0};
    bool smc_found = smc_available && discover_temperature_keys(&cpu, &gpu);

    // M1 y determinadas versiones de macOS pueden publicar la malla térmica
    // principalmente por IOHID. No se exige AppleSMC si IOHID entrega CPU/GPU.
    TemperatureGroup hid_probe_cpu = {0};
    TemperatureGroup hid_probe_gpu = {0};
    sample_hid_groups(&hid_probe_cpu, &hid_probe_gpu, false);
    if (!smc_found && !hid_probe_cpu.valid && !hid_probe_gpu.valid) {
        fputs("no se encontraron sensores térmicos CPU/GPU por SMC ni IOHID\n", stderr);
        close_hid();
        smc_close();
        free(cpu.items);
        free(gpu.items);
        return 4;
    }

    fprintf(stderr,
            "sensores detectados: SMC CPU=%zu GPU=%zu; IOHID CPU=%zu GPU=%zu\n",
            cpu.count,
            gpu.count,
            hid_probe_cpu.count,
            hid_probe_gpu.count);
    if (has_argument(argc, argv, "--list-sensors")) {
        print_sensor_list(&cpu, &gpu);
        free(cpu.items);
        free(gpu.items);
        close_hid();
        smc_close();
        return 0;
    }
    unsigned interval = parse_interval(argc, argv);
    unsigned samples = parse_samples(argc, argv);
    unsigned emitted = 0;
    while (g_running) {
        TemperatureGroup cpu_group = sample_group(&cpu);
        TemperatureGroup gpu_group = sample_group(&gpu);
        sample_hid_groups(&cpu_group, &gpu_group, false);
        print_sample(&cpu_group, &gpu_group);
        emitted += 1;
        if ((samples > 0 && emitted >= samples) || !g_running) break;
        struct timeval delay = {
            .tv_sec = (time_t)(interval / 1000U),
            .tv_usec = (suseconds_t)((interval % 1000U) * 1000U)
        };
        (void)select(0, NULL, NULL, NULL, &delay);
    }

    free(cpu.items);
    free(gpu.items);
    close_hid();
    smc_close();
    return 0;
}
