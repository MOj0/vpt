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

out vec4 oColor;

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

out vec2 vPosition;

void main() {
    vec2 position = vertices[gl_VertexID];
    vPosition = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0, 1);
}

// #part /glsl/shaders/renderers/BASIC/render/fragment

#version 300 es
precision mediump float;
precision mediump sampler2D;

uniform sampler2D uColor;

in vec2 vPosition;

out vec4 oColor;

void main(){
    // oColor = vec4(0.0, vPosition, 1); // Cool effect :D
    oColor = vec4(texture(uColor, vPosition).rgb, 1);
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