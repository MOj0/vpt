// #part /glsl/shaders/renderers/FOVEATED/generate/vertex

#version 300 es

uniform mat4 uMvpInverseMatrix;

out vec3 vRayFrom;
out vec3 vRayTo;
out vec2 vPosition;

// #link /glsl/mixins/unproject
@unproject

const vec2 vertices[] = vec2[](
    vec2(-1, -1),
    vec2( 3, -1),
    vec2(-1,  3)
);

void main() {
    vec2 position = vertices[gl_VertexID];
    unproject(position, uMvpInverseMatrix, vRayFrom, vRayTo);
    vPosition = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0, 1);
}

// #part /glsl/shaders/renderers/FOVEATED/generate/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;
precision mediump sampler3D;

uniform sampler3D uVolume;
uniform sampler2D uTransferFunction;
uniform float uStepSize;
uniform float uOffset;

uniform vec2 uMousePos;

in vec3 vRayFrom;
in vec3 vRayTo;
in vec2 vPosition;

out float oColor;

// #link /glsl/mixins/intersectCube
@intersectCube

vec4 sampleVolumeColor(vec3 position) {
    vec2 volumeSample = texture(uVolume, position).rg;
    vec4 transferSample = texture(uTransferFunction, volumeSample);
    return transferSample;
}

void main() {
    // Mouse interaction
    if (uMousePos.x >= 0.0 && uMousePos.y >= 0.0 && distance(vPosition, uMousePos) < 0.05) {
        oColor = 5.0;
        return;
    }

    vec3 rayDirection = vRayTo - vRayFrom;
    vec2 tbounds = max(intersectCube(vRayFrom, rayDirection), 0.0);
    if (tbounds.x >= tbounds.y) {
        oColor = 0.0;
    } else {
        vec3 from = mix(vRayFrom, vRayTo, tbounds.x);
        vec3 to = mix(vRayFrom, vRayTo, tbounds.y);

        float t = 0.0;
        float val = 0.0;
        float offset = uOffset;
        vec3 pos;
        do {
            pos = mix(from, to, offset);
            val = max(sampleVolumeColor(pos).a, val);
            t += uStepSize;
            offset = mod(offset + uStepSize, 1.0);
        } while (t < 1.0);
        oColor = val;
    }
}

// #part /glsl/shaders/renderers/FOVEATED/compute/vertex

#version 300 es

out vec2 vPosition;

const vec2 vertices[] = vec2[](
    vec2(-1, -1),
    vec2( 3, -1),
    vec2(-1,  3)
);

void main() {
    vec2 position = vertices[gl_VertexID];
    vPosition = position;
    gl_Position = vec4(position, 0, 1);

    // ivec2 texSize = ivec2(512);
    // float y = float(gl_VertexID / texSize.x) / float(texSize.y - 1);
    // float x = float(gl_VertexID % texSize.x) / float(texSize.x);
    // vec2 position = vec2(x, y) * 2.0 - 1.0;

    // vPosition = position;
    // gl_Position = vec4(position, 0, 1);
}

// #part /glsl/shaders/renderers/FOVEATED/compute/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;

@constants
@random/hash/pcg
@random/hash/squashlinear
@random/distribution/uniformdivision
@random/distribution/square
@random/distribution/disk
@random/distribution/sphere
@random/distribution/exponential

uniform sampler2D uFrame;
uniform float uRandSeed;

in vec2 vPosition;

out vec2 oPositionRender;

vec4 getNodeImportance(ivec2 pos, int mipLevel){
    float i1 = texelFetch(uFrame, pos, mipLevel).r;
    float i2 = texelFetch(uFrame, pos + ivec2(1, 0), mipLevel).r;
    float i3 = texelFetch(uFrame, pos + ivec2(0, 1), mipLevel).r;
    float i4 = texelFetch(uFrame, pos + ivec2(1, 1), mipLevel).r;
    float sum = i1 + i2 + i3 + i4;

    if (abs(sum) < 0.001) {
        return vec4(0.25);
    }

    return vec4(i1 / sum, i2 / sum, i3 / sum, i4 / sum);
}

int getRegion(vec4 regionImportance, float random) {
    float cumulativeProbability = 0.0;

    for (int i = 0; i < 4; i++) {
        cumulativeProbability += regionImportance[i];
        if (random <= cumulativeProbability) {
            return i;
        }
    }

    return 0; // Unreachable...
}

// Random sampling
void main() {
    // ivec2 frameSize = textureSize(uFrame, 0);
    // ivec2 frameSizeHalf = frameSize / 2;
    // int maxMipLevel = int(log2(float(frameSizeHalf.x)));
    // uint state = hash(uvec3(floatBitsToUint(vPosition.x), floatBitsToUint(vPosition.y), floatBitsToUint(uRandSeed)));

    // ivec2 currPos = ivec2(0);
    // for (int mipLevel = maxMipLevel; mipLevel > 0; mipLevel--) {
    //     float random = random_uniform(state);
    //     // vec4 regionImportance = getNodeImportance(currPos, mipLevel);
    //     vec4 regionImportance = vec4(0.25);
    //     int region = getRegion(regionImportance, random);

    //     if (region == 0) {
    //         // Top left quadrant
    //         currPos = 2 * currPos;
    //     }
    //     else if (region == 1) {
    //         // Top right quadrant
    //         currPos = 2 * (currPos + ivec2(1, 0));
    //     }
    //     else if (region == 2) {
    //         // Bottom left quadrant
    //         currPos = 2 * (currPos + ivec2(0, 1));
    //     } else {
    //         // Bottom right quadrant
    //         currPos = 2 * (currPos + ivec2(1, 1));
    //     }
    // }

    /////
    // ivec2 frameSize = textureSize(uFrame, 0);
    // ivec2 frameSizeHalf = frameSize / 2;
    // // int maxMipLevel = int(log2(float(frameSizeHalf.x)));
    // int maxMipLevel = 8;
    // uint state = hash(uvec3(floatBitsToUint(vPosition.x), floatBitsToUint(vPosition.y), floatBitsToUint(uRandSeed)));

    // ivec2 currPos = ivec2(0);
    // for (int mipLevel = maxMipLevel; mipLevel > maxMipLevel - 1; mipLevel--) {
    //     float random = random_uniform(state);
    //     // vec4 regionImportance = getNodeImportance(currPos, mipLevel);
    //     vec4 regionImportance = vec4(0.25);
    //     int region = getRegion(regionImportance, random);

    //     if (region == 0) {
    //         // Top left quadrant
    //         currPos = 2 * currPos;
    //     }
    //     else if (region == 1) {
    //         // Top right quadrant
    // TODO: Multply by 2 first, then add
    //         currPos = 2 * (currPos + ivec2(1, 0));
    //     }
    //     else if (region == 2) {
    //         // Bottom left quadrant
    //         currPos = 2 * (currPos + ivec2(0, 1));
    //     } else {
    //         // Bottom right quadrant
    //         currPos = 2 * (currPos + ivec2(1, 1));
    //     }
    // }
    // oPositionRender = (vec2(currPos - ivec2(1)) / vec2(1));
    /////

    /////
    uint state = hash(uvec3(floatBitsToUint(vPosition.x), floatBitsToUint(vPosition.y), floatBitsToUint(uRandSeed)));
    int maxDepth = 8;
    int maxCoord = int(pow(2.0, float(maxDepth))) - 1;
    float maxHalf = float(maxCoord) / 2.0;

    ivec2 currPos = ivec2(0);
    for(int depth = maxDepth; depth > 0; depth--){
        float random = random_uniform(state);
        vec4 regionImportance = getNodeImportance(currPos, depth);
        int region = getRegion(regionImportance, random);

        if (region == 0){
            currPos = 2 * currPos;
        } else if(region == 1){
            currPos = 2 * currPos + ivec2(1, 0);
        }  else if(region == 2){
            currPos = 2 * currPos + ivec2(0, 1);
        } else {
            currPos = 2 * currPos + ivec2(1, 1);
        }
    }

    vec2 newPos = (vec2(currPos) - vec2(maxHalf)) / vec2(maxHalf);
    // newPos.y = -newPos.y;
    oPositionRender = newPos;

    /////
    // /////
    // uint state = hash(uvec3(floatBitsToUint(vPosition.x), floatBitsToUint(vPosition.y), floatBitsToUint(uRandSeed)));

    // ivec2 currPos = ivec2(0);
    // float random = random_uniform(state);
    // vec4 regionImportance = getNodeImportance(currPos, 8);
    // int region = getRegion(regionImportance, random);

    // if (region == 0){
    //     currPos = 2 * currPos;
    // } else if(region == 1){
    //     currPos = 2 * currPos + ivec2(1, 0);
    // }  else if(region == 2){
    //     currPos = 2 * currPos + ivec2(0, 1);
    // } else {
    //     currPos = 2 * currPos + ivec2(1, 1);
    // }

    // int depth = 1;
    // int maxCoord = int(pow(2.0, float(depth))) - 1;
    // float maxHalf = float(maxCoord) / 2.0;

    // vec2 newPos = (vec2(currPos) - vec2(maxHalf)) / vec2(maxHalf);
    // newPos.y = -newPos.y;
    // newPos = newPos * 0.65;
    // oPositionRender = newPos;
    // /////

    /////
    // int depth = 4;
    // int maxCoord = int(pow(2.0, float(depth))) - 1;
    // float maxHalf = float(maxCoord) / 2.0;
    // ivec2 currPos = ivec2(0);
    // uint state = hash(uvec3(floatBitsToUint(vPosition.x), floatBitsToUint(vPosition.y), floatBitsToUint(uRandSeed)));
    // float random = random_uniform(state);
    // vec2 pos = vec2(0);
    // if (random < 0.25){
    //     currPos = ivec2(0, 0);
    //     pos = vec2(-1, 1);
    // } else if (random < 0.5){
    //     currPos = ivec2(maxCoord, 0);
    //     pos = vec2(1, 1);
    // } else if (random < 0.75){
    //     currPos = ivec2(0, maxCoord);
    //     pos = vec2(-1, -1);
    // } else {
    //     currPos = ivec2(maxCoord, maxCoord);
    //     pos = vec2(1, -1);
    // }
    // vec2 newPos = (vec2(currPos) - vec2(maxHalf)) / vec2(maxHalf);
    // newPos.y = -newPos.y;
    // newPos = newPos * 0.65;
    // oPositionRender = newPos;

    // // currPos = currPos + ivec2(-1, -1);
    // // currPos.y = -currPos.y;
    // // vec2 newPos = vec2(currPos) * 0.65;
    // // oPositionRender = pos * 0.65;
    ////

    //////
    // vec2 position = vec2(0.0);
    // int max_levels = 7;
    // uint state = hash(uvec3(floatBitsToUint(vPosition.x), floatBitsToUint(vPosition.y), floatBitsToUint(uRandSeed)));

    // ivec2 currPos = ivec2(0);
    // for (int depth = 1; depth <= max_levels; depth++) {
    //     float random = random_uniform(state);
    //     // vec4 regionImportance = getNodeImportance(currPos, depth);
    //     vec4 regionImportance = vec4(0.25);
    //     int region = getRegion(regionImportance, random);

    //     if (region == 0) {
    //         // Top left quadrant
    //         position = position + vec2(-1.0, 1.0) * pow(0.5, float(depth));
    //     }
    //     else if (region == 1) {
    //         // Top right quadrant
    //         position = position + vec2(1.0, 1.0) * pow(0.5, float(depth));
    //     }
    //     else if (region == 2) {
    //         // Bottom left quadrant
    //         position = position + vec2(-1.0, -1.0) * pow(0.5, float(depth));
    //     } else {
    //         // Bottom right quadrant
    //         position = position + vec2(1.0, -1.0) * pow(0.5, float(depth));
    //     }
    // }

    // float rand_dirX = random_uniform(state);
    // float rand_dirY = random_uniform(state);
    // vec2 rand_dir = vec2(rand_dirX, rand_dirY) * 0.1 - 0.05;
    // position = position + rand_dir * pow(0.5, float(max_levels + 1));
    // oPositionRender = position;
    ///////

    // oPositionRender = (vec2(currPos - frameSizeHalf) / vec2(frameSizeHalf));
    // oPositionRender = vec2(0.2, 0.3);
    // uint state = hash(uvec3(floatBitsToUint(vPosition.x), floatBitsToUint(vPosition.y), floatBitsToUint(uRandSeed)));
    // float randX = random_uniform(state);
    // float randY = random_uniform(state);
    // oPositionRender = vec2(randX, randY) * 2.0 - 1.0;
}

// #part /glsl/shaders/renderers/FOVEATED/integrate/vertex

#version 300 es

precision mediump float;
precision mediump sampler2D;

uniform sampler2D uRenderPosition;

out vec2 vPosition;

void main() {
    // ivec2 texSize = textureSize(uRenderPosition, 0);
    // int y = gl_VertexID / texSize.x;
    // int x = gl_VertexID % texSize.x;
    // vec2 renderPosition = texelFetch(uRenderPosition, ivec2(x, y), 0).xy;

    // vPosition = renderPosition;

    // gl_Position = vec4(renderPosition, 0, 1);
    // gl_PointSize = 1.0;
    // ivec2 texSize = textureSize(uRenderPosition, 0);

    ivec2 texSize = textureSize(uRenderPosition, 0);
    float y = float(gl_VertexID / texSize.x) / float(texSize.y - 1);
    float x = float(gl_VertexID % texSize.x) / float(texSize.x);
    vec2 renderPosition = texture(uRenderPosition, vec2(x, y)).xy;

    vPosition = renderPosition;

    gl_Position = vec4(renderPosition, 0, 1);
    gl_PointSize = 1.0;
}

// #part /glsl/shaders/renderers/FOVEATED/integrate/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;
precision mediump sampler3D;

#define EPS 1e-5

// #link /glsl/mixins/Photon
@Photon
// #link /glsl/mixins/intersectCube
@intersectCube

@constants
@random/hash/pcg
@random/hash/squashlinear
@random/distribution/uniformdivision
@random/distribution/square
@random/distribution/disk
@random/distribution/sphere
@random/distribution/exponential

@unprojectRand

uniform sampler2D uPosition;
uniform sampler2D uDirection;
uniform sampler2D uTransmittance;
uniform sampler2D uRadiance;

uniform sampler3D uVolume;
uniform sampler2D uTransferFunction;
uniform sampler2D uEnvironment;

uniform mat4 uMvpInverseMatrix;
uniform vec2 uInverseResolution;
uniform float uBlur;

uniform float uRandSeed;

uniform float uExtinction;
uniform float uAnisotropy;
uniform uint uMaxBounces;
uniform uint uSteps;

in vec2 vPosition;

layout (location = 0) out vec4 oPosition;
layout (location = 1) out vec4 oDirection;
layout (location = 2) out vec4 oTransmittance;
layout (location = 3) out vec4 oRadiance;

void resetPhoton(inout uint state, in vec2 position, inout Photon photon) {
    vec3 from, to;
    unprojectRand(state, position, uMvpInverseMatrix, uInverseResolution, uBlur, from, to);
    photon.direction = normalize(to - from);
    photon.bounces = 0u;
    vec2 tbounds = max(intersectCube(from, photon.direction), 0.0);
    photon.position = from + tbounds.x * photon.direction;
    photon.transmittance = vec3(1);
}

vec4 sampleEnvironmentMap(vec3 d) {
    vec2 texCoord = vec2(atan(d.x, -d.z), asin(-d.y) * 2.0) * INVPI * 0.5 + 0.5;
    return texture(uEnvironment, texCoord);
}

vec4 sampleVolumeColor(vec3 position) {
    vec2 volumeSample = texture(uVolume, position).rg;
    vec4 transferSample = texture(uTransferFunction, volumeSample);
    return transferSample;
}

float sampleHenyeyGreensteinAngleCosine(inout uint state, float g) {
    float g2 = g * g;
    float c = (1.0 - g2) / (1.0 - g + 2.0 * g * random_uniform(state));
    return (1.0 + g2 - c * c) / (2.0 * g);
}

vec3 sampleHenyeyGreenstein(inout uint state, float g, vec3 direction) {
    // generate random direction and adjust it so that the angle is HG-sampled
    vec3 u = random_sphere(state);
    if (abs(g) < EPS) {
        return u;
    }
    float hgcos = sampleHenyeyGreensteinAngleCosine(state, g);
    vec3 circle = normalize(u - dot(u, direction) * direction);
    return sqrt(1.0 - hgcos * hgcos) * circle + hgcos * direction;
}

float max3(vec3 v) {
    return max(max(v.x, v.y), v.z);
}

float mean3(vec3 v) {
    return dot(v, vec3(1.0 / 3.0));
}

void main() {
    // Photon photon;
    // vec2 mappedPosition = vPosition * 0.5 + 0.5;
    // photon.position = texture(uPosition, mappedPosition).xyz;
    // vec4 directionAndBounces = texture(uDirection, mappedPosition);
    // photon.direction = directionAndBounces.xyz;
    // photon.bounces = uint(directionAndBounces.w + 0.5);
    // photon.transmittance = texture(uTransmittance, mappedPosition).rgb;
    // vec4 radianceAndSamples = texture(uRadiance, mappedPosition);
    // photon.radiance = radianceAndSamples.rgb;
    // photon.samples = uint(radianceAndSamples.w + 0.5);

    // uint state = hash(uvec3(floatBitsToUint(mappedPosition.x), floatBitsToUint(mappedPosition.y), floatBitsToUint(uRandSeed)));
    // for (uint i = 0u; i < uSteps; i++) {
    //     float dist = random_exponential(state, uExtinction);
    //     photon.position += dist * photon.direction;

    //     vec4 volumeSample = sampleVolumeColor(photon.position);

    //     float PNull = 1.0 - volumeSample.a;
    //     float PScattering;
    //     if (photon.bounces >= uMaxBounces) {
    //         PScattering = 0.0;
    //     } else {
    //         PScattering = volumeSample.a * max3(volumeSample.rgb);
    //     }
    //     float PAbsorption = 1.0 - PNull - PScattering;

    //     float fortuneWheel = random_uniform(state);
    //     if (any(greaterThan(photon.position, vec3(1))) || any(lessThan(photon.position, vec3(0)))) {
    //         // out of bounds
    //         vec4 envSample = sampleEnvironmentMap(photon.direction);
    //         vec3 radiance = photon.transmittance * envSample.rgb;
    //         photon.samples++;
    //         photon.radiance += (radiance - photon.radiance) / float(photon.samples);
    //         resetPhoton(state, vPosition, photon);
    //     } else if (fortuneWheel < PAbsorption) {
    //         // absorption
    //         vec3 radiance = vec3(0);
    //         photon.samples++;
    //         photon.radiance += (radiance - photon.radiance) / float(photon.samples);
    //         resetPhoton(state, vPosition, photon);
    //     } else if (fortuneWheel < PAbsorption + PScattering) {
    //         // scattering
    //         photon.transmittance *= volumeSample.rgb;
    //         photon.direction = sampleHenyeyGreenstein(state, uAnisotropy, photon.direction);
    //         photon.bounces++;
    //     } else {
    //         // null collision
    //     }
    // }

    // oPosition = vec4(photon.position, 0);
    // oDirection = vec4(photon.direction, float(photon.bounces));
    // oTransmittance = vec4(photon.transmittance, 0);
    // oRadiance = vec4(photon.radiance, float(photon.samples));


    Photon photon;
    vec2 mappedPosition = vPosition * 0.5 + 0.5;
    photon.position = texture(uPosition, mappedPosition).xyz;
    vec4 directionAndBounces = texture(uDirection, mappedPosition);
    photon.direction = directionAndBounces.xyz;
    photon.bounces = uint(directionAndBounces.w + 0.5);
    photon.transmittance = texture(uTransmittance, mappedPosition).rgb;
    vec4 radianceAndSamples = texture(uRadiance, mappedPosition);
    photon.radiance = radianceAndSamples.rgb;
    photon.samples = uint(radianceAndSamples.w + 0.5);

    oPosition = vec4(0);
    oDirection = vec4(0);
    oTransmittance = vec4(0);
    oRadiance = vec4(photon.radiance + 0.01, 1);
    // oRadiance = vec4(radianceAndSamples.r + 0.01, mappedPosition, 1);
    // oRadiance = vec4(radianceAndSamples.r + 0.01, 0.2, 0.2, 1);
}

// #part /glsl/shaders/renderers/FOVEATED/render/vertex

#version 300 es

precision mediump float;
precision mediump sampler2D;

uniform sampler2D uRenderPosition;

out vec2 vPosition;

void main() {
    // ivec2 texSize = textureSize(uRenderPosition, 0);
    // int y = gl_VertexID / texSize.x;
    // int x = gl_VertexID % texSize.x;
    // vec2 renderPosition = texelFetch(uRenderPosition, ivec2(x, y), 0).xy;

    // vPosition = renderPosition * 0.5 + 0.5;

    // gl_Position = vec4(renderPosition, 0, 1);
    // gl_PointSize = 2.0;


    ivec2 texSize = textureSize(uRenderPosition, 0);
    float y = float(gl_VertexID / texSize.x) / float(texSize.y);
    float x = float(gl_VertexID % texSize.x) / float(texSize.x);
    vec2 renderPosition = texture(uRenderPosition, vec2(x, y)).xy;

    vPosition = renderPosition * 0.5 + 0.5;

    gl_Position = vec4(renderPosition, 0, 1);
    gl_PointSize = 2.0;
}

// #part /glsl/shaders/renderers/FOVEATED/render/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;

uniform sampler2D uColor;

in vec2 vPosition;

out vec4 oColor;

void main() {
    oColor = vec4(texture(uColor, vPosition).rgb, 1);
}

// #part /glsl/shaders/renderers/FOVEATED/reset/vertex

#version 300 es

const vec2 vertices[] = vec2[](
    vec2(-1, -1),
    vec2( 3, -1),
    vec2(-1,  3)
);

out vec2 vPosition;

void main() {
    vec2 position = vertices[gl_VertexID];
    vPosition = position;
    gl_Position = vec4(position, 0, 1);
}

// #part /glsl/shaders/renderers/FOVEATED/reset/fragment

#version 300 es
precision mediump float;

// #link /glsl/mixins/Photon
@Photon
// #link /glsl/mixins/intersectCube
@intersectCube

@constants
@random/hash/pcg
@random/hash/squashlinear
@random/distribution/uniformdivision
@random/distribution/square
@random/distribution/disk
@random/distribution/sphere
@random/distribution/exponential

@unprojectRand

uniform mat4 uMvpInverseMatrix;
uniform vec2 uInverseResolution;
uniform float uRandSeed;
uniform float uBlur;

in vec2 vPosition;

layout (location = 0) out vec4 oPosition;
layout (location = 1) out vec4 oDirection;
layout (location = 2) out vec4 oTransmittance;
layout (location = 3) out vec4 oRadiance;
layout (location = 4) out vec2 oPositionRender;

void main() {
    Photon photon;
    vec3 from, to;
    uint state = hash(uvec3(floatBitsToUint(vPosition.x), floatBitsToUint(vPosition.y), floatBitsToUint(uRandSeed)));
    unprojectRand(state, vPosition, uMvpInverseMatrix, uInverseResolution, uBlur, from, to);
    photon.direction = normalize(to - from);
    vec2 tbounds = max(intersectCube(from, photon.direction), 0.0);
    photon.position = from + tbounds.x * photon.direction;
    photon.transmittance = vec3(1);
    photon.radiance = vec3(1);
    photon.bounces = 0u;
    photon.samples = 0u;
    oPosition = vec4(photon.position, 0);
    oDirection = vec4(photon.direction, float(photon.bounces));
    oTransmittance = vec4(photon.transmittance, 0);
    // oRadiance = vec4(photon.radiance, float(photon.samples));
    oRadiance = vec4(0, 0, 0, 0);
    oPositionRender = vec2(0);
}


// #part /glsl/shaders/renderers/FOVEATED/resetRender/vertex

#version 300 es

const vec2 vertices[] = vec2[](
    vec2(-1, -1),
    vec2( 3, -1),
    vec2(-1,  3)
);

out vec2 vPosition;

void main() {
    vec2 position = vertices[gl_VertexID];
    vPosition = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0, 1);
}

// #part /glsl/shaders/renderers/FOVEATED/resetRender/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;

uniform sampler2D uEnvironment;

in vec2 vPosition;

out vec4 oColor;

void main() {
    // vec3 env = texture(uEnvironment, vPosition).rgb;
    // oColor = vec4(env, 1);
    oColor = vec4(vec3(0), 1);
}