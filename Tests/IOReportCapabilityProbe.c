#include "../Sources/ProcessBridge.h"

#include <stdio.h>

int main(void) {
    int32_t capability = tb_ioreport_capability();
    if (capability == 1) {
        puts("IOReportCapabilityProbe: PASS símbolos requeridos detectados; sin suscripción");
        return 0;
    }
    if (capability == 0) {
        puts("IOReportCapabilityProbe: SKIP capacidad no disponible; degradación segura");
        return 0;
    }
    fprintf(stderr, "IOReportCapabilityProbe: FAIL resultado inesperado %d\n", capability);
    return 1;
}
