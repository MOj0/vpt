// #part /glsl/shaders/renderers/FOVEATED/generate/vertex

#version 300 es

uniform mat4 uMvpInverseMatrix;

out vec3 vRayFrom;
out vec3 vRayTo;

// #link /glsl/mixins/unproject
@unproject

// #link /glsl/mixins/rand.glsl
@rand

// TODO:
// Buffer fotonov: F1, F2, .. -> v bufferju so tudi pozicije pikslov, tako jih lahko izrises
// drawPixels(gl.POINT)
// lastnosti fotonov iz textur -> buffer

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

// TODO: ...
// void main(){
//     // Generate random points within the [-1, 1] x [-1, 1] square
//     vec2 randomPoints = vec2(rand(gl_VertexID), rand(gl_VertexID + 1.0)) * 2.0 - 1.0;

        // // Unproject the random points to the near and far planes of the view frustum
        // vec3 rayFrom, rayTo;
        // unproject(randomPoints, uMvpInverseMatrix, rayFrom, rayTo);

        // // Output the ray endpoints
        // vRayFrom = rayFrom;
        // vRayTo = rayTo;

        // // Output the vertex position (for visualization if needed)
        // gl_Position = vec4(randomPoints, 0.0, 1.0);
// }

// #part /glsl/shaders/renderers/FOVEATED/generate/fragment

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
    // return texture(uVolume, position);
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

// #part /glsl/shaders/renderers/FOVEATED/integrate/vertex

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

// #part /glsl/shaders/renderers/FOVEATED/integrate/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;

uniform sampler2D uAccumulator;
uniform sampler2D uFrame;

in vec2 vPosition;

out float oColor;

void main() {
    float acc = texture(uAccumulator, vPosition).r;
    float frame = texture(uFrame, vPosition).r;
    oColor = max(acc, frame);
    // oColor = frame;
}

// #part /glsl/shaders/renderers/FOVEATED/render/vertex

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

// #part /glsl/shaders/renderers/FOVEATED/render/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;

uniform sampler2D uAccumulator;

in vec2 vPosition;

out vec4 oColor;

vec3 rgb2yuv(vec3 rgb){
    const mat3 RGB2YUV = mat3(
        0.299, -0.14713,  0.615,
        0.587, -0.28886,  -0.51499,
        0.114, 0.436,     -0.10001
    );

    return RGB2YUV * rgb;
}

// void main() {
//     float acc = texture(uAccumulator, vPosition).r;
//     oColor = vec4(acc, acc, acc, 1);
// }

// Renders edges
void main(){
    vec4 acc = texture(uAccumulator, vPosition).rgba;
    vec3 yuv = rgb2yuv(acc.rgb);

    // oColor = acc;
    // oColor = vec4(vec3(yuv.x), 1.0);

    float Y = yuv.x;
    float U = yuv.y;
    float V = yuv.z;
    float combined_chroma_magnitude = sqrt(U*U + V*V);

    // Compute gradients using fininte differences
    float dx = dFdx(Y);
    float dy = dFdy(Y);
    float gradient_magnitude_LUM = sqrt(dx*dx + dy*dy);

    // Compute gradient of combined chroma magnitude using finite differences
    float dCombinedChromaMagnitude_dx = dFdx(combined_chroma_magnitude);
    float dCombinedChromaMagnitude_dy = dFdy(combined_chroma_magnitude);
    float gradient_magnitude_CHROMA = sqrt(dCombinedChromaMagnitude_dx*dCombinedChromaMagnitude_dx + dCombinedChromaMagnitude_dy*dCombinedChromaMagnitude_dy);

    // Determine importance based on gradient magnitude
    float threshold = 0.1;
    // float importance = step(threshold, gradient_magnitude_LUM);
    float importance = step(threshold, gradient_magnitude_CHROMA);
    
    // Output importance as grayscale value
    oColor = vec4(vec3(importance), 1.0);
}

// #part /glsl/shaders/renderers/FOVEATED/reset/vertex

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

// #part /glsl/shaders/renderers/FOVEATED/reset/fragment

#version 300 es
precision mediump float;

out float oColor;

void main() {
    oColor = 0.0;
}