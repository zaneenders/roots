#include "CWaylandTransport.h"

size_t cwt_control_space(size_t size) { return CMSG_SPACE(size); }
size_t cwt_control_length(size_t size) { return CMSG_LEN(size); }
struct cmsghdr *cwt_first_header(struct msghdr *message) { return CMSG_FIRSTHDR(message); }
struct cmsghdr *cwt_next_header(struct msghdr *message, struct cmsghdr *header) {
    return CMSG_NXTHDR(message, header);
}
void *cwt_control_data(struct cmsghdr *header) { return CMSG_DATA(header); }
