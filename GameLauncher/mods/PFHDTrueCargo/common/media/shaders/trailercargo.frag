#version 110

// Trailer Cargo: vanilla's basicEffect.frag, lit the way a dropped item is.
//
// A vehicle sub-model reaches this shader with AmbientColour set to the
// square's light at full strength plus the square's light sources
// (Model.DrawVehicle), while a dropped item gets the same light times 0.4,
// no square lights plus one fixed lamp at 0.375 of it
// (ItemModelRenderer.java:713-746). Cargo drawn with the vehicle inputs
// came out 2.5x brighter than the same item on the ground, with no shading.
// This reproduces the item path: 0.4 ambient plus one lamp from above and
// a little towards the camera, in view space, so every item on the bed is
// shaded the same way however it lies. The five square lights are ignored,
// as the item path ignores them; the square's own light already carries
// what lamps and the sun put on that square.

varying vec3 vertColour;
varying vec3 vertNormal;
varying vec3 viewNormal;
varying vec2 texCoords;

uniform sampler2D Texture;
uniform float Alpha;
uniform float LightingAmount;
uniform vec3 TintColour;
uniform vec3 AmbientColour;
uniform vec3 Light0Direction;
uniform vec3 Light0Colour;
uniform vec3 Light1Direction;
uniform vec3 Light1Colour;
uniform vec3 Light2Direction;
uniform vec3 Light2Colour;
uniform vec3 Light3Direction;
uniform vec3 Light3Colour;
uniform vec3 Light4Direction;
uniform vec3 Light4Colour;
uniform float HueChange;

// util/math + util/hueShift, inlined so nothing depends on how a mod's
// shader folder resolves an #include.
vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 hueShift(vec3 col, float amount)
{
    vec3 col3 = rgb2hsv(col);
    col3.r += amount;
    while (col3.r > 1.0) { col3.r -= 2.0; }
    while (col3.r < -1.0) { col3.r += 2.0; }
    return hsv2rgb(col3);
}

void main()
{
	vec3 normal = normalize(viewNormal);

	vec4 texSample = texture2D(Texture, texCoords);
	if (texSample.w < 0.01)
	{
	    discard;
	}

	vec3 col = texSample.xyz;
	if (HueChange != 0.0)
	{
	    col = hueShift(col, HueChange);
	}

	// The item path's lamp: ambient / 4 * 1.5 at a radius nothing reaches.
	// Its direction is (0, 0.928, -0.371) in the item's own frame; here it
	// is fixed in view space, up and towards the viewer.
	vec3 lamp = normalize(vec3(0.0, 0.928, 0.371));
	float dotprod = max(dot(normal, lamp), 0.0);
	vec3 lighting = AmbientColour * 0.4 + AmbientColour * 0.375 * dotprod;
	lighting.x = min(lighting.x, 1.0);
	lighting.y = min(lighting.y, 1.0);
	lighting.z = min(lighting.z, 1.0);

	col = vec3(col.x * TintColour.x * lighting.x, col.y * TintColour.y * lighting.y, col.z * TintColour.z * lighting.z);

	gl_FragColor = vec4(Alpha * col * vertColour, Alpha * texSample.w);
}
