#version 300 es
layout(location = 0) in vec2 position;
layout(location = 1) in vec2 size;
layout(location = 2) in vec4 color;
layout(location = 3) in float radius;
layout(location = 4) in vec4 glyphUV;
layout(location = 5) in float textured;
layout(location = 6) in float strokeWidth;
layout(location = 7) in vec2 axis;
uniform vec2 resolution;

out vec2 vLocal;
out vec2 vSize;
out vec4 vColor;
out float vRadius;
out vec2 vUV;
flat out float vTextured;
out float vStrokeWidth;

const vec2 corners[6] = vec2[6](vec2(0,0), vec2(1,0), vec2(0,1), vec2(0,1), vec2(1,0), vec2(1,1));
void main() {
  vec2 corner = corners[gl_VertexID];
  float padding = textured > 0.5 ? 0.0 : 1.0;
  vec2 local = corner * (size + 2.0 * padding) - padding;
  vec2 world = position + axis * local.x + vec2(-axis.y, axis.x) * local.y;
  vLocal = local;
  vSize = size;
  vColor = color;
  vRadius = radius;
  vStrokeWidth = strokeWidth;
  vUV = glyphUV.xy + corner * glyphUV.zw;
  vTextured = textured;
  gl_Position = vec4(world.x / resolution.x * 2.0 - 1.0, 1.0 - world.y / resolution.y * 2.0, 0.0, 1.0);
}
