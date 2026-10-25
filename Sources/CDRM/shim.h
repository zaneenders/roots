#include <xf86drm.h>
#include <drm_fourcc.h>
enum {
  ROOTS_DRM_ARGB8888 = DRM_FORMAT_ARGB8888,
  ROOTS_DRM_ABGR8888 = DRM_FORMAT_ABGR8888
};
static const uint64_t ROOTS_DRM_MOD_INVALID = DRM_FORMAT_MOD_INVALID;
#include <linux/dma-buf.h>
// ioctl request macros contain sizeof expressions, which Swift cannot import.
static const unsigned long ROOTS_DMA_BUF_IOCTL_IMPORT_SYNC_FILE = DMA_BUF_IOCTL_IMPORT_SYNC_FILE;
