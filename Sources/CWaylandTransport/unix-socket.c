#define _GNU_SOURCE
#include "CWaylandTransport.h"
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

int cwt_prepare_connected(int socket) {
    struct sockaddr_storage address;
    socklen_t length = sizeof(address);
    int type;
    socklen_t type_length = sizeof(type);
    if (getpeername(socket, (struct sockaddr *)&address, &length) < 0 ||
        address.ss_family != AF_UNIX ||
        getsockopt(socket, SOL_SOCKET, SO_TYPE, &type, &type_length) < 0 || type != SOCK_STREAM) {
        errno = EINVAL;
        return -1;
    }
    int flags = fcntl(socket, F_GETFL);
    int descriptor_flags = fcntl(socket, F_GETFD);
    if (flags < 0 || descriptor_flags < 0 ||
        fcntl(socket, F_SETFL, flags | O_NONBLOCK) < 0 ||
        fcntl(socket, F_SETFD, descriptor_flags | FD_CLOEXEC) < 0) return -1;
    return 0;
}

ssize_t cwt_receive(int socket, void *bytes, size_t capacity, int *fds, size_t *fd_count) {
    union { struct cmsghdr alignment; char bytes[CMSG_SPACE(256 * sizeof(int))]; } control;
    struct iovec vector = { .iov_base = bytes, .iov_len = capacity };
    struct msghdr message = { .msg_iov = &vector, .msg_iovlen = 1,
        .msg_control = control.bytes, .msg_controllen = sizeof(control.bytes) };
    size_t limit = *fd_count;
    *fd_count = 0;
    ssize_t count = recvmsg(socket, &message, MSG_DONTWAIT | MSG_CMSG_CLOEXEC);
    if (count < 0) return count;
    int invalid = message.msg_flags & MSG_CTRUNC;
    for (struct cmsghdr *header = CMSG_FIRSTHDR(&message); header; header = CMSG_NXTHDR(&message, header)) {
        if (header->cmsg_level != SOL_SOCKET || header->cmsg_type != SCM_RIGHTS) continue;
        size_t n = (header->cmsg_len - CMSG_LEN(0)) / sizeof(int);
        int *values = (int *)CMSG_DATA(header);
        for (size_t i = 0; i < n; ++i) {
            if (*fd_count < limit) fds[(*fd_count)++] = values[i];
            else { close(values[i]); invalid = 1; }
        }
    }
    if (invalid) {
        for (size_t i = 0; i < *fd_count; ++i) close(fds[i]);
        *fd_count = 0; errno = EMSGSIZE; return -1;
    }
    return count;
}

ssize_t cwt_send(int socket, const void *bytes, size_t count, const int *fds, size_t fd_count) {
    if (fd_count > 256) { errno = EMSGSIZE; return -1; }
    union { struct cmsghdr alignment; char bytes[CMSG_SPACE(256 * sizeof(int))]; } control;
    struct iovec vector = { .iov_base = (void *)bytes, .iov_len = count };
    struct msghdr message = { .msg_iov = &vector, .msg_iovlen = 1 };
    if (fd_count) {
        message.msg_control = control.bytes;
        message.msg_controllen = CMSG_SPACE(fd_count * sizeof(int));
        struct cmsghdr *header = CMSG_FIRSTHDR(&message);
        header->cmsg_level = SOL_SOCKET; header->cmsg_type = SCM_RIGHTS;
        header->cmsg_len = CMSG_LEN(fd_count * sizeof(int));
        memcpy(CMSG_DATA(header), fds, fd_count * sizeof(int));
    }
    return sendmsg(socket, &message, MSG_DONTWAIT | MSG_NOSIGNAL);
}
