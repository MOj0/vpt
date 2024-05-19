import { mat4 } from '../../lib/gl-matrix-module.js';

import { WebGL } from '../WebGL.js';
import { AbstractRenderer } from './AbstractRenderer.js';

import { PerspectiveCamera } from '../PerspectiveCamera.js';

const [SHADERS, MIXINS] = await Promise.all([
    'shaders.json',
    'mixins.json',
].map(url => fetch(url).then(response => response.json())));

export class BasicRenderer extends AbstractRenderer {

    constructor(gl, volume, camera, environmentTexture, options = {}) {
        super(gl, volume, camera, environmentTexture, options);

        this._programs = WebGL.buildPrograms(this._gl, SHADERS.renderers.BASIC, MIXINS);

        this._points = [];

        // this.quadTreeTest();
    }

    destroy() {
        const gl = this._gl;
        Object.keys(this._programs).forEach(programName => {
            gl.deleteProgram(this._programs[programName].program);
        });

        super.destroy();
    }

    _generateFrame() {
        const gl = this._gl;

        const { program, uniforms } = this._programs.generate;
        gl.useProgram(program);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_3D, this._volume.getTexture());
        gl.uniform1i(uniforms.uVolume, 0);

        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, this._transferFunction);
        gl.uniform1i(uniforms.uTransferFunction, 1);

        gl.uniform1f(uniforms.uStepSize, 1 / this.steps);
        gl.uniform1f(uniforms.uOffset, Math.random());

        const centerMatrix = mat4.fromTranslation(mat4.create(), [-0.5, -0.5, -0.5]);
        const modelMatrix = this._volumeTransform.globalMatrix;
        const viewMatrix = this._camera.transform.inverseGlobalMatrix;
        const projectionMatrix = this._camera.getComponent(PerspectiveCamera).projectionMatrix;

        const matrix = mat4.create();
        mat4.multiply(matrix, centerMatrix, matrix);
        mat4.multiply(matrix, modelMatrix, matrix);
        mat4.multiply(matrix, viewMatrix, matrix);
        mat4.multiply(matrix, projectionMatrix, matrix);
        mat4.invert(matrix, matrix);
        gl.uniformMatrix4fv(uniforms.uMvpInverseMatrix, false, matrix);

        gl.drawArrays(gl.TRIANGLES, 0, 3);
    }


    _integrateFrame() {
        const gl = this._gl;

        const { program, uniforms } = this._programs.integrate;
        gl.useProgram(program);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, this._frameBuffer.getAttachments().color[0]);
        gl.uniform1i(uniforms.uFrame, 0);

        gl.drawBuffers([
            gl.COLOR_ATTACHMENT0,
            gl.COLOR_ATTACHMENT1,
        ]);

        gl.readBuffer(gl.COLOR_ATTACHMENT1);
        const positionData = new Float32Array(this._resolution * this._resolution * 2);
        gl.readPixels(0, 0, this._resolution, this._resolution, gl.RG, gl.FLOAT, positionData);
        this._points = positionData;

        gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    _renderFrame() {
        const gl = this._gl;

        const { program, uniforms, attributes } = this._programs.render;
        gl.useProgram(program);

        // Get attribute location
        const pointsAttribLocation = attributes.aPosition;
        gl.enableVertexAttribArray(pointsAttribLocation);
        // const points = new Float32Array([-0.9, 0, 0, 0.9, 0.9, 0]);
        const points = this._points;
        const nPoints = points.length / 2;
        // console.log(nPoints, points);
        const pointsBuffer = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, pointsBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, points, gl.STATIC_DRAW);
        // Bind the buffer and set attribute pointer
        gl.vertexAttribPointer(pointsAttribLocation, 2, gl.FLOAT, false, 0, 0);
        //

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[0]);
        gl.uniform1i(uniforms.uColor, 0);

        gl.drawArrays(gl.POINTS, 0, nPoints);
    }

    _resetFrame() {
        const gl = this._gl;

        const { program, uniforms } = this._programs.reset;
        gl.useProgram(program);

        gl.drawBuffers([
            gl.COLOR_ATTACHMENT0,
            gl.COLOR_ATTACHMENT1,
        ]);

        gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    quadTreeTest() {
        const MAX_LEVELS = 3;
        const MAX_NODES = 1 + 4 + 16;
        const quadTree = Array(MAX_NODES).fill(0.0);

        initializeQuadTree(10);

        function startIndexReverseLevel(negLevel) {
            var s = 0.0;
            for (var i = 0; i < MAX_LEVELS - negLevel; i++) {
                s += Math.pow(4.0, i);
            }
            return Math.floor(s);
        }

        function sideCount() {
            return Math.floor(Math.sqrt(Math.pow(4.0, (MAX_LEVELS - 1))));
        }


        function initializeQuadTree(sampleAccuracy) {
            var index = startIndexReverseLevel(1);
            const nSide = sideCount();
            const halfSide = Math.floor(nSide / 2);
            const nQuadAreas = Math.floor(nSide * nSide / 4);

            const topLeftX = -1.0;
            const topLeftY = 1.0;
            const deltaX = 2.0 / nSide;
            const deltaY = -2.0 / nSide;

            for (var i = 0; i < nQuadAreas; i++) {
                var initX = i % halfSide;
                var initY = Math.floor(i / halfSide);
                var xIdx = initX * 2;
                var yIdx = initY * 2;
                for (var j = 0; j < 4; j++) {
                    var xOffset = j % 2
                    var yOffset = Math.floor(j / 2);
                    const finalIdxX = xIdx + xOffset;
                    const finalIdxY = yIdx + yOffset;
                    const posX = topLeftX + finalIdxX * deltaX;
                    const posY = topLeftY + finalIdxY * deltaY;

                    var sumIntensity = 0.0;
                    for (var y = 0; y < sampleAccuracy; y++) {
                        for (var x = 0; x < sampleAccuracy; x++) {
                            const offsetX = (x / sampleAccuracy) * deltaX;
                            const offsetY = (y / sampleAccuracy) * deltaY;
                            const finalPosX = posX + offsetX;
                            const finalPosY = posY + offsetY;

                            if (finalPosX > 0.8 && finalPosY < -0.8) {
                                sumIntensity += 1.0;
                            } else {
                                sumIntensity += 0.1;
                            }
                            // sumIntensity += 1.0;
                        }
                    }

                    quadTree[index] = sumIntensity;
                    index++;
                }
            }

            for (var reverseLevel = 2; reverseLevel <= MAX_LEVELS; reverseLevel++) {
                const startIdx = startIndexReverseLevel(reverseLevel);
                const nQuads = Math.floor(Math.pow(4.0, MAX_LEVELS - reverseLevel));

                for (var j = 0; j < nQuads; j++) {
                    const nodeIdx = startIdx + j;

                    var sumIntensity = 0.0;
                    for (var k = 1; k <= 4; k++) {
                        sumIntensity += quadTree[nodeIdx * 4 + k];
                    }

                    quadTree[nodeIdx] = sumIntensity;
                }
            }
        }

        function getNodeImportance(nodeIndex) {
            var i1 = quadTree[4 * nodeIndex + 1];
            var i2 = quadTree[4 * nodeIndex + 2];
            var i3 = quadTree[4 * nodeIndex + 3];
            var i4 = quadTree[4 * nodeIndex + 4];
            var sum = i1 + i2 + i3 + i4;

            if (abs(sum) < 0.001) {
                return vec4(0.25);
            }

            return vec4(i1 / sum, i2 / sum, i3 / sum, i4 / sum);
        }

        function getRegion(regionImportance, random) {
            var cumulativeProbability = 0.0;

            for (var i = 0; i < 4; i++) {
                cumulativeProbability += regionImportance[i];
                if (random <= cumulativeProbability) {
                    return i;
                }
            }

            return 0; // Unreachable...
        }
    }

    _getFrameBufferSpec() {
        const gl = this._gl;
        return [{
            width: this._resolution,
            height: this._resolution,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            format: gl.RED,
            iformat: gl.R8,
            type: gl.UNSIGNED_BYTE,
        }];
    }

    _getAccumulationBufferSpec() {
        const gl = this._gl;
        const colorBufferSpec = {
            width: this._resolution,
            height: this._resolution,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            format: gl.RGBA,
            iformat: gl.RGBA32F,
            type: gl.FLOAT,
        };

        const positionBufferSpec = {
            width: this._resolution,
            height: this._resolution,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            format: gl.RG,
            iformat: gl.RG32F,
            type: gl.FLOAT,
        };

        return [
            colorBufferSpec,
            positionBufferSpec,
        ];
    }

    _getRenderBufferSpec() {
        const gl = this._gl;
        return [{
            width: this._resolution,
            height: this._resolution,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            wrapS: gl.CLAMP_TO_EDGE,
            wrapT: gl.CLAMP_TO_EDGE,
            format: gl.RGBA,
            iformat: gl.RGBA16F,
            type: gl.FLOAT,
        }];
    }
}