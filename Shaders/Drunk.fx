// Copyright 2021 Michael Fabian Dirks <info@xaymar.com>
// Modified for use with GShade by Radegast Stravinsky <radegast.ffxiv@gmail.com>
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//	this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice,
//	this list of conditions and the following disclaimer in the documentation
//	and/or other materials provided with the distribution.
// 3. Neither the name of the copyright holder nor the names of its contributors
//	may be used to endorse or promote products derived from this software
//	without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#undef fmod
#define fmod(x, y) x - y * floor(x/y)

#define MAX_LINE 5
#define MAX_PTS 5

#include "ReShade.fxh"
#include "Blending.fxh"

// Shader Parameters
uniform float2 p_drunk_strength<
    ui_type = "slider";
    ui_label = "Strength";
    ui_category = "Distortion";
    ui_min = 0.0; 
    ui_max = 100.0;
    ui_step = 0.1;
    ui_tooltip = "Controls the magnitude of the distortion along the X and Y axis.";    
> = 25.0;

uniform float2 p_drunk_speed<
    ui_type = "slider";
    ui_label = "Speed";
    ui_category = "Distortion";
    ui_min = 0.0; 
    ui_max = 10.0;
    ui_step = 0.1;
    ui_tooltip = "Controls the speed of the distortion along the X and Y axis.";    

> = 2.0;

uniform float angle <
    ui_type = "slider";
    ui_label = "Bending Angle";
    ui_category = "Distortion";
    ui_min = -1800.0; 
    ui_max = 1800.0; 
    ui_tooltip = "Controls how much the distortion bends.";
    ui_step = 1.0;
> = 180.0;

uniform float angle_speed<
    ui_type = "slider";
    ui_label = "Bending Speed";
    ui_category = "Distortion";
    ui_min = 0.0; 
    ui_max = 10.0;
    ui_step = 0.1;
    ui_tooltip = "Controls the speed of the bending.";    

> = 1.0;


BLENDING_COMBO(
    render_type, 
    "Blending Mode", 
    "Blends the effect with the previous layers.",
    "Blending",
    false,
    0,
    0
);

uniform float blending_amount <
    ui_type = "slider";
    ui_label = "Opacity";
    ui_category = "Blending";
    ui_tooltip = "Adjusts the blending amount.";
    ui_min = 0.0;
    ui_max = 1.0;
> = 1.0;

uniform float depth_threshold <
    ui_type = "slider";
    ui_label="Depth Threshold";
    ui_category = "Depth";
    ui_min=0.0;
    ui_max=1.0;
> = 0;

uniform int depth_mode <
    ui_type = "combo";
    ui_label = "Depth Mode";
    ui_category = "Depth";
    ui_items = "Minimum\0Maximum\0";
    ui_tooltip = "Mask the effect by using the depth of the scene.";
> = 0;

uniform bool set_max_depth_behind <
    ui_label = "Set Distortion Behind Foreground";
    ui_tooltip = "(Maximum Depth Threshold Mode only) When enabled, sets the distorted area behind the objects that should come in front of it.";
    ui_category = "Depth";
> = 0;

uniform float anim_rate <
    source = "timer";
>;

// Textures
texture texColorBuffer : COLOR;

texture drunkDistortTarget
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA8;
};

// Samplers
sampler samplerColor
{
    Texture = texColorBuffer;

    AddressU = MIRROR;
    AddressV = MIRROR;
    AddressW = MIRROR;

    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;

    MinLOD = 0.0f;
    MaxLOD = 1000.0f;

    MipLODBias = 0.0f;

    SRGBTexture = false;
};

sampler result 
{
    Texture = drunkDistortTarget;
};

// Helper Functions
float2x2 swirlTransform(float theta) {
    const float c = cos(theta);
    const float s = sin(theta);

    const float m1 = c;
    const float m2 = -s;
    const float m3 = s;
    const float m4 = c;

    return float2x2(
        m1, m2,
        m3, m4
    );
}

float random_time_at(int x, int y) {
      
    const float x0[] = { .2, .8, -.2, .452, -.2832, .8 };
    const float x1[] = {-.28, -1, -.42, -.89, .72, -.29 };
    const float x2[] = { .75, .25, .33, .67, .98, .01 };
    const float x3[] = { -.28, 0.8, -.32, -.189, .11, .84 };
    const float x4[] = { -.48, 0.1, -.2323, -.555, .421, .23 };
    const float x5[] = { -.28, 0.3, -1.3333, 1.333, 4, 1 };

    float result;
    switch(x) {
        case 0:
            result = x0[y];
            break;
        case 1:
            result = x1[y];
            break;
        case 2:
            result = x2[y];
            break;
        case 3:
            result = x3[y];
            break;
        case 4:
            result = x4[y];
            break;
        case 5:
            result = x5[y];
            break;
    }
   
    return result;
}

float2 mult_at(int x, int y) {
	float x2 = fmod(x, 2.);
	float y2 = fmod(y, 2.);
	
	float2 mult;
	mult.x = (x2 < 1.) ? -1. : 1.;
	mult.y = (y2 < 1.) ? -1. : 1.;
	
	return mult;
}



// Vertex Shader
void FullScreenVS(uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD0)
{
    texcoord.x = (id == 2) ? 2.0 : 0.0;
    texcoord.y = (id == 1) ? 2.0 : 0.0;
    
    position = float4(texcoord * float2(2, -2) + float2(-1, 1), 0, 1);

}

// Pixel Shader
float4 PSDrunkStage1(float4 pos : SV_Position, float2 texcoord : TEXCOORD0) : SV_TARGET {

	float2 uvs[36];
    float out_depth;
    float4 base = tex2D(samplerColor, texcoord);
    float2 tc = texcoord;
    const float theta = radians(angle) * sin(anim_rate * 0.0005 * angle_speed);

	for (uint i = 0; i < 36; i++) {
        uint x = i/6;
        uint y = i%6;
		float2 off = float2(0, 0);
		if ((x >= 0) && (x < MAX_PTS)) {
			off.x = cos(anim_rate / 1000 * (p_drunk_speed.x) + random_time_at(x, y)) * (1. / tc.x);
		}
		if ((y >= 0) && (y < MAX_PTS)) {
			off.y = sin(anim_rate / 1000 * (p_drunk_speed.y) + random_time_at(x, y)) * (1. / tc.y);
		}
		off *= (p_drunk_strength / 100.0) * tc.xy * 0.5 * mult_at(x, y);
		off = mul(swirlTransform(theta), off);	
		uvs[i] = float2((x +  off.x) / MAX_LINE , (y + off.y) / MAX_LINE );
	}
	
	float2 fade = frac(tc.xy * MAX_LINE);
	fade = (sin((fade - 0.5) * 3.141) + 1.0) * 0.5;
	
	int2 _low = int2(floor(tc.xy * MAX_LINE));
	int2 _hig = int2(ceil(tc.xy * MAX_LINE));
	
    _low.x *=   MAX_PTS+1;
    _hig.x *=  MAX_PTS+1;
    

	float2 uv = tc.xy;

	float2 uv_tl = uvs[_low.x + _low.y];
	float2 uv_tr = uvs[_hig.x + _low.y];
	float2 uv_bl = uvs[_low.x + _hig.y];
	float2 uv_br = uvs[_hig.x + _hig.y];
	
	float2 uv_t = lerp(uv_tl, uv_tr, fade.x);
	float2 uv_b = lerp(uv_bl, uv_br, fade.x);
	uv = lerp(uv_t, uv_b, fade.y);
	
	float4 result = tex2D(samplerColor, uv);
    bool inDepthBounds;
    if (depth_mode == 0) 
    {
        out_depth =  ReShade::GetLinearizedDepth(texcoord).r;
        inDepthBounds = out_depth >= depth_threshold;
    }
    else
    {
        out_depth = ReShade::GetLinearizedDepth(uv).r;
        inDepthBounds = out_depth <= depth_threshold;
    }
    if(inDepthBounds) {
        result.rgb = ComHeaders::Blending::Blend(render_type, base.rgb, result.rgb, blending_amount);
        

    } else result = base;
	
    if(set_max_depth_behind) 
    {
        const float mask_front = ReShade::GetLinearizedDepth(texcoord).r;
        if(mask_front < depth_threshold)
            result = tex2D(samplerColor, texcoord);
    }
    return result;
}

technique Drunk
{
	pass
	{
		VertexShader = FullScreenVS;
		PixelShader  = PSDrunkStage1; 
	}
}
