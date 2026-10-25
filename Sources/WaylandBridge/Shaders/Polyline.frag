#version 300 es
precision highp float;
precision highp int;
in vec2 worldPosition;
uniform highp sampler2D geometry;
uniform int pointCount;
uniform float strokeWidth;
uniform vec4 color;
uniform vec4 transform; // translation.xy, rotation axis.xy
uniform float scale;
uniform vec2 pixelScale;
out vec4 outputColor;
vec4 dataAt(int index) { return texelFetch(geometry, ivec2(index % 256, index / 256), 0); }
void main() {
  vec2 p = (worldPosition - transform.xy) / scale;
  p = vec2(dot(p, transform.zw), dot(p, vec2(-transform.w, transform.z)));
  float distance = strokeWidth * 0.5 + 2.0 / (scale * min(pixelScale.x, pixelScale.y));
  vec4 tint = vec4(1);
  int segments = max(1, pointCount - 1);
  int chunks = (segments + 63) / 64;
  for (int chunk = 0; chunk < chunks; chunk++) {
    vec4 bounds = dataAt(chunk * 3 + 2);
    vec2 delta = max(max(bounds.xy - p, p - bounds.xy - bounds.zw), vec2(0));
    if (dot(delta, delta) > distance * distance) continue;
    int endIndex = min((chunk + 1) * 64, segments);
    for (int i = chunk * 64; i < endIndex; i++) {
      vec2 start = dataAt(i * 3).xy;
      int next = min(i + 1, pointCount - 1);
      vec2 segment = dataAt(next * 3).xy - start;
      float squaredLength = dot(segment, segment);
      float t = squaredLength > 0.0 ? clamp(dot(p - start, segment) / squaredLength, 0.0, 1.0) : 0.0;
      float d = length(p - start - t * segment);
      if (d < distance) {
        distance = d;
        tint = mix(dataAt(i * 3 + 1), dataAt(next * 3 + 1), t);
      }
    }
  }
  distance = (distance - strokeWidth * 0.5) * scale;
  float edge = max(fwidth(distance) * 0.75, 0.0001);
  float coverage = 1.0 - smoothstep(-edge, edge, distance);
  vec4 result = clamp(tint, 0.0, 1.0) * color;
  outputColor = vec4(result.rgb, result.a * coverage);
}
