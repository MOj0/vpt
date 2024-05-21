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

uniform sampler2D uFrame;

out vec2 vPosition;

// #link /glsl/mixins/rand
@rand

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

void main() {
    ivec2 currPos = ivec2(0);

    for (int mipLevel = 8; mipLevel > 0; mipLevel--) {
        float random = fract(cos(float(gl_VertexID) + float(mipLevel) * 0.123) * 43758.5453123);
        vec4 regionImportance = getNodeImportance(currPos, mipLevel);
        int region = getRegion(regionImportance, random);

        if (region == 0) {
            // Top left quadrant
            currPos = 2 * currPos;
        }
        else if (region == 1) {
            // Top right quadrant
            currPos = 2 * (currPos + ivec2(1, 0));
        }
        else if (region == 2) {
            // Bottom left quadrant
            currPos = 2 * (currPos + ivec2(0, 1));
        } else {
            // Bottom right quadrant
            currPos = 2 * (currPos + ivec2(1, 1));
        }
    }

    // position: [0, 512] -> [-1, 1] (clip space)
    vec2 position = vec2(currPos - ivec2(256)) / 256.0;

    vPosition = position; // Send position to the fragment shader, which will write it to the texture

    // We have to compute the position in which we will render the pixel (the same way as we will do in the render/vertex shader)
    float y = float(100 * int(float(gl_VertexID) / 100.0)) / 100000.0;
    float x = float(gl_VertexID% 100) / 100.0;
    vec2 pos = vec2(x, y) * 2.0 - 1.0;
    gl_Position = vec4(pos, 0, 1);
}

// #part /glsl/shaders/renderers/BASIC/integrate/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;

in vec2 vPosition;

layout (location = 0) out vec4 oColor;
layout (location = 1) out vec2 oPosition;

void main() {
    oColor = vec4(1.0); // TODO: Compute actual color (MCM)
    oPosition = vPosition;
}

// #part /glsl/shaders/renderers/BASIC/render/vertex

#version 300 es

precision mediump float;
precision mediump sampler2D;

uniform sampler2D uPosition;

out vec2 vPosition;

void main() {
    float y = float(100 * int(float(gl_VertexID) / 100.0)) / 100000.0;
    float x = float(gl_VertexID% 100) / 100.0;
    vec2 pos = vec2(x, y);

    vec2 position = texture(uPosition, pos).xy;

    vPosition = pos;
    gl_Position = vec4(position, 0, 1);
    gl_PointSize = 2.0;
}

// #part /glsl/shaders/renderers/BASIC/render/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;

uniform sampler2D uColor;

in vec2 vPosition;

out vec4 oColor;

void main(){
    vec3 color = texture(uColor, vPosition).rgb;
    oColor = vec4(color, 1);
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

// NOTE: This does not really work, since renderer only renders pixels at the given POINTS (aPosition)
void main() {
    oColor = vec4(0.0);
    oPosition = vec2(0.0);
}