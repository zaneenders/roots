#version 300 es
precision highp float;

in vec2 vLocal;
in vec2 vSize;
in vec4 vColor;
in float vRadius;
in float vStrokeWidth;
in vec2 vUV;
flat in float vTextured;
uniform sampler2D fontAtlas;
uniform sampler2D emojiAtlas;
out vec4 outputColor;

void main() {
  vec2 halfSize = vSize * 0.5;
  float r = min(max(vRadius, 0.0), min(halfSize.x, halfSize.y));
  vec2 q = abs(vLocal - halfSize) - halfSize + vec2(r);
  float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
  float edge = max(fwidth(distance) * 0.75, 0.0001);
  float coverage = 1.0 - smoothstep(-edge, edge, distance);
  if (vStrokeWidth > 0.0 && vStrokeWidth < min(halfSize.x, halfSize.y)) {
    float inner = 1.0 - smoothstep(-edge, edge, distance + vStrokeWidth);
    coverage = max(0.0, coverage - inner);
  }
  if (vTextured > 1.5) {
    vec4 texel = texture(emojiAtlas, vUV);
    outputColor = vec4(texel.a > 0.0 ? texel.bgr / texel.a : vec3(0.0), texel.a * vColor.a);
    return;
  }
  if (vTextured > 0.5) coverage = texture(fontAtlas, vUV).r;
  outputColor = vec4(vColor.rgb, vColor.a * coverage);
}
