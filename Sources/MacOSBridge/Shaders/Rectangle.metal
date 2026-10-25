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
                                  texture2d<float> emojiAtlas [[texture(1)]], sampler emojiSampler [[sampler(1)]],
                                  texture2d<float> imageY [[texture(2)]], texture2d<float> imageU [[texture(3)]],
                                  texture2d<float> imageV [[texture(4)]], sampler imageSampler [[sampler(2)]],
                                  constant float4 *imageRows [[buffer(0)]]) {
  if (input.textured > 2.5) {
    float4 texel;
    if (input.textured < 3.5) {
      texel = imageY.sample(imageSampler, input.glyphUV);
    } else {
      float2 chromaUV = input.glyphUV * imageRows[3].xy + imageRows[3].zw;
      float4 yuv = float4(imageY.sample(imageSampler, input.glyphUV).r,
        imageU.sample(imageSampler, chromaUV).r,
        input.textured > 4.5 ? imageU.sample(imageSampler, chromaUV).g : imageV.sample(imageSampler, chromaUV).r, 1);
      texel = float4(clamp(float3(dot(imageRows[0], yuv), dot(imageRows[1], yuv), dot(imageRows[2], yuv)), 0.0, 1.0), 1);
    }
    return float4(texel.rgb, texel.a * input.color.a);
  }
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
fragment float4 polylineFragment(PolylineOutput input [[stage_in]], const device float4 *vertices [[buffer(0)]],
                                constant uint &count [[buffer(1)]], constant float &width [[buffer(2)]],
                                constant float4 &color [[buffer(3)]], const device float4 *chunks [[buffer(4)]],
                                constant float4 &transform [[buffer(5)]], constant float &scale [[buffer(6)]], constant float2 &pixelScale [[buffer(7)]]) {
  float2 p = (input.worldPosition - transform.xy) / scale;
  p = float2(dot(p, transform.zw), dot(p, float2(-transform.w, transform.z)));
  float distance = width * 0.5 + 2.0 / (scale * min(pixelScale.x, pixelScale.y));
  float4 tint = float4(1);
  uint segments = max(1u, count - 1);
  uint chunkCount = (segments + 63) / 64;
  for (uint chunk = 0; chunk < chunkCount; chunk++) {
    float4 bounds = chunks[chunk];
    float2 delta = max(max(bounds.xy - p, p - bounds.xy - bounds.zw), float2(0));
    if (dot(delta, delta) > distance * distance) continue;
    uint end = min((chunk + 1) * 64, segments);
    for (uint i = chunk * 64; i < end; i++) {
      float2 start = vertices[i * 2].xy;
      uint next = min(i + 1, count - 1);
      float2 segment = vertices[next * 2].xy - start;
      float squaredLength = dot(segment, segment);
      float t = squaredLength > 0.0 ? clamp(dot(p - start, segment) / squaredLength, 0.0, 1.0) : 0.0;
      float d = length(p - start - t * segment);
      if (d < distance) {
        distance = d;
        tint = mix(vertices[i * 2 + 1], vertices[next * 2 + 1], t);
      }
    }
  }
  distance = (distance - width * 0.5) * scale;
  float edge = max(fwidth(distance) * 0.75, 0.0001);
  float coverage = 1.0 - smoothstep(-edge, edge, distance);
  float4 result = clamp(tint, 0.0, 1.0) * color;
  return float4(result.rgb, result.a * coverage);
}

struct RibbonVertex { float4 geometry; float4 color; float4 edge; };
struct RibbonOutput {
  float4 position [[position]];
  float4 tint;
  float2 edgePosition;
  float cap [[flat]];
  float halfWidth [[flat]];
};
vertex RibbonOutput ribbonVertex(uint id [[vertex_id]], const device RibbonVertex *vertices [[buffer(0)]],
    constant float2 &resolution [[buffer(1)]], constant float4 &transform [[buffer(2)]],
    constant float4 &parameters [[buffer(3)]]) {
  RibbonVertex v = vertices[id];
  RibbonOutput output;
  float scale = parameters.x;
  output.halfWidth = parameters.y * scale * 0.5;
  float padding = 1.5 / min(parameters.z, parameters.w);
  float2 p = v.geometry.xy * scale + v.geometry.zw * (output.halfWidth + padding);
  p = transform.xy + transform.zw * p.x + float2(-transform.w, transform.z) * p.y;
  output.position = float4(p.x / resolution.x * 2 - 1, 1 - p.y / resolution.y * 2, 0, 1);
  output.tint = v.color;
  output.edgePosition = v.edge.xy * (output.halfWidth + padding);
  output.cap = v.edge.z;
  return output;
}
fragment float4 ribbonFragment(RibbonOutput input [[stage_in]], constant float4 &color [[buffer(0)]]) {
  float d = (input.cap > 0.5 ? length(input.edgePosition) : abs(input.edgePosition.x)) - input.halfWidth;
  float edge = max(fwidth(d) * 0.75, 0.0001);
  float coverage = 1.0 - smoothstep(-edge, edge, d);
  float4 value = clamp(input.tint, 0.0, 1.0) * color;
  return float4(value.rgb, value.a * coverage);
}
