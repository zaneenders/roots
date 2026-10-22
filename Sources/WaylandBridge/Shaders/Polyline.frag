#version 300 es
precision highp float;
in vec2 worldPosition;
uniform vec2 points[128];
uniform int pointCount;
uniform float strokeWidth;
uniform vec4 color;
out vec4 outputColor;
void main() {
  float distance = 1e30;
  vec2 start = points[0];
  for (int i = 0; i < pointCount; i++) {
    vec2 end = points[i];
    vec2 segment = end - start;
    float squaredLength = dot(segment, segment);
    float t = squaredLength > 0.0 ? clamp(dot(worldPosition - start, segment) / squaredLength, 0.0, 1.0) : 0.0;
    distance = min(distance, length(worldPosition - start - t * segment));
    start = end;
  }
  distance -= strokeWidth * 0.5;
  float edge = max(fwidth(distance) * 0.75, 0.0001);
  float coverage = 1.0 - smoothstep(-edge, edge, distance);
  outputColor = vec4(color.rgb, color.a * coverage);
}
