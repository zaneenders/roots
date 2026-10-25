#version 300 es
precision highp float;
in vec4 tint;
in vec2 edgePosition;
flat in float cap;
flat in float halfWidth;
uniform vec4 color;
out vec4 outputColor;
void main() {
  float d = (cap > 0.5 ? length(edgePosition) : abs(edgePosition.x)) - halfWidth;
  float edge = max(fwidth(d) * 0.75, 0.0001);
  float coverage = 1.0 - smoothstep(-edge, edge, d);
  vec4 value = clamp(tint, 0.0, 1.0) * color;
  outputColor = vec4(value.rgb, value.a * coverage);
}
