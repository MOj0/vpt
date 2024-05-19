// TODO:
// Buffer fotonov: F1, F2, .. -> v bufferju so tudi pozicije pikslov, tako jih lahko izrises
// lastnosti fotonov iz textur -> buffer

// TODO: (OPTIMIZATION): QuadTree zamenjaj z MipMap-om; za MipMap NE uporabi `gl.generateMipMap()` ampak ga zgeneriraj sam (zdruzi po 4 sosdenje piksle in propagiraj navzgor)


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

// #part /glsl/shaders/renderers/BASIC/integrate/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;

#define MAX_LEVELS 4 // Maximum levels of the QuadTree
#define MAX_NODES 1 + 4 + 16 + 64  // TODO: Remember to update this when MAX_LEVELS is changed

uniform sampler2D uFrame;

in vec2 vPosition;

layout (location = 0) out vec4 oColor;
layout (location = 1) out vec2 oPosition;

float quadTree[MAX_NODES];

// #link /glsl/mixins/rand
@rand

int startIndexReverseLevel(int negLevel){
    float s = 0.0;
    for(int i = 0; i < MAX_LEVELS - negLevel; i++){
        s += pow(4.0, float(i));
    }
    return int(s);
}

int sideCount(){
    return int(sqrt(pow(4.0, float(MAX_LEVELS - 1))));
}

void initializeQuadTree(int sampleAccuracy) {
    int index = startIndexReverseLevel(1);
    int nSide = sideCount();
    int halfSide = int(nSide / 2);
    int nQuadAreas = int(nSide * nSide / 4);

    vec2 topLeft = vec2(-1.0, 1.0);
    vec2 delta = vec2(2.0, -2.0) / float(nSide);

    for (int i = 0; i < nQuadAreas; i++) {
        int initX = i % halfSide;
        int initY = int(i / halfSide);
        int xIdx = initX * 2;
        int yIdx = initY * 2;
        for (int j = 0; j < 4; j++) {
            int xOffset = j % 2;
            int yOffset = int(j / 2);
            vec2 finalIdx = vec2(float(xIdx + xOffset), float(yIdx + yOffset));
            vec2 pos = topLeft + finalIdx * delta;

            float sumIntensity = 0.0;
            for (int y = 0; y < sampleAccuracy; y++) {
                for (int x = 0; x < sampleAccuracy; x++) {
                    vec2 offset = vec2(x, y) / float(sampleAccuracy) * delta;
                    // NOTE: We have to normalize position, since we are sampling a texture
                    vec2 finalPos = (pos + offset) * 0.5 + 0.5;
                    float intensity = texture(uFrame, finalPos).r;

                    sumIntensity += intensity;
                }
            }

            quadTree[index] = sumIntensity;
            index++;
        }
    }

    for (int reverseLevel = 2; reverseLevel <= MAX_LEVELS; reverseLevel++) {
        int startIdx = startIndexReverseLevel(reverseLevel);
        int nQuads = int(pow(4.0, float(MAX_LEVELS - reverseLevel)));

        for (int j = 0; j < nQuads; j++) {
            int nodeIdx = startIdx + j;

            float sumIntensity = 0.0;
            for (int k = 1; k <= 4; k++) {
                sumIntensity += quadTree[nodeIdx * 4 + k];
            }

            quadTree[nodeIdx] = sumIntensity;
        }
    }
}

vec4 getNodeImportance(int nodeIndex){
    float i1 = quadTree[4 * nodeIndex + 1];
    float i2 = quadTree[4 * nodeIndex + 2];
    float i3 = quadTree[4 * nodeIndex + 3];
    float i4 = quadTree[4 * nodeIndex + 4];
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
    // TODO: This is extremely inefficient, it should be a texture (mipmap)
    // TODO: Increase MAX_LEVELS (once we have mipmap)
    initializeQuadTree(10);

    int currNodeIdx = 0;
    vec2 position = vec2(0.0);

    for (int depth = 1; depth <= MAX_LEVELS; depth++) {
        float random = fract(cos(float(vPosition.x + vPosition.y) + float(depth) * 0.123) * 43758.5453123);

        vec4 regionImportance = getNodeImportance(currNodeIdx);
        int region = getRegion(regionImportance, random);

        if (region == 0) {
            // Top left quadrant
            position = position + vec2(-1.0, 1.0) * pow(0.5, float(depth));
            currNodeIdx = currNodeIdx * 4 + 1;
        }
        else if (region == 1) {
            // Top right quadrant
            position = position + vec2(1.0, 1.0) * pow(0.5, float(depth));
            currNodeIdx = currNodeIdx * 4 + 2;
        }
        else if (region == 2) {
            // Bottom left quadrant
            position = position + vec2(-1.0, -1.0) * pow(0.5, float(depth));
            currNodeIdx = currNodeIdx * 4 + 3;
        } else {
            // Bottom right quadrant
            position = position + vec2(1.0, -1.0) * pow(0.5, float(depth));
            currNodeIdx = currNodeIdx * 4 + 4;
        }
    }

    vec2 rand_dir = rand(vec2(float(vPosition.x + vPosition.y), float(MAX_LEVELS))) * vec2(2.0) - vec2(1.0);
    position = position + rand_dir * pow(0.5, float(MAX_LEVELS));

    oColor = vec4(1.0);
    oPosition = position;
}

// #part /glsl/shaders/renderers/BASIC/render/vertex

#version 300 es

in vec2 aPosition;

out vec2 vPosition;

void main() {
    vec2 position = aPosition;

    vPosition = position * 0.5 + 0.5;
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