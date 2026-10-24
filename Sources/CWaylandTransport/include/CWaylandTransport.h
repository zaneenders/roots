#pragma once
#include <stddef.h>
#include <sys/socket.h>

size_t cwt_control_space(size_t size);
size_t cwt_control_length(size_t size);
struct cmsghdr *cwt_first_header(struct msghdr *message);
struct cmsghdr *cwt_next_header(struct msghdr *message, struct cmsghdr *header);
void *cwt_control_data(struct cmsghdr *header);
