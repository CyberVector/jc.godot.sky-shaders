//===========================================================
// Atmospheric Scattering based on Hoffman and pretham paper.
// Semi artistic control.
// License:
// 	J. Cuellar MIT License.
//===========================================================
shader_type sky;

// Params.
//------------------------------------------------------------------------------

// General.
uniform float _TonemapLevel: hint_range(0.0, 1.0) = 1.0;
uniform float _Contrast: hint_range(0.0, 1.0) = 0.0;
uniform float _Darkness: hint_range(0.0, 1.0) = 0.5;
uniform float _Exposure = 1.0;

// Intensity.
uniform float _SunIntensity = 40.0;
uniform float _NightIntensity = 0.1;

// Tint.
uniform vec4 _DayTint: hint_color = vec4(1.0);
uniform vec4 _NightTint: hint_color = vec4(0.0, 0.19, 0.36, 1.0);
uniform vec4 _SunsetDawnTint: hint_color = vec4(0.96, 0.26, 0.07, 1.0);

// Zenith.
uniform float _Thickness = 1.0;
uniform float _ZenithOffset: hint_range(0.0, 1.0) = 0.0;
uniform float _HorizonLevel: hint_range(0.0, 1.0) = 1.0;

// _Mie.
uniform float _Mie = 0.03;
uniform float _Turbidity = 0.001;

// Sun Mie.
uniform vec4 _SunMieTint: hint_color;
uniform float _SunMieIntensity = 1.0;
uniform float _SunMieAnisotropy: hint_range(0.0, 0.9999);

// Sun Disk.
uniform vec4 _SunDiskTint: hint_color = vec4(0.99, 0.49, 0.22, 1.0);
uniform float _SunDiskIntensity = 1.0;
uniform float _SunDiskSize = 0.022;


// Constants.
//------------------------------------------------------------------------------

// PI.
const float kPI = 3.1415927;     // π.
const float kTAU = 6.2831853;    // π * 2.
const float kPIRCP = 0.3183098;  // 1/π.
const float kPI4 = 12.5663706;   // PI(π)*4.
const float kPI4RCP = 0.0795775; // 1/(PI(π)*4).
const float k3PI16 = 0.0596831;  // 3/(PI(π)*16).

// Zenith length.
const float kRayleighZenithLength = 8.4e3;
const float kMieZenithLength = 1.25e3;

// Beta Ray.
const vec3 kBetaRay = vec3(5.807035e-06, 1.356874e-05, 3.312679e-05);
const vec3 kBetaMie = vec3(0.000434);

// Functions.
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

vec3 filmicTonemap(vec3 real, in float exposure, in float lv)
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

float miePhase(float mult, float mu, float g)
{
	vec3 phg = partialMiePhase(g);
	return (mult * phg.x * ((1.0 + mu * mu) * 
		pow(phg.y - (phg.z * mu), -1.5))) * _SunMieIntensity;
}

float rayleighPhase(float mu)
{
	return k3PI16 * (1.0 + mu * mu);
}

void computeOpticalDepth(float side, out float sr, out float sm)
{
	side = saturateReal(side * _HorizonLevel);
	side = max(0.0, side);
	
	float zenith = acos(side);
	zenith = cos(zenith) + 0.15 * pow(93.885 - ((zenith * 180.0) / kPI), -1.253);
	zenith = 1.0 / (zenith + (_ZenithOffset * 0.5));
	
	sr = zenith * kRayleighZenithLength;
	sm = zenith * kMieZenithLength;
}

void computeFastOpticalDepth(float side, out float sr, out float sm)
{
	side = max(0.03, side + 0.025);
	side = saturateReal(side * _HorizonLevel);
	side = 1.0 / (side + _ZenithOffset);
		
	sr = side * kRayleighZenithLength;
	sm = side * kMieZenithLength;
}

vec3 atmosphericScattering(float sr, float sm, float mu)
{
	vec3 betaMie = _Mie * _Turbidity * kBetaMie;
	vec3 betaRay = kBetaRay * _Thickness; 
	
	vec3 extinctionFactor = exp(-(betaRay * sr + betaMie * sm));
	extinctionFactor = saturateRGB(extinctionFactor);
	
	vec3 finalExtinctionFactor = mix(1.0 - extinctionFactor, 
		(1.0 - extinctionFactor) * extinctionFactor, saturateReal(1.0 - LIGHT0_DIRECTION.y));
	
	float sunRayleighPhase = rayleighPhase(mu);
	
	vec3 sunBRT = betaRay * sunRayleighPhase;
	vec3 sunBMT = betaMie * (miePhase(kPI4, mu, _SunMieAnisotropy) * _SunMieIntensity) * _SunMieTint.rgb;
	
	vec3 sunBRMT = (sunBRT + sunBMT) / (betaRay + betaMie);
	
	vec3 scatter = _SunIntensity * (sunBRMT * finalExtinctionFactor) * _DayTint.rgb;
	scatter *= saturateReal(LIGHT0_DIRECTION.y + 0.45);
	scatter = mix(scatter, scatter * ( 1.0 - extinctionFactor), _Darkness);
	
	float st = saturateReal(1.0 - (LIGHT0_DIRECTION.y + 0.40));
	vec3 sunsetCol = mix(_DayTint.rgb, _SunsetDawnTint.rgb, st);
	
	vec3 nightScatter = (1.0 - extinctionFactor) * 
		saturateReal((-LIGHT0_DIRECTION.y + 0.30)) * _NightTint.rgb * _NightIntensity;
	
	return (scatter * sunsetCol) + nightScatter;
}

void fragment()
{
	
	float y = dot(vec3(0.0, 1.0, 0.0), EYEDIR);
	
	float sr; float sm;
	computeFastOpticalDepth(y, sr, sm);
	
	float mu = dot(normalize(LIGHT0_DIRECTION), EYEDIR);
	
	vec3 scatter = atmosphericScattering(sr, sm, mu);
	
	scatter = filmicTonemap(scatter, _Exposure, _TonemapLevel);
	scatter = pow3RGB(scatter, _Contrast);
	scatter += sunDisk(_SunDiskSize, LIGHT0_DIRECTION, EYEDIR) * _SunDiskTint.rgb * 
		_SunDiskIntensity * scatter;
	
	//if(y > 0.0)
	//	COLOR = scatter;
	//else 
	//	COLOR = vec3(0.0);
	
	COLOR = scatter;
}