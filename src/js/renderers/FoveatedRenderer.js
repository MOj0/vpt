import { mat4 } from '../../lib/gl-matrix-module.js';

import { WebGL } from '../WebGL.js';
import { AbstractRenderer } from './AbstractRenderer.js';

import { PerspectiveCamera } from '../PerspectiveCamera.js';

import { SingleBuffer } from '../SingleBuffer.js';

const [SHADERS, MIXINS] = await Promise.all([
    'shaders.json',
    'mixins.json',
].map(url => fetch(url).then(response => response.json())));

export class FoveatedRenderer extends AbstractRenderer {

    constructor(gl, volume, camera, environmentTexture, options = {}) {
        super(gl, volume, camera, environmentTexture, options);

        this.registerProperties([
            // MIP
            {
                name: 'stepsMIP',
                label: 'StepsMIP',
                type: 'spinner',
                value: 64,
                min: 1,
            },
            // MCM
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

        this.addEventListener('change', e => {
            const { name, value } = e.detail;

            if (name === 'transferFunction') {
                this.setTransferFunction(this.transferFunction);
            }

            if ([
                'extinction',
                'anisotropy',
                'bounces',
                'transferFunction',
            ].includes(name)) {
                this.reset();
            }
        });

        this._computeBuffer = new SingleBuffer(gl, this._getComputeBufferSpec());

        this._programs = WebGL.buildPrograms(gl, SHADERS.renderers.FOVEATED, MIXINS);

        this._mx = -1;
        this._my = -1;

        gl.canvas.addEventListener('pointermove', e => {
            if (e.altKey) {
                this._mx = e.offsetX / this._resolution;
                this._my = 1 - e.offsetY / this._resolution;
            }
        });
    }

    destroy() {
        const gl = this._gl;
        Object.keys(this._programs).forEach(programName => {
            gl.deleteProgram(this._programs[programName].program);
        });

        super.destroy();
    }

    render() {
        this._accumulationBuffer.use();
        this._integrateFrame();
        this._accumulationBuffer.swap();

        this._renderBuffer.use();
        this._renderFrame();

        this._mx = -1;
        this._my = -1;
    }

    reset() {
        // MIP renderer only needs to get invoked when the state changes
        this._frameBuffer.use();
        this._generateFrame();

        // Compute photon positions using MIP output & MipMap
        this._computeBuffer.use();
        this._computePosition();

        this._accumulationBuffer.use();
        this._resetFrameAccumulation();
        this._accumulationBuffer.swap();

        this._renderBuffer.use();
        this._resetFrameRender();
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

        gl.uniform2f(uniforms.uMousePos, this._mx, this._my);

        gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    _computePosition() {
        const gl = this._gl;

        const { program, uniforms } = this._programs.compute;
        gl.useProgram(program);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, this._frameBuffer.getAttachments().color[0]);
        gl.generateMipmap(gl.TEXTURE_2D);
        gl.uniform1i(uniforms.uFrame, 0);

        gl.uniform1f(uniforms.uRandSeed, Math.random());

        gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    _integrateFrame() {
        const gl = this._gl;

        const { program, uniforms } = this._programs.integrate;
        gl.useProgram(program);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[0]);
        gl.uniform1i(uniforms.uPosition, 0);

        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[1]);
        gl.uniform1i(uniforms.uDirection, 1);

        gl.activeTexture(gl.TEXTURE2);
        gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[2]);
        gl.uniform1i(uniforms.uTransmittance, 2);

        gl.activeTexture(gl.TEXTURE3);
        gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[3]);
        gl.uniform1i(uniforms.uRadiance, 3);

        gl.activeTexture(gl.TEXTURE4);
        gl.bindTexture(gl.TEXTURE_2D, this._computeBuffer.getAttachments().color[0]);
        gl.uniform1i(uniforms.uRandomPosition, 4);

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

        gl.uniform1f(uniforms.uRandSeed, Math.random());

        gl.uniform1f(uniforms.uExtinction, this.extinction);
        gl.uniform1f(uniforms.uAnisotropy, this.anisotropy);
        gl.uniform1ui(uniforms.uMaxBounces, this.bounces);
        gl.uniform1ui(uniforms.uSteps, this.stepsMCM);

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
        ]);

        gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    _renderFrame() {
        const gl = this._gl;

        const { program, uniforms } = this._programs.render;
        gl.useProgram(program);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[3]);
        gl.uniform1i(uniforms.uColor, 0);

        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, this._computeBuffer.getAttachments().color[0]);
        gl.uniform1i(uniforms.uRandomPosition, 1);

        gl.drawArrays(gl.POINTS, 0, this._resolution * this._resolution);
    }

    _resetFrameAccumulation() {
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

    _resetFrameRender() {
        const gl = this._gl;

        const { program, uniforms } = this._programs.resetRender;
        gl.useProgram(program);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, this._environmentTexture);
        gl.uniform1i(uniforms.uEnvironment, 0);

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

    _getComputeBufferSpec() {
        const gl = this._gl;

        const rayPositionBufferSpec = {
            width: this._resolution,
            height: this._resolution,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            format: gl.RG,
            iformat: gl.RG32F,
            type: gl.FLOAT,
        };

        return [rayPositionBufferSpec];
    }

    _getAccumulationBufferSpec() {
        const gl = this._gl;

        const positionBufferSpec = {
            width: this._resolution,
            height: this._resolution,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            format: gl.RGBA,
            iformat: gl.RGBA32F,
            type: gl.FLOAT,
        };

        const directionBufferSpec = {
            width: this._resolution,
            height: this._resolution,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            format: gl.RGBA,
            iformat: gl.RGBA32F,
            type: gl.FLOAT,
        };

        const transmittanceBufferSpec = {
            width: this._resolution,
            height: this._resolution,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            format: gl.RGBA,
            iformat: gl.RGBA32F,
            type: gl.FLOAT,
        };

        const radianceBufferSpec = {
            width: this._resolution,
            height: this._resolution,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            format: gl.RGBA,
            iformat: gl.RGBA32F,
            type: gl.FLOAT,
        };

        return [
            positionBufferSpec,
            directionBufferSpec,
            transmittanceBufferSpec,
            radianceBufferSpec,
        ];
    }
}
