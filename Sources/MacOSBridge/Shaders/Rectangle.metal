#include <metal_stdlib>
using namespace metal;

struct VertexInput {
  float2 position [[attribute(0)]];
  float2 size [[attribute(1)]];
  float4 color [[attribute(2)]];
  float radius [[attribute(3)]];
  float4 glyphUV [[attribute(4)]];
  float textured [[attribute(5)]];
  float strokeWidth [[attribute(6)]];
  float2 axis [[attribute(7)]];
};

struct VertexOutput {
  float4 position [[position]];
  float2 localPosition;
  float2 size;
  float4 color;
  float radius;
  float2 glyphUV;
  float textured [[flat]];
  float strokeWidth;
};

constant float2 corners[6] = {float2(0,0), float2(1,0), float2(0,1), float2(0,1), float2(1,0), float2(1,1)};
vertex VertexOutput rectangleVertex(VertexInput input [[stage_in]], uint vertexID [[vertex_id]], constant float2 &resolution [[buffer(1)]]) {
  VertexOutput output;
  float padding = input.textured > 0.5 ? 0.0 : 1.0;
  float2 local = corners[vertexID] * (input.size + 2.0 * padding) - padding;
  float2 world = input.position + input.axis * local.x + float2(-input.axis.y, input.axis.x) * local.y;
  output.position = float4(world.x / resolution.x * 2.0 - 1.0, 1.0 - world.y / resolution.y * 2.0, 0, 1);
  output.localPosition = local;
  output.size = input.size;
  output.color = input.color;
  output.radius = input.radius;
  output.strokeWidth = input.strokeWidth;
  output.glyphUV = input.glyphUV.xy + corners[vertexID] * input.glyphUV.zw;
  output.textured = input.textured;
  return output;
}

fragment float4 rectangleFragment(VertexOutput input [[stage_in]],
                                  texture2d<float> atlas [[texture(0)]], sampler atlasSampler [[sampler(0)]],
                                  texture2d<float> emojiAtlas [[texture(1)]], sampler emojiSampler [[sampler(1)]]) {
  float2 halfSize = input.size * 0.5;
  float radius = clamp(input.radius, 0.0, min(halfSize.x, halfSize.y));
  float2 q = abs(input.localPosition - halfSize) - halfSize + float2(radius);
  float distance = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
  float edge = max(fwidth(distance) * 0.75, 0.0001);
  float coverage = 1.0 - smoothstep(-edge, edge, distance);
  if (input.strokeWidth > 0.0 && input.strokeWidth < min(halfSize.x, halfSize.y)) {
    float inner = 1.0 - smoothstep(-edge, edge, distance + input.strokeWidth);
    coverage = max(0.0, coverage - inner);
  }
  if (input.textured > 1.5) {
    float4 texel = emojiAtlas.sample(emojiSampler, input.glyphUV);
    return float4(texel.a > 0.0 ? texel.rgb / texel.a : float3(0.0), texel.a * input.color.a);
  }
  if (input.textured > 0.5) coverage = atlas.sample(atlasSampler, input.glyphUV).r;
  return float4(input.color.rgb, input.color.a * coverage);
}

struct PolylineOutput {
  float4 position [[position]];
  float2 worldPosition;
};
vertex PolylineOutput polylineVertex(uint vertexID [[vertex_id]], constant float4 &bounds [[buffer(0)]],
                                     constant float2 &resolution [[buffer(1)]]) {
  PolylineOutput output;
  output.worldPosition = bounds.xy + corners[vertexID] * bounds.zw;
  output.position = float4(output.worldPosition.x / resolution.x * 2.0 - 1.0,
                          1.0 - output.worldPosition.y / resolution.y * 2.0, 0, 1);
  return output;
}
fragment float4 polylineFragment(PolylineOutput input [[stage_in]], constant float2 *points [[buffer(0)]],
                                constant uint &count [[buffer(1)]], constant float &width [[buffer(2)]],
                                constant float4 &color [[buffer(3)]]) {
  float distance = 1e30;
  float2 start = points[0];
  for (uint i = 0; i < count; i++) {
    float2 end = points[i];
    float2 segment = end - start;
    float squaredLength = dot(segment, segment);
    float t = squaredLength > 0.0 ? clamp(dot(input.worldPosition - start, segment) / squaredLength, 0.0, 1.0) : 0.0;
    distance = min(distance, length(input.worldPosition - start - t * segment));
    start = end;
  }
  distance -= width * 0.5;
  float edge = max(fwidth(distance) * 0.75, 0.0001);
  float coverage = 1.0 - smoothstep(-edge, edge, distance);
  return float4(color.rgb, color.a * coverage);
}
