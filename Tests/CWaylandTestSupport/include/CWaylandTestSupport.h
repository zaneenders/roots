#include <stddef.h>
#include <sys/types.h>
ssize_t cwl_receive(int socket, void *bytes, size_t capacity, int *fds, size_t *fd_count);
ssize_t cwl_send(int socket, const void *bytes, size_t count, const int *fds, size_t fd_count);
