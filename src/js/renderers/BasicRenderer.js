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
    }

    destroy() {
        const gl = this._gl;
        Object.keys(this._programs).forEach(programName => {
            gl.deleteProgram(this._programs[programName].program);
        });

        super.destroy();
    }

    render() {
        // this._frameBuffer.use(); // NOTE: This is done in the _generateFrame method
        this._generateFrame();

        this._accumulationBuffer.use();
        this._integrateFrame();
        this._accumulationBuffer.swap();

        this._renderBuffer.use();
        this._renderFrame();
    }

    _generateFrame() {
        const gl = this._gl;
        gl.bindFramebuffer(gl.FRAMEBUFFER, this._frameBuffer.getFramebuffer());
        gl.viewport(0, 0, this._resolution, this._resolution);

        const { program, uniforms } = this._programs.generate;
        gl.useProgram(program);


        const positionData = new Float32Array(this._resolution * this._resolution * 2);
        gl.readPixels(0, 0, this._resolution, this._resolution, gl.RG, gl.FLOAT, positionData);
        // return positionData;
        console.log(positionData);
        // for (let i = 0; i < pixelData.length; i++) {
        //     if (pixelData[i] !== 0) {
        //         console.log('non-zero');
        //         break;
        //     }
        // }

        gl.drawArrays(gl.TRIANGLES, 0, 3);
    }


    _integrateFrame() {
        const gl = this._gl;

        const { program, uniforms } = this._programs.integrate;
        gl.useProgram(program);

        gl.drawBuffers([
            gl.COLOR_ATTACHMENT0,
            gl.COLOR_ATTACHMENT1,
        ]);

        gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    _renderFrame() {
        const gl = this._gl;

        const { program, uniforms } = this._programs.render;
        gl.useProgram(program);

        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[0]);
        gl.uniform1i(uniforms.uColor, 0);

        // gl.activeTexture(gl.TEXTURE1);
        // gl.bindTexture(gl.TEXTURE_2D, this._accumulationBuffer.getAttachments().color[1]);
        // gl.uniform1i(uniforms.uPosition, 1);
        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, this._frameBuffer.getAttachments().color[0]);
        gl.uniform1i(uniforms.uPosition, 1);

        gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    _resetFrame() {
        const gl = this._gl;

        const { program, uniforms } = this._programs.reset;
        gl.useProgram(program);

        gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    _getFrameBufferSpec() {
        const gl = this._gl;
        return [{
            width: this._resolution,
            height: this._resolution,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            format: gl.RG,
            iformat: gl.RG32F,
            type: gl.FLOAT,
        }];
    }

    _getAccumulationBufferSpec() {
        const gl = this._gl;
        const radianceBufferSpec = {
            width: this._resolution,
            height: this._resolution,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            format: gl.RGBA,
            iformat: gl.RGBA32F,
            type: gl.FLOAT,
        };

        const radianceBufferSpecVec2 = {
            width: this._resolution,
            height: this._resolution,
            min: gl.NEAREST,
            mag: gl.NEAREST,
            format: gl.RG,
            iformat: gl.RG32F,
            type: gl.FLOAT,
        };

        return [
            radianceBufferSpec,
            radianceBufferSpecVec2,
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