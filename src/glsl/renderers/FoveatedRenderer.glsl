// #part /glsl/shaders/renderers/FOVEATED/generate/vertex

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
    // vec3 rayDirection = vRayTo - vRayFrom;
    // vec2 tbounds = max(intersectCube(vRayFrom, rayDirection), 0.0);
    // if (tbounds.x >= tbounds.y) {
    //     oColor = 0.0;
    // } else {
    //     vec3 from = mix(vRayFrom, vRayTo, tbounds.x);
    //     vec3 to = mix(vRayFrom, vRayTo, tbounds.y);

    //     float t = 0.0;
    //     float val = 0.0;
    //     float offset = uOffset;
    //     vec3 pos;
    //     do {
    //         pos = mix(from, to, offset);
    //         val = max(sampleVolumeColor(pos).a, val);
    //         t += uStepSize;
    //         offset = mod(offset + uStepSize, 1.0);
    //     } while (t < 1.0);
    //     oColor = val;
    // }
    oColor = 1.0;
}

// #part /glsl/shaders/renderers/FOVEATED/integrate/vertex

#version 300 es

uniform mat4 uMvpInverseMatrix;
uniform sampler2D uFrame;

out vec3 vRayFrom;
out vec3 vRayTo;

// #link /glsl/mixins/rand
@rand

#define MAX_LEVELS 4 // Maximum levels of the QuadTree
#define MAX_NODES 1 + 4 + 16 + 64 // TODO: Remember to update this when MAX_LEVELS is changed

float quadTree[MAX_NODES];

// #link /glsl/mixins/unproject
@unproject


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
    vec2 topLeft = vec2(-1.0, 1.0);
    vec2 delta = vec2(2.0, -2.0) / float(nSide);

    for(int i = 0; i < nSide; i++){
        for(int j = 0; j < nSide; j++){
            vec2 pos = topLeft + vec2(delta.x * float(j), delta.y * float(i));

            float sumIntensity = 0.0;
            for(int y = 0; y < sampleAccuracy; y++){
                for(int x = 0; x < sampleAccuracy; x++){
                    vec2 dir = vec2(float(x), -float(y)) / float(sampleAccuracy);
                    float intensity = texture(uFrame, pos + dir).r;
                    sumIntensity += intensity;
                }
            }

            quadTree[index] = sumIntensity;
            index++;
        }
    }

    for(int i = MAX_LEVELS-2; i > 0; i--){
        int startIdx = startIndexReverseLevel(i);
        int nQuads = int(pow(4.0, float(i)));

        for(int j = 0; j < nQuads; j++){
            int nodeIdx = startIdx + j;

            float sumIntensity = 0.0;
            for(int k = 1; k <= 4; k++){
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
    initializeQuadTree(10);

    int currNodeIdx = 0;
    vec2 position = vec2(0.0);

    for (int depth = 1; depth <= MAX_LEVELS; depth++) {
        float random = fract(cos(float(gl_VertexID) + float(depth) * 0.123) * 43758.5453123);

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

    vec2 rand_dir = rand(vec2(float(gl_VertexID), float(MAX_LEVELS))) * vec2(2.0) - vec2(1.0);
    position = position + rand_dir * pow(0.5, float(MAX_LEVELS));
    unproject(position, uMvpInverseMatrix, vRayFrom, vRayTo);

    gl_Position = vec4(position, 0, 1);
    gl_PointSize = 2.0;
}

// #part /glsl/shaders/renderers/FOVEATED/integrate/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;
precision mediump sampler3D;

uniform mat4 uMvpInverseMatrix;

uniform sampler3D uVolume;
uniform sampler2D uTransferFunction;

uniform float uStepSize;
uniform float uOffset;

// TODO: What to do with these?
// uniform sampler2D uAccumulator;
// uniform sampler2D uFrame;

out float oColor;

// #link /glsl/mixins/rand
@rand

vec4 sampleVolumeColor(vec3 position) {
    vec2 volumeSample = texture(uVolume, position).rg;
    vec4 transferSample = texture(uTransferFunction, volumeSample);
    return transferSample;
}

void main() {
    // vec3 vRayFrom;
    // vec3 vRayTo;
    // vec2 position = vec2(0.0);
    // initializeQuadTree();

    // int currNodeIdx = 0;

    // for (int depth = 0; depth < MAX_LEVELS; depth++) {
    //     float random = fract(cos(float(depth * 2) + float(depth) * 0.123) * 43758.5453123);

    //     vec4 regionImportance = getNodeImportance(currNodeIdx);
    //     int region = getRegion(regionImportance, random);

    //     if (region == 0) {
    //         // Top left quadrant
    //         position = position + vec2(-1.0, 1.0) * pow(0.5, float(depth + 1));
    //         currNodeIdx = currNodeIdx * 4 + 1;
    //     } 
    //     else if (region == 1) {
    //         // Top right quadrant
    //         position = position + vec2(1.0, 1.0) * pow(0.5, float(depth + 1));
    //         currNodeIdx = currNodeIdx * 4 + 2;
    //     } 
    //     else if (region == 2) {
    //         // Bottom left quadrant
    //         position = position + vec2(-1.0, -1.0) * pow(0.5, float(depth + 1));
    //         currNodeIdx = currNodeIdx * 4 + 3;
    //     } else {
    //         // Bottom right quadrant
    //         position = position + vec2(1.0, -1.0) * pow(0.5, float(depth + 1));
    //         currNodeIdx = currNodeIdx * 4 + 4;
    //     }
    // }

    // vec2 rand_dir = rand(vec2(0.2, float(MAX_LEVELS))) * vec2(2.0) - vec2(1.0);
    // position = position + rand_dir * pow(0.5, float(MAX_LEVELS));

    // unproject(position, uMvpInverseMatrix, vRayFrom, vRayTo);

    // gl_Position = vec4(position, 0, 1);



    // vec3 rayDirection = vRayTo - vRayFrom;
    // vec2 tbounds = max(intersectCube(vRayFrom, rayDirection), 0.0);
    // if (tbounds.x >= tbounds.y) {
    //     oColor = 0.0;
    // } else {
    //     vec3 from = mix(vRayFrom, vRayTo, tbounds.x);
    //     vec3 to = mix(vRayFrom, vRayTo, tbounds.y);

    //     float t = 0.0;
    //     float val = 0.0;
    //     float offset = uOffset;
    //     vec3 pos;
    //     do {
    //         pos = mix(from, to, offset);
    //         val = max(sampleVolumeColor(pos).a, val);
    //         t += uStepSize;
    //         offset = mod(offset + uStepSize, 1.0);
    //     } while (t < 1.0);
    //     oColor = val;
    // }
    

    oColor = 1.0;
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

void main(){
    float acc = texture(uAccumulator, vPosition).r;
    oColor = vec4(vec3(acc), 1);
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