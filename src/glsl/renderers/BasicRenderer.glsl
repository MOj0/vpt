// #part /glsl/shaders/renderers/BASIC/generate/vertex

#version 300 es

// const vec2 vertices[] = vec2[](
//     vec2(-1, -1),
//     vec2( 3, -1),
//     vec2(-1,  3)
// );

const vec2 vertices[] = vec2[](
    vec2( -0.8, -0.8),
    vec2(0, 0.8),
    vec2(0.8,  -0.8)
);

out vec2 vPosition;

void main() {
    vec2 position = vertices[gl_VertexID];
    // vPosition = position * 0.5 + 0.5;
    vPosition = position;
    gl_Position = vec4(position, 0, 1);
}

// #part /glsl/shaders/renderers/BASIC/generate/fragment

#version 300 es
precision mediump float;

in vec2 vPosition;

out vec2 oPosition;

void main() {
    oPosition = vPosition;
}

// #part /glsl/shaders/renderers/BASIC/integrate/vertex

#version 300 es

const vec2 vertices[] = vec2[](
    vec2( -0.8, -0.8),
    vec2(0, 0.8),
    vec2(0.8,  -0.8)
);

out vec2 vPosition;

void main() {
    vec2 position = vertices[gl_VertexID];
    vPosition = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0, 1);
}

// #part /glsl/shaders/renderers/BASIC/integrate/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;

// #link /glsl/mixins/Photon
@Photon

in vec2 vPosition;

layout (location = 0) out vec4 oColor;

void main() {
    Photon photon;
    photon.radiance = vec3(0.0, vPosition);
    oColor = vec4(photon.radiance, 1.0);
}

// #part /glsl/shaders/renderers/BASIC/render/vertex

#version 300 es

const vec2 vertices[] = vec2[](
    vec2(-1, -1),
    vec2( 3, -1),
    vec2(-1,  3)
);

in vec2 aPosition;

out vec2 vPosition;

void main() {
    // vec2 position = vertices[gl_VertexID];
    vec2 position = aPosition;

    vPosition = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0, 1);
    gl_PointSize = 5.0;
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

out float oColor;

void main() {
    oColor = 0.0;
}