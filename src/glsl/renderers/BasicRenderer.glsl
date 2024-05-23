// #part /glsl/shaders/renderers/BASIC/generate/vertex

#version 300 es

uniform mat4 uMvpInverseMatrix;

out vec3 vRayFrom;
out vec3 vRayTo;

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
    gl_Position = vec4(position, 0, 1);
}

// #part /glsl/shaders/renderers/BASIC/generate/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;
precision mediump sampler3D;

uniform sampler3D uVolume;
uniform sampler2D uTransferFunction;
uniform float uStepSize;
uniform float uOffset;

in vec3 vRayFrom;
in vec3 vRayTo;

out float oColor;

// #link /glsl/mixins/intersectCube
@intersectCube

vec4 sampleVolumeColor(vec3 position) {
    vec2 volumeSample = texture(uVolume, position).rg;
    vec4 transferSample = texture(uTransferFunction, volumeSample);
    return transferSample;
}

void main() {
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

// #part /glsl/shaders/renderers/BASIC/integrate/vertex

#version 300 es

precision mediump float;
precision mediump sampler2D;

@constants
@random/hash/pcg
@random/hash/squashlinear
@random/distribution/uniformcast
@random/distribution/exponential

uniform int uLen;
uniform float uRandSeed;

out vec2 vPosition;
out vec2 vRandomPosition;

void main() {
    ivec2 gridSize = ivec2(uLen);
    float y = float(gl_VertexID / gridSize.x) / float(gridSize.y);
    float x = float(gl_VertexID % gridSize.x) / float(gridSize.x);
    vec2 position = vec2(x, y) * 2.0 - 1.0;

    vPosition = position * 0.5 + 0.5;

    uint state = hash(uvec3(floatBitsToUint(x), floatBitsToUint(y), floatBitsToUint(uRandSeed)));
    float randX = float(random_uniform(state));
    float randY = float(random_uniform(state));
    vRandomPosition = vec2(randX, randY) * 0.7 + 0.15;

    gl_Position = vec4(position, 0, 1);
}

// #part /glsl/shaders/renderers/BASIC/integrate/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;

uniform float uRandSeed2;

@constants
@random/hash/pcg
@random/hash/squashlinear
@random/distribution/uniformcast
@random/distribution/exponential

layout (location = 0) out vec4 oColor;
layout (location = 1) out vec4 oPositionNormalized;

in vec2 vPosition;
in vec2 vRandomPosition;

void main(){
    uint state = hash(uvec3(floatBitsToUint(vPosition.x), floatBitsToUint(vPosition.y), floatBitsToUint(uRandSeed2)));
    float randX = float(random_uniform(state));
    float randY = float(random_uniform(state));

    oColor = vec4(randX, randY, 0, 1);
    oPositionNormalized = vec4(vRandomPosition, 0, 1);
}

// #part /glsl/shaders/renderers/BASIC/render/vertex

#version 300 es

precision mediump float;
precision mediump sampler2D;

uniform sampler2D uColor;
uniform sampler2D uRandomPositionNormalized;

out vec2 vPosition;

void main() {
    ivec2 texSize = textureSize(uColor, 0);
    float y = float(gl_VertexID / texSize.x) / float(texSize.y);
    float x = float(gl_VertexID % texSize.x) / float(texSize.x);

    vec2 positionNormalized = vec2(x, y);

    vec4 uRandomPositionNormalized = texture(uRandomPositionNormalized, positionNormalized);

    vPosition = positionNormalized;

    vec2 gridPosition = uRandomPositionNormalized.xy * 2.0 - 1.0;

    gl_Position = vec4(gridPosition, 0, 1);
    gl_PointSize = 1.0;
}

// #part /glsl/shaders/renderers/BASIC/render/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;

uniform sampler2D uColor;

in vec2 vPosition;

out vec4 oColor;

void main(){
    oColor = texture(uColor, vPosition);
}

// #part /glsl/shaders/renderers/BASIC/reset/vertex

#version 300 es

const vec2 vertices[] = vec2[](
    vec2(-1, -1),
    vec2( 3, -1),
    vec2(-1,  3)
);

void main() {
    vec2 position = vertices[gl_VertexID];
    gl_Position = vec4(position, 0, 1);
}

// #part /glsl/shaders/renderers/BASIC/reset/fragment

#version 300 es
precision mediump float;

layout (location = 0) out vec4 oColor;
layout (location = 1) out vec2 oPosition;

void main() {
    oColor = vec4(0.0);
    oPosition = vec2(0.0);
}