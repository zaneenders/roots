#version 300 es
precision highp float;
uniform vec2 resolution;
uniform vec4 bounds;
out vec2 worldPosition;
const vec2 corners[6] = vec2[6](vec2(0,0), vec2(1,0), vec2(0,1), vec2(0,1), vec2(1,0), vec2(1,1));
void main() {
  worldPosition = bounds.xy + corners[gl_VertexID] * bounds.zw;
  gl_Position = vec4(worldPosition.x / resolution.x * 2.0 - 1.0, 1.0 - worldPosition.y / resolution.y * 2.0, 0, 1);
}
