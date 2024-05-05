// #part /glsl/shaders/renderers/FOVEATED/generate/vertex

#version 300 es

uniform mat4 uMvpInverseMatrix;

out vec3 vRayFrom;
out vec3 vRayTo;

// #link /glsl/mixins/unproject
@unproject

// TODO:
// Buffer fotonov: F1, F2, .. -> v bufferju so tudi pozicije pikslov, tako jih lahko izrises
// lastnosti fotonov iz textur -> buffer

const vec2 vertices[] = vec2[](
    vec2(-1, -1),
    vec2( 3, -1),
    vec2(-1,  3)
);

vec2 rand(vec2 seed) {
    const mat2 M = mat2
    (
        23.14069263277926, 2.665144142690225,
        12.98987893203892, 78.23376739376591
    );
    const vec2 D = vec2
    (
        1235.6789,
        4378.5453
    );
    vec2 dotted = M * seed;
    vec2 mapped = vec2(cos(dotted.x), sin(dotted.y));
    return fract(mapped * D);
}

#define MAX_LEVELS 3 // Maximum levels of the QuadTree
#define MAX_NODES 1 + 4 + 16 // TODO: Remember to update this when MAX_LEVELS is changed

// Structure to represent a QuadTree node
struct QuadTreeNode {
    vec2 minPosition;
    vec2 maxPosition;
    float importance;
    int childIndices[4]; // Indices of child nodes in the QuadTree buffer
};

QuadTreeNode nodes[MAX_NODES];

void buildQuadTree(int level, int nodeIndex, float importance, vec2 minPos, vec2 maxPos){
    // Stack to simulate recursion
    float stack[MAX_NODES * 6];
    int stackIndex = 0;
    
    // Push initial parameters to the stack
    stack[stackIndex++] = float(level);
    stack[stackIndex++] = float(nodeIndex);
    stack[stackIndex++] = minPos.x;
    stack[stackIndex++] = minPos.y;
    stack[stackIndex++] = maxPos.x;
    stack[stackIndex++] = maxPos.y;

    // Simulate recursion using a while loop
    while (stackIndex > 0) {
        // Pop parameters from the stack
        maxPos.y = stack[--stackIndex];
        maxPos.x = stack[--stackIndex];
        minPos.y = stack[--stackIndex];
        minPos.x = stack[--stackIndex];
        nodeIndex = int(stack[--stackIndex]);
        level = int(stack[--stackIndex]);

        // Process current node
        nodes[nodeIndex] = QuadTreeNode(minPos, maxPos, importance, int[](
            nodeIndex * 4 + 1,
            nodeIndex * 4 + 2,
            nodeIndex * 4 + 3,
            nodeIndex * 4 + 4
        ));

        // If not at maximum level, push child parameters to the stack
        if (level < MAX_LEVELS){
            vec2 midPos = (minPos + maxPos) * 0.5;

            stack[stackIndex++] = float(level + 1);
            stack[stackIndex++] = float(nodeIndex * 4 + 1);
            stack[stackIndex++] = minPos.x;
            stack[stackIndex++] = midPos.y;
            stack[stackIndex++] = midPos.x;
            stack[stackIndex++] = maxPos.y;

            stack[stackIndex++] = float(level + 1);
            stack[stackIndex++] = float(nodeIndex * 4 + 2);
            stack[stackIndex++] = midPos.x;
            stack[stackIndex++] = midPos.y;
            stack[stackIndex++] = maxPos.x;
            stack[stackIndex++] = maxPos.y;

            stack[stackIndex++] = float(level + 1);
            stack[stackIndex++] = float(nodeIndex * 4 + 3);
            stack[stackIndex++] = midPos.x;
            stack[stackIndex++] = minPos.y;
            stack[stackIndex++] = maxPos.x;
            stack[stackIndex++] = midPos.y;

            stack[stackIndex++] = float(level + 1);
            stack[stackIndex++] = float(nodeIndex * 4 + 4);
            stack[stackIndex++] = minPos.x;
            stack[stackIndex++] = minPos.y;
            stack[stackIndex++] = midPos.x;
            stack[stackIndex++] = midPos.y;
        }
    }
}


void initializeQuadTree() {
    buildQuadTree(0, 0, 0.25, vec2(-1.0, -1.0), vec2(1.0, 1.0));
}

vec4 getNodeImportance(int nodeIndex){
    QuadTreeNode node = nodes[nodeIndex];

    float i1 = nodes[node.childIndices[0]].importance;
    float i2 = nodes[node.childIndices[1]].importance;
    float i3 = nodes[node.childIndices[2]].importance;
    float i4 = nodes[node.childIndices[3]].importance;
    float sum = i1 + i2 + i3 + i4;

    if (abs(sum) < 0.001) {
        return vec4(0.25);
    }

    return vec4(i1 / sum, i2 / sum, i3 / sum, i4 / sum);
}


int sampleProbabilityRegion(vec4 regionImportance, float random) {
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
    vec2 position = vec2(0.0);
    initializeQuadTree();

    int currNodeIdx = 0;

    for (int depth = 0; depth < MAX_LEVELS; depth++) {
        float random = fract(sin(float(gl_VertexID) + float(depth) * 0.123) * 43758.5453123);

        vec4 regionImportance = getNodeImportance(currNodeIdx);
        int region = sampleProbabilityRegion(regionImportance, random);

        if (region == 0) {
            // Top left quadrant
            position = position + vec2(-1.0, 1.0) * pow(0.5, float(depth + 1));
            currNodeIdx = currNodeIdx * 4 + 1;
        } 
        else if (region == 1) {
            // Top right quadrant
            position = position + vec2(1.0, 1.0) * pow(0.5, float(depth + 1));
            currNodeIdx = currNodeIdx * 4 + 2;
        } 
        else if (region == 2) {
            // Bottom left quadrant
            position = position + vec2(-1.0, -1.0) * pow(0.5, float(depth + 1));
            currNodeIdx = currNodeIdx * 4 + 3;
        } else {
            // Bottom right quadrant
            position = position + vec2(1.0, -1.0) * pow(0.5, float(depth + 1));
            currNodeIdx = currNodeIdx * 4 + 4;
        }
    }

    vec2 rand_dir = rand(vec2(float(gl_VertexID), float(MAX_LEVELS))) * vec2(2.0) - vec2(1.0);
    position = position + rand_dir * pow(0.5, float(MAX_LEVELS));

    unproject(position, uMvpInverseMatrix, vRayFrom, vRayTo);

    // Set the vertex position and point size
    gl_Position = vec4(position, 0, 1);
    gl_PointSize = 2.0;
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

// Renders MIP
void main() {
    float acc = texture(uAccumulator, vPosition).r;
    oColor = vec4(vec3(acc), 1);
}


// Renders importance
// void main(){
//     vec4 acc = texture(uAccumulator, vPosition).rgba;
//     vec3 yuv = rgb2yuv(acc.rgb);

//     // oColor = acc;
//     // oColor = vec4(vec3(yuv.x), 1.0);

//     float Y = yuv.x;
//     float U = yuv.y;
//     float V = yuv.z;
//     float combined_chroma_magnitude = sqrt(U*U + V*V);

//     // Compute gradients using fininte differences
//     float dx = dFdx(Y);
//     float dy = dFdy(Y);
//     float gradient_magnitude_LUM = sqrt(dx*dx + dy*dy);

//     // Compute gradient of combined chroma magnitude using finite differences
//     float dCombinedChromaMagnitude_dx = dFdx(combined_chroma_magnitude);
//     float dCombinedChromaMagnitude_dy = dFdy(combined_chroma_magnitude);
//     float gradient_magnitude_CHROMA = sqrt(dCombinedChromaMagnitude_dx*dCombinedChromaMagnitude_dx + dCombinedChromaMagnitude_dy*dCombinedChromaMagnitude_dy);

//     // Determine importance based on gradient magnitude
//     float threshold = 0.1;
//     // float importance = step(threshold, gradient_magnitude_LUM);
//     float importance = step(threshold, gradient_magnitude_CHROMA);
    
//     // Output importance as grayscale value
//     oColor = vec4(vec3(importance), 1.0);
// }



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