#version 110

// Trailer Cargo (SPIKE): a car model drawn on a car trailer from a skin that
// bakes its colour (KI5's damn_vehicle_shader has no paint step): the
// texture as it is, lit like the swatch shaders.

varying vec3 vertColour;
varying vec3 vertNormal;
varying vec3 viewNormal;
varying vec2 texCoords;

uniform sampler2D Texture;
uniform float Alpha;
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

float lit(vec3 normal, vec3 dir)
{
    float d = max(dot(normal, normalize(dir)), 0.0);
    return ceil(d * 3.0) / 3.0;
}

void main()
{
    vec3 normal = normalize(vertNormal);
    vec4 tex = texture2D(Texture, texCoords);
    vec3 col = tex.xyz;

    vec3 lighting = AmbientColour;
    lighting += Light0Colour * lit(normal, Light0Direction);
    lighting += Light1Colour * lit(normal, Light1Direction);
    lighting += Light2Colour * lit(normal, Light2Direction);
    lighting += Light3Colour * lit(normal, Light3Direction);
    lighting += Light4Colour * lit(normal, Light4Direction);
    lighting = clamp(lighting, 0.0, 1.0);
    vec3 grey = vec3(dot(vec3(0.2126, 0.7152, 0.0722), TintColour));
    vec3 tint = mix(TintColour, grey, 0.3);

    col *= lighting * tint;
    gl_FragColor = vec4(Alpha * col, Alpha);
}
