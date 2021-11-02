// UnlitTexture shader template for URP. This is SRPBatcher Compatible: 
Shader "Environment/Water"
{
    Properties
    {
        [MainColor] _WaterBaseColor01("Water Intersection Color", Color) = (1,1,1,1)
        [MainColor] _WaterBaseColor02("Water Base Color", Color) = (1,1,1,1)
        
        [Header(Specular)]
        _SpecularColor("Specular Color", Color) = (1,1,1,1)
        _SpecularIntensity("Specular Intensity", Range(0,1)) = 1
        _Shininess("Shininess", Range(0,5)) = 1
        _DistortedNormalStrength("Distorted Normal Strength", Range(0,1)) = 1
        
        [Header(Reflection)]
        _ReflectionCubemap("Reflection Cubemap", Cube) = "white"{}
        _FresnelStrength("Fresnel Mask Strength", Range(1,5)) = 1 // Only show fresnel effect around rim edges
        
        [Header(Foam)]
        [MainTexture]_FoamBaseMap("Foam BaseMap", 2D) = "white" {}
        _FoamSpreadFactor("Foam Spread Factor", Range(0, 5)) = 1
        _FoamColor("Foam Color", Color) = (1,1,1,1)
        _FoamNoise("Foam Noise", Range(1, 5)) = 1
        _AnimationSpeed("Animation Speed", Range(0, 1)) = 0.12
        
        [Header(Distortion)]
        _DistortNormalMap("Distort Normal Map", 2D) = "white" {} // Use normal map for distortion: R(u)G(v)B contains different normals => different u & v animation
        _DistortAmount("Distort Amount", Range(0,0.1)) = 0.02
    }

    // Universal Render Pipeline subshader. If URP is installed this will be used.
    SubShader
    {
        // Make water quad transparent so it's not written into the depth map => get intersection area of other opaque objects, manually get water's viewspace depth value.z for comparisons
        Tags { "RenderType"="Transparent" "Queue" = "Transparent" "IgnoreProjector" = "True" "RenderPipeline"="UniversalRenderPipeline"}

        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            // #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 uv           : TEXCOORD0; //uv.xy = foam uv animation, uv.zw = distort underwater uv animation
                float fogCoord : TEXCOORD1;
                float4 positionHCS  : SV_POSITION; // Homogeneous Clip space
                float3 positionVS : TEXCOORD2; // View space
                float3 positionWS : TEXCOORD3; 
                float3 normalWS : TEXCOORD4;
                float4 waterNormalUV : TEXCOORD5;
            };

            TEXTURE2D(_FoamBaseMap);SAMPLER(sampler_FoamBaseMap);
            TEXTURE2D(_CameraDepthTexture);SAMPLER(sampler_CameraDepthTexture);
            TEXTURE2D(_CameraOpaqueTexture);SAMPLER(sampler_CameraOpaqueTexture);
            TEXTURE2D(_DistortNormalMap);SAMPLER(sampler_DistortNormalMap);
            TEXTURECUBE(_ReflectionCubemap);SAMPLER(sampler_ReflectionCubemap);
            
            CBUFFER_START(UnityPerMaterial)
            float4 _FoamBaseMap_ST;
            float4 _DistortNormalMap_ST;
            half4 _WaterBaseColor01, _WaterBaseColor02;
            half _FoamSpreadFactor;
            half _AnimationSpeed;
            half4 _FoamColor;
            half _FoamNoise;
            half _DistortAmount;
            half4 _SpecularColor;
            half _SpecularIntensity, _Shininess;
            half _DistortedNormalStrength;
            half _FresnelStrength;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                
                OUT.positionWS = TransformObjectToWorld(IN.positionOS);
                OUT.positionVS = TransformWorldToView(OUT.positionWS);
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                // Use IN.uv.xy to make sure tiling changes with object scale changes accordingly. Scale should not affect foamTex tiling. Animate foam effect via texture offset.
                float animationOffset = _Time.y * _AnimationSpeed;
                OUT.uv.xy = OUT.positionWS.xz * _FoamBaseMap_ST.xy + animationOffset;
                //OUT.uv.zw = TRANSFORM_TEX(IN.uv, _DistortNormalMap) + animationOffset;
                OUT.waterNormalUV.xy = TRANSFORM_TEX(IN.uv, _DistortNormalMap) + animationOffset * float2(1, 1);
                OUT.waterNormalUV.zw = TRANSFORM_TEX(IN.uv, _DistortNormalMap) + animationOffset * float2(-1.07, 1.1); // Flow water at opposite directions to create more interesting movement. Vary values slightly
                OUT.fogCoord = ComputeFogFactor(OUT.positionHCS.z);
                OUT.normalWS = TransformObjectToWorld(IN.normalOS);
                
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 screenUV = IN.positionHCS.xy / _ScreenParams.xy;
                
                // Water Depth Base
                half depthTex = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, screenUV); // SAMPLE_DEPTH_TEXTURE
                // LinearEyeDepth takes the depth buffer value & converts it into world scaled view space depth. The original depth texture 0.0 will become the far plane distance value, 1.0 will be the near clip plane.  
                half depthScene = LinearEyeDepth(depthTex, _ZBufferParams); // Calculate water's viewspace z value for depth comparison against other objects
                half depthWater = saturate(depthScene + IN.positionVS.z); // Manually get water's viewspace depth value.z for comparisons. Try removing saturate
                // Water base color transition 0 - 1 (WaterColor01 to WaterColor02)
                half4 waterColor = lerp(_WaterBaseColor01, _WaterBaseColor02, depthWater);
                
                // Water Caustics
                
                // Water Foam Bubbles
                half foamTex = SAMPLE_TEXTURE2D(_FoamBaseMap, sampler_FoamBaseMap, IN.uv.xy); // Foam needs to be 1D vector - black & white value, no need for half4.
                foamTex = pow(abs(foamTex), _FoamNoise); // TODO: optimisation - no pow
                half foamDepth = depthWater * _FoamSpreadFactor;
                half foamIntersectionEdgeMask = step(foamDepth, foamTex);
                half4 foamColor = foamIntersectionEdgeMask * _FoamColor;
                half4 waterFoamColor = foamColor + waterColor;
                waterFoamColor.a = 0.5;

                // Under-Water Distortion: Show undistorted depth water map if water region is covered by current object
                half4 distortNormalTex = SAMPLE_TEXTURE2D(_DistortNormalMap, sampler_DistortNormalMap, IN.waterNormalUV.xy);
                half4 distortNormalTexFlowAlt = SAMPLE_TEXTURE2D(_DistortNormalMap, sampler_DistortNormalMap, IN.waterNormalUV.zw);
                half4 distortNormals = distortNormalTex * distortNormalTexFlowAlt;
                
                float2 distortUV = lerp(screenUV, distortNormals, _DistortAmount);
                half depthDistortTex = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, distortUV);
                half depthDistortScene = LinearEyeDepth(depthDistortTex, _ZBufferParams);
                half depthDistortWater = depthDistortScene + IN.positionVS.z; // If water region is covered by current object (above water level): depthDistortWater is negative
                float2 opaqueTexUV = distortUV;
                if(depthDistortWater < 0) opaqueTexUV = screenUV;
                half4 underWaterOpaqueTex = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, opaqueTexUV);

                // Water Specular = SpecularColor * SpecularReflectionKs * pow(max(0, dot(N,H), Shininess)
                half4 normal = lerp(half4(normalize(IN.normalWS), 1), distortNormals, _DistortedNormalStrength); // Normalize to avoid visual artefacts when rotating view angle
                Light mainLight = GetMainLight();
                half3 lightDir = mainLight.direction;
                half3 viewDir = normalize(_WorldSpaceCameraPos.xyz - IN.positionWS.xyz);
                half3 halfVector = normalize(lightDir + viewDir);
                half NDotH = dot(normal,halfVector);
                half4 specular = _SpecularColor * _SpecularIntensity * pow(max(0, NDotH), _Shininess);
                
                // Water Reflection with fresnel mask
                half fresnelMask = pow(1 - saturate(dot(normal, viewDir)), _FresnelStrength);
                half3 reflectionUV = reflect(-viewDir, normal);
                half4 reflectionTex = SAMPLE_TEXTURECUBE(_ReflectionCubemap, sampler_ReflectionCubemap, reflectionUV);
                half4 reflection = reflectionTex * fresnelMask;
                
                half4 finalCol = underWaterOpaqueTex * waterColor + waterFoamColor + specular * reflection;
                // finalCol *= reflection;
                return finalCol;
            }
            ENDHLSL
        }
    }

    // Built-in pipeline subshader. This is fallback subshader in case URP is not being used.
    /*SubShader
    {
        Tags { "RenderType"="Opaque"}
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // Water Depth
                // Water Specular
                
                // Water Reflection
                // Water Caustics
                // Under-Water Distortion
                // Water Bubbles
                // sample the texture
                fixed4 col = tex2D(_MainTex, i.uv);
                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }*/
}