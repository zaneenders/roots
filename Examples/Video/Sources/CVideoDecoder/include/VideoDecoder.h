#ifndef ROOTS_EXAMPLE_VIDEO_DECODER_H
#define ROOTS_EXAMPLE_VIDEO_DECODER_H
#include <stdint.h>

typedef struct RootsVideoDecoder RootsVideoDecoder;
// Local files only. Errors are copied into the caller's buffer.
RootsVideoDecoder *roots_video_open(const char *path, char *error, int capacity);
void roots_video_close(RootsVideoDecoder *decoder);
// 1 = frame, 0 = EOF, -1 = error. Frame planes are borrowed until next/close.
int roots_video_next(RootsVideoDecoder *decoder, char *error, int capacity);
int roots_video_width(const RootsVideoDecoder *decoder);
int roots_video_height(const RootsVideoDecoder *decoder);
int roots_video_bt709(const RootsVideoDecoder *decoder);
int roots_video_full_range(const RootsVideoDecoder *decoder);
int roots_video_chroma(const RootsVideoDecoder *decoder); // 0=center, 1=left, 2=top-left
double roots_video_time(const RootsVideoDecoder *decoder);
const uint8_t *roots_video_plane(const RootsVideoDecoder *decoder, int plane);
int roots_video_stride(const RootsVideoDecoder *decoder, int plane);
#endif
