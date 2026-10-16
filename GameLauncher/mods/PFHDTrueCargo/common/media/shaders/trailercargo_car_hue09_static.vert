#version 330

// Trailer Cargo: vanilla's basicEffect_static.vert plus a view-space
// normal for trailercargo.frag. Everything else is verbatim.

layout (location = 0) in vec4 vertex;
layout (location = 1) in vec4 normal;
layout (location = 2) in vec2 uv;

out vec3 vertColour;
out vec3 vertNormal;
out vec3 viewNormal;
out vec2 texCoords;

uniform mat4 ModelViewProjection;
uniform mat4 transform;
uniform float targetDepth = 0.5;
uniform float DepthBias;

uniform vec2 UVScale;
uniform float HighResDepthMultiplier = 0.0;
uniform float FinalScale = 1.0;

void main()
{
	vec4 position = vec4(vertex.xyz, 1);
	vec4 normal = vec4(normal.xyz, 0);

	texCoords = uv.st * UVScale.xy;

	vertNormal = (transform * normal).xyz;
	// See trailercargo.vert: a view-space direction is fixed in the world.
	viewNormal = mat3(ModelViewProjection) * vertNormal;
	vertColour = vec3(1,1,1);

	vec4 positionScaled = transform * position;
	positionScaled.xyz *= FinalScale;
	vec4 o = ModelViewProjection * positionScaled;

	vec4 origin = ModelViewProjection * vec4(0, 0, 0, 1);
	o.z += (origin.z - o.z) * HighResDepthMultiplier;

	float clip = ((o.z+1.0) / 2.0);
	clip += targetDepth - 0.5;
	o.z = (clip*2)-1;

	gl_Position = o;
}
