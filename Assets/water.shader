Shader "Unlit/OwnWater2"
{
    Properties 
    {
        _BaseMap("Albedo", 2D) = "white" {}
        _waterDepth("Depth", Float) = 9
        [HDR]_ShallowColor("Shallow Color", Color) = (0.27, 0.58, 0.76, 0.57)
        [HDR]_DeepColor("Deep Color", Color) = (0, 0.04, 0.17, 0.92)
        [HDR]_FoamColor("Foam Color", Color) = (1, 1, 1, 1)
        _Foam("Foam: Amount,  Scale,  Cutoff,  Speed", Vector) = (1, 120, 5, 1)
        _Wave("Wave: VelocityX, VelocityY,  Intensity", Vector) = (1, 1, 0.2)
    }

    SubShader {
        Pass {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"

            //////////////////////
            // Depth and Opaque //
            //////////////////////
            TEXTURE2D_X(_CameraOpaqueTexture); 
            SAMPLER(sampler_CameraOpaqueTexture); 
            float4 _CameraOpaqueTexture_TexelSize;
            TEXTURE2D_X(_CameraDepthTexture); 
            SAMPLER(sampler_CameraDepthTexture);

            float SampleSceneDepth(float2 UV) {
                return SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, UnityStereoTransformScreenSpaceTex(UV)).r;
            }

            // generates a pseduo random float value between 0 and 1
            float random(float2 uv) {
                float2 noise = ( frac( sin( dot( uv, float2( 12.9898,78.233 ) * 2.0 ) ) * 43758.5453 ) );
                return abs( noise.x + noise.y ) * 0.5;
            }

            // generates a noise map
            float randomNoise (float2 st) {
                float2 i = floor(st); float2 f = frac(st);

                // Four corners in 2D of a tile
                float a = random(i);
                float b = random(i + float2(1.0, 0.0));
                float c = random(i + float2(0.0, 1.0));
                float d = random(i + float2(1.0, 1.0));

                // Smooth Interpolation
                float2 u = smoothstep(0.,1.,f);

                // Mix 4 coorners percentages
                return lerp( a, b, u.x ) + ( c - a ) * u.y * ( 1.0 - u.x ) + ( d - b ) * u.x * u.y;
            }

            // sets a threshold for where the colors should change
            float waterDepthFade(float depth, float4 screenPosition, float distanceToCamera) { 
                return saturate((depth - screenPosition.w) / distanceToCamera); 
            }

            struct appdata {
                float4 position_objectSpace : POSITION; // vertex position in object space
                float2 textureCoordinate : TEXCOORD0;
            };

            struct v2f {
                float4 position_cameraSpace : SV_POSITION; // vertex position in camera space
                float2 textureCoordinate : TEXCOORD0;
                float4 screenPosition : TEXCOORD1;
            };

            TEXTURE2D(_BaseMap); 
            SAMPLER(sampler_BaseMap); 
            float4 _BaseMap_ST;

            float _waterDepth;
            half4 _DepthColor, _ShallowColor, _DeepColor, _FoamColor;
            float4 _Foam;
            float3 _Wave;
            
            // *** vertex shader ***
            v2f vert(appdata vertices) {
                v2f interpolator;
                interpolator.textureCoordinate = TRANSFORM_TEX(vertices.textureCoordinate, _BaseMap);

                float3 position_worldSpace = TransformObjectToWorld(vertices.position_objectSpace.xyz);
                float noise = randomNoise(position_worldSpace.xz + _Time.y * _Wave.xy) * _Wave.z;
                float3 displacement = float3( 0, noise, 0 );
                position_worldSpace += displacement;
                interpolator.position_cameraSpace = mul(UNITY_MATRIX_VP, float4(position_worldSpace, 1));
                interpolator.screenPosition = ComputeScreenPos(interpolator.position_cameraSpace);

                return interpolator;
            }

            // *** fragment shader ***
            half4 frag(v2f input) : SV_Target {
                float2 screenUV = input.screenPosition.xy / input.screenPosition.w;
                float zEye = LinearEyeDepth(SampleSceneDepth(screenUV), _ZBufferParams);

                half4 depthColor = lerp(_ShallowColor, _DeepColor, waterDepthFade(zEye, input.screenPosition, _waterDepth));

                float foam = waterDepthFade(zEye, input.screenPosition, _Foam.x) * _Foam.z;
                float2 foamUV = input.textureCoordinate * _Foam.y + (_Foam.w * _Time.y);
                float noise = randomNoise(foamUV) + 0.5;
                half4 foamValue = step(foam, noise) * _FoamColor.a;

                return lerp(depthColor, _FoamColor, foamValue);
            }

            ENDHLSL
        }
    }
}
