//=============================================================
// Custom Atmospheric Scattering based on Hoffman 
// and Pretham papers.
// License:
// 	J. Cuellar MIT License.
//=============================================================
shader_type sky;

// HDR.
uniform float _TonemapLevel: hint_range(0.0, 1.0) = 1.0;
uniform float _Exposure = 1.0;

// Color Correction.
uniform float _Contrast: hint_range(0.0, 1.0) = 0.3;
uniform float _Darkness: hint_range(0.0, 1.0) = 0.5;

// Intensity.
uniform float _SunIntensity = 40.0;
uniform float _NightIntensity: hint_range(0.0, 1.0) = 0.1;

// Artistic
uniform vec4  _DayTint: hint_color = vec4(1.0);
uniform vec4  _SDTint: hint_color  = vec4(0.91, 0.42, 0.35, 1.0);
uniform vec4  _NightTint: hint_color  = vec4(1.0);
uniform vec4  _GroundTint: hint_color = vec4(0.3, 0.3, 0.3, 1.0);

// Zenith.
uniform float _Thickness = 1.0;
uniform float _YMult: hint_range(0.0, 20.0) = 1.0;
uniform float _DownOffset: hint_range(0.0, 1.0) = 0.0;
uniform float _HorizonOffset = 0.0;

// _Mie.
uniform float _Mie = 0.07;
uniform float _Turbidity = 0.001;

// Sun Mie.
uniform vec4  _SunMieTint: hint_color = vec4(1.0);
uniform float _SunMieIntensity = 1.0;
uniform float _SunMieAnisotropy: hint_range(0.0, 0.999) = 0.75;

// Sun Disk.
uniform vec4  _SunDiskTint: hint_color = vec4(0.99, 0.49, 0.22, 1.0);
uniform float _SunDiskIntensity = 1.0;
uniform float _SunDiskSize = 0.022;

// PI.
const float kPI     = 3.1415927;  // π.
const float kTAU    = 6.2831853;  // π * 2.
const float kPIRCP  = 0.3183098;  // 1/π.
const float kPI4    = 12.5663706; // PI(π)*4.
const float kPI4RCP = 0.0795775;  // 1/(PI(π)*4).
const float k3PI16  = 0.0596831;  // 3/(PI(π)*16).

// Zenith Length.
const float kRayleighZenithLength = 8.4e3;
const float kMieZenithLength = 1.25e3;

// Beta Ray.
// 680, 550, 440
const vec3 kBetaRay = vec3(5.807035e-06, 1.356874e-05, 3.312679e-05);

// 650, 570, 475
//const vec3 kBetaRay = vec3(6.955633e-6, 1.176226e-05, 2.439022e-05);

const vec3 kBetaMie = vec3(0.000434);

//------------------------------------------------------------------------------
float saturateReal(in float real)
{
	return clamp(real, 0.0, 1.0);
}

vec3 saturateRGB(in vec3 real)
{
	return clamp(real.rgb, 0.0, 1.0);
}

vec3 pow3RGB(in vec3 real, in float fade)
{
	return mix(real.rgb, real.rgb * real.rgb * real.rgb, fade);
}

vec3 photoTonemap(vec3 real, in float exposure, in float lv)
{
	real.rgb *= exposure;
	return mix(real, 1.0 - exp(-real), lv);
}

float sunDisk(float size, vec3 r, vec3 coords)
{
	float dist = length(r - coords);
	return 1.0 - step(size, dist);
}

vec3 partialMiePhase(in float g)
{
	vec3 ret; 
	float g2 = g * g;
	ret.x = ((1.0 - g2) / (2.0 + g2));
	ret.y = (1.0 + g2);
	ret.z = (2.0 * g);
	
	return ret;
}

float miePhase(float mu, float g)
{
	vec3 partial = partialMiePhase(g);
	return (kPI4 * partial.x * ((1.0 + mu * mu) * 
		pow(partial.y - (partial.z * mu), -1.5))) * _SunMieIntensity;
}

float rayleighPhase(float mu)
{
	return k3PI16 * (1.0 + mu * mu);
}

// Paper.
//void _opticalDepth(float y, out float sr, out float sm)
//{
//	y = max(0.0, y);
//	y = saturateReal(y * _YMult);
//	
//	float zenith = acos(y);
//	zenith = cos(zenith) + 0.15 * pow(93.885 - ((zenith * 180.0) / kPI), -1.253);
//	zenith = 1.0 / (zenith+_DownOffset);
//	
//	sr = zenith * kRayleighZenithLength;
//	sm = zenith * kMieZenithLength;
//}

// Custom and more fast.
void opticalDepth(float y, out float sr, out float sm)
{
	y = max(0.03, y + 0.025) + _DownOffset;
	y = 1.0 / (y * _YMult);
	
	sr = y * kRayleighZenithLength;
	sm = y * kMieZenithLength;
}

vec3 atmosphericScattering(float sr, float sm, float mu, vec3 angleMult)
{
	vec3 betaMie = kBetaMie * 0.001 * _Mie;
	vec3 betaRay = kBetaRay * _Thickness;
	//------------------------------------------------------------------------
	
	vec3 extinctionFactor = saturateRGB(exp(-(betaRay * sr + betaMie * sm)));
	
	// Final Extinction Factor.
	vec3 fExtinctionFactor = mix(1.0 - extinctionFactor, 
		(1.0 - extinctionFactor) * extinctionFactor, angleMult.x);
	//------------------------------------------------------------------------
	
	float rayleighPhase = rayleighPhase(mu);
	
	vec3 BRT = betaRay * rayleighPhase;
	vec3 BMT = betaMie * miePhase(mu, _SunMieAnisotropy);
	BMT *= _SunMieIntensity * _SunMieTint.rgb;
	
	vec3 BRMT = (BRT + BMT) / (betaRay + betaMie);
	//------------------------------------------------------------------------
	
	vec3 scatter = _SunIntensity * (BRMT * fExtinctionFactor) * _DayTint.rgb;
	scatter *= angleMult.y;
	scatter  = mix(scatter, scatter * (1.0 - extinctionFactor), _Darkness);
	//------------------------------------------------------------------------
	
	// Sunsent/Dawn Color.
	vec3 sdCol = mix(_DayTint.rgb, _SDTint.rgb, angleMult.x);
	vec3 nightScatter = (1.0 - extinctionFactor) * angleMult.z;
	nightScatter *= _NightTint.rgb * _NightIntensity;
	//------------------------------------------------------------------------
	
	return (scatter * sdCol) + nightScatter;
}

void fragment()
{
	vec4 anglesMult;
	anglesMult.x = saturateReal(1.0 - LIGHT0_DIRECTION.y);
	anglesMult.y = saturateReal(LIGHT0_DIRECTION.y + 0.45);
	anglesMult.z = saturateReal(-LIGHT0_DIRECTION.y + 0.30);
	anglesMult.w = saturateReal(LIGHT0_DIRECTION.y);
	
	float y        = dot(vec3(0.0, 1.0, 0.0), EYEDIR) + _HorizonOffset;
	float cosTheta = dot(normalize(LIGHT0_DIRECTION), EYEDIR);
	
	// Scattering.
	float sr; float sm; opticalDepth(y, sr, sm);
	vec3 scatter = atmosphericScattering(sr, sm, cosTheta, anglesMult.xyz);
	
	// Sun Disk.
	scatter += sunDisk(_SunDiskSize, LIGHT0_DIRECTION, EYEDIR) * _SunDiskTint.rgb *
		_SunDiskIntensity * scatter;
	
	// Final Color.
	vec3 finalColor = mix(scatter, _GroundTint.rgb * anglesMult.w, saturateReal(-y * 100.0) * _GroundTint.a);
	
	// Color Correction.
	scatter = photoTonemap(scatter, _Exposure, _TonemapLevel);
	scatter = pow3RGB(scatter, _Contrast);
	
	COLOR = finalColor;
}
