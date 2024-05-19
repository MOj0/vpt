// #part /glsl/shaders/renderers/FOVEATED/integrate/vertex

#version 300 es

// #link /glsl/mixins/rand
@rand

#define MAX_LEVELS 3 // Maximum levels of the QuadTree
#define MAX_NODES 1 + 4 + 16 // TODO: Remember to update this when MAX_LEVELS is changed

float quadTree[MAX_NODES];


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
                    float intensity = 1.0;
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

    gl_Position = vec4(position, 0, 1);
    gl_PointSize = 2.0;
}

// #part /glsl/shaders/renderers/FOVEATED/integrate/fragment

#version 300 es
precision mediump float;

out float oColor;

void main() {
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