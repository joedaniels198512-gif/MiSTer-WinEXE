#ifndef WINEXE_H
#define WINEXE_H

#include <stdint.h>

void winexe_init();
void winexe_poll();
void winexe_status_event(const char *opt, uint32_t value);

#endif
