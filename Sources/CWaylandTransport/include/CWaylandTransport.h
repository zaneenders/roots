#pragma once
#include <stddef.h>
#include <sys/types.h>

int cwt_prepare_connected(int socket);
ssize_t cwt_receive(int socket, void *bytes, size_t capacity, int *fds, size_t *fd_count);
ssize_t cwt_send(int socket, const void *bytes, size_t count, const int *fds, size_t fd_count);
