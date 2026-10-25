#version 300 es
precision highp float;
layout(location=0) in vec4 geometry;
layout(location=1) in vec4 vertexColor;
layout(location=2) in vec4 edge;
uniform vec2 resolution;
uniform vec4 transform;
uniform float scale;
uniform float strokeWidth;
uniform vec2 pixelScale;
out vec4 tint;
out vec2 edgePosition;
flat out float cap;
flat out float halfWidth;
void main() {
  halfWidth = strokeWidth * scale * 0.5;
  float padding = 1.5 / min(pixelScale.x, pixelScale.y);
  vec2 p = geometry.xy * scale + geometry.zw * (halfWidth + padding);
  p = transform.xy + transform.zw * p.x + vec2(-transform.w, transform.z) * p.y;
  gl_Position = vec4(p.x / resolution.x * 2.0 - 1.0, 1.0 - p.y / resolution.y * 2.0, 0, 1);
  tint = vertexColor;
  edgePosition = edge.xy * (halfWidth + padding);
  cap = edge.z;
}
