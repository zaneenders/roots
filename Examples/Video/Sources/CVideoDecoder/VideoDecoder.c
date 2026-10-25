#include "VideoDecoder.h"
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libavutil/display.h>
#include <libavutil/opt.h>
#include <libswscale/swscale.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct RootsVideoDecoder {
  AVFormatContext *format;
  AVCodecContext *codec;
  AVPacket *packet;
  AVFrame *frame, *output, *pixels;
  struct SwsContext *scale;
  int stream, draining, bt709, full_range, chroma;
  double first_time, time, step;
  int has_time;
  int scale_width, scale_height, scale_format, scale_chroma;
};

static int fail(char *error, int capacity, const char *message, int code) {
  char detail[AV_ERROR_MAX_STRING_SIZE] = {0};
  if (code < 0) av_strerror(code, detail, sizeof(detail));
  snprintf(error, capacity, "%s%s%s", message, code < 0 ? ": " : "", detail);
  return -1;
}

void roots_video_close(RootsVideoDecoder *d) {
  if (!d) return;
  sws_freeContext(d->scale);
  av_frame_free(&d->output);
  av_frame_free(&d->frame);
  av_packet_free(&d->packet);
  avcodec_free_context(&d->codec);
  avformat_close_input(&d->format);
  free(d);
}

RootsVideoDecoder *roots_video_open(const char *path, char *error, int capacity) {
  RootsVideoDecoder *d = calloc(1, sizeof(*d));
  if (!d) { fail(error, capacity, "Out of memory", 0); return NULL; }
  d->format = avformat_alloc_context();
  if (!d->format) goto allocation;
  // Do not allow a local playlist to open network URLs or nested protocols.
  AVDictionary *options = NULL;
  av_dict_set(&options, "protocol_whitelist", "file", 0);
  int result = avformat_open_input(&d->format, path, NULL, &options);
  av_dict_free(&options);
  if (result < 0) { fail(error, capacity, "Open", result); goto failure; }
  result = avformat_find_stream_info(d->format, NULL);
  if (result < 0) { fail(error, capacity, "Stream info", result); goto failure; }
  const AVCodec *codec = NULL;
  d->stream = av_find_best_stream(d->format, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
  if (d->stream < 0) { fail(error, capacity, "No video stream", d->stream); goto failure; }
  AVStream *stream = d->format->streams[d->stream];
  // This first example explicitly rejects rotated video rather than displaying it incorrectly.
  const AVPacketSideData *rotation = av_packet_side_data_get(
    stream->codecpar->coded_side_data, stream->codecpar->nb_coded_side_data, AV_PKT_DATA_DISPLAYMATRIX);
  if (rotation && rotation->size >= 9 * sizeof(int32_t)
      && fabs(av_display_rotation_get((const int32_t *)rotation->data)) > 0.01) {
    fail(error, capacity, "Rotated video is not supported yet", 0); goto failure;
  }
  d->codec = avcodec_alloc_context3(codec);
  d->frame = av_frame_alloc();
  d->output = av_frame_alloc();
  d->packet = av_packet_alloc();
  if (!d->codec || !d->frame || !d->output || !d->packet) goto allocation;
  result = avcodec_parameters_to_context(d->codec, stream->codecpar);
  if (result < 0) { fail(error, capacity, "Codec parameters", result); goto failure; }
  d->codec->thread_count = 2; // Bound decoder worker/reference buffering.
  result = avcodec_open2(d->codec, codec, NULL);
  if (result < 0) { fail(error, capacity, "Decoder", result); goto failure; }
  AVRational rate = av_guess_frame_rate(d->format, stream, NULL);
  d->step = rate.num > 0 && rate.den > 0 ? av_q2d(av_inv_q(rate)) : 1.0 / 30;
  return d;
allocation:
  fail(error, capacity, "Out of memory", 0);
failure:
  roots_video_close(d);
  return NULL;
}

int roots_video_next(RootsVideoDecoder *d, char *error, int capacity) {
  av_frame_unref(d->frame);
  for (;;) {
    int result = avcodec_receive_frame(d->codec, d->frame);
    if (result == AVERROR_EOF) return 0;
    if (result == 0) break;
    if (result != AVERROR(EAGAIN)) return fail(error, capacity, "Decode", result);
    if (d->draining) return fail(error, capacity, "Decoder did not drain", 0);
    do {
      av_packet_unref(d->packet);
      result = av_read_frame(d->format, d->packet);
    } while (result >= 0 && d->packet->stream_index != d->stream);
    if (result == AVERROR_EOF) {
      d->draining = 1;
      result = avcodec_send_packet(d->codec, NULL);
    } else if (result >= 0) {
      result = avcodec_send_packet(d->codec, d->packet);
      av_packet_unref(d->packet);
    }
    if (result < 0) return fail(error, capacity, "Read/send packet", result);
  }
  AVFrame *f = d->frame;
  if (f->width <= 0 || f->height <= 0 || f->width > 8192 || f->height > 8192)
    return fail(error, capacity, "Unsupported video dimensions (maximum 8192)", 0);
  if (f->flags & AV_FRAME_FLAG_INTERLACED)
    return fail(error, capacity, "Interlaced video is not supported yet", 0);
  switch (f->color_trc) {
    case AVCOL_TRC_UNSPECIFIED: case AVCOL_TRC_BT709: case AVCOL_TRC_SMPTE170M:
    case AVCOL_TRC_GAMMA22: case AVCOL_TRC_GAMMA28: case AVCOL_TRC_IEC61966_2_1: break;
    default: return fail(error, capacity, "Unsupported transfer function (SDR only)", 0);
  }
  switch (f->color_primaries) {
    case AVCOL_PRI_UNSPECIFIED: case AVCOL_PRI_BT709:
    case AVCOL_PRI_BT470BG: case AVCOL_PRI_SMPTE170M: break;
    default: return fail(error, capacity, "Wide-gamut video is not supported yet", 0);
  }
  AVRational aspect = av_guess_sample_aspect_ratio(d->format, d->format->streams[d->stream], f);
  if (aspect.num > 0 && aspect.den > 0 && aspect.num != aspect.den)
    return fail(error, capacity, "Non-square pixels are not supported yet", 0);
  int result = av_frame_apply_cropping(f, 0);
  if (result < 0) return fail(error, capacity, "Crop", result);
  int space;
  switch (f->colorspace) {
    case AVCOL_SPC_BT709: space = SWS_CS_ITU709; break;
    case AVCOL_SPC_BT470BG: case AVCOL_SPC_SMPTE170M: space = SWS_CS_ITU601; break;
    case AVCOL_SPC_UNSPECIFIED: space = f->height >= 720 ? SWS_CS_ITU709 : SWS_CS_ITU601; break;
    case AVCOL_SPC_RGB: space = SWS_CS_ITU709; break;
    default: return fail(error, capacity, "Unsupported color matrix", 0);
  }
  d->bt709 = space == SWS_CS_ITU709;
  d->full_range = f->color_range == AVCOL_RANGE_JPEG;
  switch (f->chroma_location) {
    case AVCHROMA_LOC_UNSPECIFIED: case AVCHROMA_LOC_CENTER: d->chroma = 0; break;
    case AVCHROMA_LOC_LEFT: d->chroma = 1; break;
    case AVCHROMA_LOC_TOPLEFT: d->chroma = 2; break;
    default: return fail(error, capacity, "Unsupported chroma location", 0);
  }
  d->pixels = f;
  if (f->format != AV_PIX_FMT_YUV420P) {
    if (d->output->width != f->width || d->output->height != f->height) {
      av_frame_unref(d->output);
      d->output->format = AV_PIX_FMT_YUV420P;
      d->output->width = f->width;
      d->output->height = f->height;
      result = av_frame_get_buffer(d->output, 32);
      if (result < 0) return fail(error, capacity, "Allocate output", result);
    }
    if (!d->scale || d->scale_width != f->width || d->scale_height != f->height
        || d->scale_format != f->format || d->scale_chroma != d->chroma) {
      sws_freeContext(d->scale);
      d->scale = sws_alloc_context();
      if (!d->scale) return fail(error, capacity, "Allocate converter", 0);
      #define SET_OPTION(name, value) \
        if (av_opt_set_int(d->scale, name, value, 0) < 0) \
          return fail(error, capacity, "Configure converter: " name, 0)
      SET_OPTION("srcw", f->width); SET_OPTION("srch", f->height);
      SET_OPTION("dstw", f->width); SET_OPTION("dsth", f->height);
      SET_OPTION("src_format", f->format); SET_OPTION("dst_format", AV_PIX_FMT_YUV420P);
      SET_OPTION("sws_flags", SWS_BILINEAR);
      SET_OPTION("src_h_chr_pos", d->chroma == 0 ? 128 : 0);
      SET_OPTION("src_v_chr_pos", d->chroma == 2 ? 0 : 128);
      SET_OPTION("dst_h_chr_pos", 128); SET_OPTION("dst_v_chr_pos", 128);
      #undef SET_OPTION
      result = sws_init_context(d->scale, NULL, NULL);
      if (result < 0) return fail(error, capacity, "Initialize converter", result);
      d->scale_width = f->width; d->scale_height = f->height;
      d->scale_format = f->format; d->scale_chroma = d->chroma;
    }
    // Preserve matrix/range; conversion to RGB belongs to the renderer.
    result = sws_setColorspaceDetails(d->scale, sws_getCoefficients(space), d->full_range,
      sws_getCoefficients(space), d->full_range, 0, 1 << 16, 1 << 16);
    if (result < 0) return fail(error, capacity, "Color conversion", result);
    result = sws_scale(d->scale, (const uint8_t * const *)f->data, f->linesize, 0, f->height,
      d->output->data, d->output->linesize);
    if (result != f->height) return fail(error, capacity, "Scale", result < 0 ? result : 0);
    d->pixels = d->output;
    // Explicitly configured centered 4:2:0 destination.
    d->chroma = 0;
  }
  int64_t pts = f->best_effort_timestamp;
  double time = pts == AV_NOPTS_VALUE ? (d->has_time ? d->time + d->first_time + d->step : 0)
    : pts * av_q2d(d->format->streams[d->stream]->time_base);
  if (!isfinite(time)) return fail(error, capacity, "Invalid timestamp", 0);
  if (!d->has_time) { d->first_time = time; d->has_time = 1; }
  d->time = fmax(d->time, time - d->first_time);
  return 1;
}

int roots_video_width(const RootsVideoDecoder *d) { return d->pixels->width; }
int roots_video_height(const RootsVideoDecoder *d) { return d->pixels->height; }
double roots_video_time(const RootsVideoDecoder *d) { return d->time; }
const uint8_t *roots_video_plane(const RootsVideoDecoder *d, int plane) { return d->pixels->data[plane]; }
int roots_video_stride(const RootsVideoDecoder *d, int plane) { return d->pixels->linesize[plane]; }

int roots_video_bt709(const RootsVideoDecoder *d) { return d->bt709; }
int roots_video_full_range(const RootsVideoDecoder *d) { return d->full_range; }
int roots_video_chroma(const RootsVideoDecoder *d) { return d->chroma; }
