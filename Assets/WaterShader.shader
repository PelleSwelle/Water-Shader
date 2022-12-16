Shader "DNC/Unlit/Water" 
{
    Properties 
    {
        _BaseMap("Albedo", 2D) = "white" {}
        _waterDepth("Depth", Float) = 9
        [HDR]_ShallowColor("Shallow Color", Color) = (0.27, 0.58, 0.76, 0.57)
        [HDR]_DeepColor("Deep Color", Color) = (0, 0.04, 0.17, 0.92)
        [HDR]_FoamColor("Foam Color", Color) = (1, 1, 1, 1)
        _Foam("Foam: Amount,  Scale,  Cutoff,  Speed", Vector) = (1, 120, 5, 1)
        _Refraction("Refraction: Strength,  Scale,  Speed", Vector) = (0.002, 40, 1)
        _Wave("Wave: VelocityX, VelocityY,  Intensity", Vector) = (1, 1, 0.2)
    }

    SubShader {
        LOD 100
        
        Tags {
            // "Queue" = "Transparent" // paints the mesh before the opaque layer
            // "RenderType" = "Transparent"
            // "RenderPipeline" = "UniversalPipeline"
            // "IgnoreProjector" = "True"
        }

        Pass {
            // Tags {
            //     "LightMode" = "UniversalForward"
            // }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"

            // #pragma multi_compile_instancing // GPU instancing

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

            float3 SampleSceneColor(float2 UV) {
                return SAMPLE_TEXTURE2D_X(
                    _CameraOpaqueTexture, 
                    sampler_CameraOpaqueTexture, 
                    UnityStereoTransformScreenSpaceTex(UV)).rgb;
            }

            ////////////////////
            // Gradient Noise // Google "gradient noise shader graph"
            ////////////////////
            float2 GradientNoiseDir(float2 p) {
                p = p % 289;
                float x = (34 * p.x + 1) * p.x % 289 + p.y;
                x = (34 * x + 1) * x % 289;
                x = frac(x / 41) * 2 - 1;
                return normalize(float2(x - floor(x + 0.5), abs(x) - 0.5));
            }
            
            // generates a pseduo random float value between 0 and 1
            float random(float2 uv) {
                float2 noise = (
                    frac(
                        sin(
                            dot(
                                uv,
                                float2( 12.9898,78.233 ) * 2.0
                            )
                        ) * 43758.5453
                    )
                );
                return abs( noise.x + noise.y ) * 0.5;
            }


            float noise (float2 st) {
                float2 i = floor(st);
                float2 f = frac(st);

                // Four corners in 2D of a tile
                float a = random(i);
                float b = random(i + float2(1.0, 0.0));
                float c = random(i + float2(0.0, 1.0));
                float d = random(i + float2(1.0, 1.0));

                // Smooth Interpolation
                float2 u = smoothstep(0.,1.,f);

                // Mix 4 coorners percentages
                return lerp( a, b, u.x ) +
                        ( c - a ) * u.y * ( 1.0 - u.x ) +
                        ( d - b ) * u.x * u.y;
            }

            // Gradient noise is a type of noise commonly used in computer graphics. One of the implementations is Perlin Noise.
            float GradientNoise(float2 weirdness) {
                float2 ip = floor(weirdness);
                float2 fp = frac(weirdness);
                
                float d00 = dot(
                    GradientNoiseDir(ip), 
                    fp
                );
                float d01 = dot(
                    GradientNoiseDir(ip + float2(0, 1)), 
                    fp - float2(0, 1)
                );
                float d10 = dot(
                    GradientNoiseDir(ip + float2(1, 0)), 
                    fp - float2(1, 0)
                );
                float d11 = dot(
                    GradientNoiseDir(ip + float2(1, 1)), 
                    fp - float2(1, 1)
                );
                fp = fp * fp * fp * (fp * (fp * 6 - 15) + 10);
                
                return lerp(
                    lerp(d00, d01, fp.y), 
                    lerp(d10, d11, fp.y), 
                    fp.x
                );
            }

            ///////////
            // Water //
            ///////////
            float2 WaterRefractedUV(float2 _uv, float _strength, float _scale, float _speed, float2 ScreenUV) {
                float2 tiledAndOffsettedUV = _uv * _scale + (_Time.y * _speed);
                // float gNoiseRemapped = GradientNoise(tiledAndOffsettedUV) * 2 * _strength;
                float gNoiseRemapped = noise(tiledAndOffsettedUV) * 2 * _strength;
                return ScreenUV + gNoiseRemapped;
            }

            float waterDepthFade(float waterDepth, float4 screenPosition, float distanceToCamera) { 
                return saturate((waterDepth - screenPosition.w) / distanceToCamera); 
            }

            struct Attributes {
                float4 positionOS : POSITION; // vertex position in object space
                float2 texCoord : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID // GPU instancing
            };

            struct v2f {
                float4 positionCS : SV_POSITION; // vertex position in camera space
                float2 texCoord : TEXCOORD0;
                float4 screenPos : TEXCOORD1;
            };

            TEXTURE2D(_BaseMap); 
            SAMPLER(sampler_BaseMap); 
            float4 _BaseMap_ST;

            float _waterDepth;
            half4 _DepthColor;
            half4 _ShallowColor;
            half4 _DeepColor;
            half4 _FoamColor;
            float4 _Foam;
            float3 _Refraction;
            float3 _Wave;

            v2f vert(Attributes attributes) {
                v2f o;
                o.texCoord = TRANSFORM_TEX(attributes.texCoord, _BaseMap);

                float3 positionWS = TransformObjectToWorld(attributes.positionOS.xyz); // vertex position in world space
                float3 displacement = float3(
                    0, 
                    GradientNoise(positionWS.xz + _Time.y * _Wave.xy) * _Wave.z, 
                    0
                );
                positionWS += displacement;
                o.positionCS = mul(UNITY_MATRIX_VP, float4(positionWS, 1));
                o.screenPos = ComputeScreenPos(o.positionCS);

                return o;
            }

            half4 frag(v2f i) : SV_Target {
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                float zEye = LinearEyeDepth(SampleSceneDepth(screenUV), _ZBufferParams);

                half4 depthColor = lerp(_ShallowColor, _DeepColor, waterDepthFade(zEye, i.screenPos, _waterDepth));

                float foam = waterDepthFade(zEye, i.screenPos, _Foam.x) * _Foam.z;
                float2 foamUV = i.texCoord * _Foam.y + (_Foam.w * _Time.y);
                float gNoise = GradientNoise(foamUV) + 0.5;
                half4 foamValue = step(foam, gNoise) * _FoamColor.a;

                half4 waterColor = lerp(depthColor, _FoamColor, foamValue);

                float2 refractedUV = WaterRefractedUV(i.texCoord, _Refraction.x, _Refraction.y, _Refraction.z, screenUV);
                half4 refractedSceneColor = half4(SampleSceneColor(refractedUV), 1);

                return lerp(refractedSceneColor, waterColor, waterColor.a);
            }

            ENDHLSL
        }
    }
}