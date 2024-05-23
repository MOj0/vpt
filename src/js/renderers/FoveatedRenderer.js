import { mat4 } from '../../lib/gl-matrix-module.js';

import { WebGL } from '../WebGL.js';
import { AbstractRenderer } from './AbstractRenderer.js';

import { PerspectiveCamera } from '../PerspectiveCamera.js';

const [SHADERS, MIXINS] = await Promise.all([
    'shaders.json',
    'mixins.json',
].map(url => fetch(url).then(response => response.json())));

const BUFFER_SIZE = 512;
const GRID_SIZE = BUFFER_SIZE * 2;

export class FoveatedRenderer extends AbstractRenderer {

    constructor(gl, volume, camera, environmentTexture, options = {}) {
        super(gl, volume, camera, environmentTexture, options);

        this.registerProperties([
            {
                name: 'extinction',
                label: 'Extinction',
                type: 'spinner',
                value: 1,
                min: 0,
            },
            {
                name: 'anisotropy',
                label: 'Anisotropy',
                type: 'slider',
                value: 0,
                min: -1,
                max: 1,
            },
            {
                name: 'bounces',
                label: 'Max bounces',
                type: 'spinner',
                value: 8,
                min: 0,
            },
            {
                name: 'stepsMIP',
                label: 'StepsMip',
                type: 'spinner',
                value: 1,
                min: 0,
            },
            {
                name: 'stepsMCM',
                label: 'StepsMCM',
                type: 'spinner',
                value: 8,
                min: 0,
            },
            {
                name: 'transferFunction',
                label: 'Transfer function',
                type: 'transfer-function',
                value: new Uint8Array(256),
            },
        ]);

        this._rand1 = Math.random();
        this._rand2 = Math.random();

        this._programs = WebGL.buildPrograms(this._gl, SHADERS.renderers.FOVEATED, MIXINS);
    }

    destroy() {
        const gl = this._gl;
        Object.keys(this._programs).forEach(programName => {
            gl.deleteProgram(this._programs[programName].program);
        });

        super.destroy();
    }

    render() {
        this._frameBuffer.use();
        this._generateFrame();

        this._accumulationBuffer.use();
        this._integrateFrame();
        this._accumulationBuffer.swap();

        this._renderBuffer.use();
        this._renderFrame();
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

        gl.uniform1f(uniforms.uStepSize, 1 / this.stepsMIP);
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

        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[0]);
        gl.uniform1i(uniforms.uPosition, 1);

        gl.activeTexture(gl.TEXTURE2);
        gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[1]);
        gl.uniform1i(uniforms.uDirection, 2);

        gl.activeTexture(gl.TEXTURE3);
        gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[2]);
        gl.uniform1i(uniforms.uTransmittance, 3);

        gl.activeTexture(gl.TEXTURE4);
        gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[3]);
        gl.uniform1i(uniforms.uRadiance, 4);

        gl.activeTexture(gl.TEXTURE5);
        gl.bindTexture(gl.TEXTURE_3D, this._volume.getTexture());
        gl.uniform1i(uniforms.uVolume, 5);

        gl.activeTexture(gl.TEXTURE6);
        gl.bindTexture(gl.TEXTURE_2D, this._environmentTexture);
        gl.uniform1i(uniforms.uEnvironment, 6);

        gl.activeTexture(gl.TEXTURE7);
        gl.bindTexture(gl.TEXTURE_2D, this._transferFunction);
        gl.uniform1i(uniforms.uTransferFunction, 7);

        gl.uniform2f(uniforms.uInverseResolution, 1 / this._resolution, 1 / this._resolution);
        gl.uniform1f(uniforms.uBlur, 0);

        gl.uniform1f(uniforms.uExtinction, this.extinction);
        gl.uniform1f(uniforms.uAnisotropy, this.anisotropy);
        gl.uniform1ui(uniforms.uMaxBounces, this.bounces);
        gl.uniform1ui(uniforms.uSteps, this.stepsMCM);

        gl.uniform1f(uniforms.uRandSeed, this._rand1);
        gl.uniform1f(uniforms.uRandSeed2, this._rand2);

        gl.uniform1i(uniforms.uLen, GRID_SIZE);

        gl.drawBuffers([
            gl.COLOR_ATTACHMENT0,
            gl.COLOR_ATTACHMENT1,
            gl.COLOR_ATTACHMENT2,
            gl.COLOR_ATTACHMENT3,
            gl.COLOR_ATTACHMENT4,
        ]);

        gl.drawArrays(gl.POINTS, 0, GRID_SIZE * GRID_SIZE);

        // get the result
        // const results = new Float32Array(BUFFER_SIZE * BUFFER_SIZE * 4);
        // gl.readBuffer(gl.COLOR_ATTACHMENT1);
        // gl.readPixels(0, 0, BUFFER_SIZE, BUFFER_SIZE, gl.RGBA, gl.FLOAT, results);
        // // print the results
        // console.log(results);
        // console.log("\n");
    }

    _renderFrame() {
        const gl = this._gl;

        const { program, uniforms } = this._programs.render;
        gl.useProgram(program);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[3]);
        gl.uniform1i(uniforms.uColor, 0);

        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[4]);
        gl.uniform1i(uniforms.uRandomPositionNormalized, 1);

        gl.drawArrays(gl.POINTS, 0, BUFFER_SIZE * BUFFER_SIZE);
    }

    _resetFrame() {
        const gl = this._gl;

        const { program, uniforms } = this._programs.reset;
        gl.useProgram(program);

        gl.uniform2f(uniforms.uInverseResolution, 1 / this._resolution, 1 / this._resolution);
        gl.uniform1f(uniforms.uRandSeed, Math.random());
        gl.uniform1f(uniforms.uBlur, 0);

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

        gl.drawBuffers([
            gl.COLOR_ATTACHMENT0,
            gl.COLOR_ATTACHMENT1,
            gl.COLOR_ATTACHMENT2,
            gl.COLOR_ATTACHMENT3,
            gl.COLOR_ATTACHMENT4,
        ]);

        gl.drawArrays(gl.TRIANGLES, 0, 3);
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

        // NOTE: Multiple attachments require SAME DIMENSIONS!
        const positionBufferSpec = {
            width: BUFFER_SIZE,
            height: BUFFER_SIZE,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            wrapS: gl.CLAMP_TO_EDGE,
            wrapT: gl.CLAMP_TO_EDGE,
            format: gl.RGBA,
            iformat: gl.RGBA32F,
            type: gl.FLOAT,
        };

        const directionBufferSpec = {
            width: BUFFER_SIZE,
            height: BUFFER_SIZE,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            wrapS: gl.CLAMP_TO_EDGE,
            wrapT: gl.CLAMP_TO_EDGE,
            format: gl.RGBA,
            iformat: gl.RGBA32F,
            type: gl.FLOAT,
        };

        const transmittanceBufferSpec = {
            width: BUFFER_SIZE,
            height: BUFFER_SIZE,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            wrapS: gl.CLAMP_TO_EDGE,
            wrapT: gl.CLAMP_TO_EDGE,
            format: gl.RGBA,
            iformat: gl.RGBA32F,
            type: gl.FLOAT,
        };

        const radianceBufferSpec = {
            width: BUFFER_SIZE,
            height: BUFFER_SIZE,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            wrapS: gl.CLAMP_TO_EDGE,
            wrapT: gl.CLAMP_TO_EDGE,
            format: gl.RGBA,
            iformat: gl.RGBA32F,
            type: gl.FLOAT,
        };

        const rayPositionBufferSpec = {
            width: BUFFER_SIZE,
            height: BUFFER_SIZE,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            wrapS: gl.CLAMP_TO_EDGE,
            wrapT: gl.CLAMP_TO_EDGE,
            format: gl.RGBA,
            iformat: gl.RGBA32F,
            type: gl.FLOAT,
        };

        return [
            positionBufferSpec,
            directionBufferSpec,
            transmittanceBufferSpec,
            radianceBufferSpec,
            rayPositionBufferSpec,
        ];
    }

    // TODO: This can be removed
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