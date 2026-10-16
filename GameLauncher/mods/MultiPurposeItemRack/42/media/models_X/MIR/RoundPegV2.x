xof 0303txt 0032
template ColorRGBA { <35ff44e0-6c7c-11cf-8f52-0040333594a3> FLOAT red; FLOAT green; FLOAT blue; FLOAT alpha; }
template ColorRGB { <d3e16e81-7835-11cf-8f52-0040333594a3> FLOAT red; FLOAT green; FLOAT blue; }
template Material { <3d82ab4d-62da-11cf-ab39-0020af71e433> ColorRGBA faceColor; FLOAT power; ColorRGB specularColor; ColorRGB emissiveColor; [...] }
template TextureFilename { <a42790e1-7810-11cf-8f52-0040333594a3> STRING filename; }
template Frame { <3d82ab46-62da-11cf-ab39-0020af71e433> [...] }
template Matrix4x4 { <f6f23f45-7686-11cf-8f52-0040333594a3> array FLOAT matrix[16]; }
template FrameTransformMatrix { <f6f23f41-7686-11cf-8f52-0040333594a3> Matrix4x4 frameMatrix; }
template Vector { <3d82ab5e-62da-11cf-ab39-0020af71e433> FLOAT x; FLOAT y; FLOAT z; }
template MeshFace { <3d82ab5f-62da-11cf-ab39-0020af71e433> DWORD nFaceVertexIndices; array DWORD faceVertexIndices[nFaceVertexIndices]; }
template Mesh { <3d82ab44-62da-11cf-ab39-0020af71e433> DWORD nVertices; array Vector vertices[nVertices]; DWORD nFaces; array MeshFace faces[nFaces]; [...] }
template MeshNormals { <f6f23f43-7686-11cf-8f52-0040333594a3> DWORD nNormals; array Vector normals[nNormals]; DWORD nFaceNormals; array MeshFace faceNormals[nFaceNormals]; }
template MeshMaterialList { <f6f23f42-7686-11cf-8f52-0040333594a3> DWORD nMaterials; DWORD nFaceIndexes; array DWORD faceIndexes[nFaceIndexes]; [Material <3d82ab4d-62da-11cf-ab39-0020af71e433>] }
template Coords2d { <f6f23f44-7686-11cf-8f52-0040333594a3> FLOAT u; FLOAT v; }
template MeshTextureCoords { <f6f23f40-7686-11cf-8f52-0040333594a3> DWORD nTextureCoords; array Coords2d textureCoords[nTextureCoords]; }

Material MIR_Wood_Material {
 1.0;1.0;1.0;1.0;; 4.0; 0.04;0.04;0.04;; 0.0;0.0;0.0;;
 TextureFilename { "Wood.png"; }
}

Frame MIR_RoundPegV2 {
 FrameTransformMatrix { 1.0,0.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,0.0,1.0;; }
 Mesh MIR_RoundPegV2 {
  18;
   0.000000;0.005000; 0.000000;,
   0.018000;0.005000; 0.000000;, 0.012728;0.005000; 0.012728;, 0.000000;0.005000; 0.018000;,-0.012728;0.005000; 0.012728;,
  -0.018000;0.005000; 0.000000;,-0.012728;0.005000;-0.012728;, 0.000000;0.005000;-0.018000;, 0.012728;0.005000;-0.012728;,
   0.000000;0.035000; 0.000000;,
   0.018000;0.035000; 0.000000;, 0.012728;0.035000; 0.012728;, 0.000000;0.035000; 0.018000;,-0.012728;0.035000; 0.012728;,
  -0.018000;0.035000; 0.000000;,-0.012728;0.035000;-0.012728;, 0.000000;0.035000;-0.018000;, 0.012728;0.035000;-0.012728;;
  32;
  3;0,2,1;,3;0,3,2;,3;0,4,3;,3;0,5,4;,3;0,6,5;,3;0,7,6;,3;0,8,7;,3;0,1,8;,
  3;9,10,11;,3;9,11,12;,3;9,12,13;,3;9,13,14;,3;9,14,15;,3;9,15,16;,3;9,16,17;,3;9,17,10;,
  3;1,2,11;,3;1,11,10;,3;2,3,12;,3;2,12,11;,3;3,4,13;,3;3,13,12;,3;4,5,14;,3;4,14,13;,
  3;5,6,15;,3;5,15,14;,3;6,7,16;,3;6,16,15;,3;7,8,17;,3;7,17,16;,3;8,1,10;,3;8,10,17;;
  MeshNormals {
   10;
   0.0;-1.0;0.0;,0.0;1.0;0.0;,
   0.923880;0.0;0.382683;,0.382683;0.0;0.923880;,-0.382683;0.0;0.923880;,-0.923880;0.0;0.382683;,
  -0.923880;0.0;-0.382683;,-0.382683;0.0;-0.923880;,0.382683;0.0;-0.923880;,0.923880;0.0;-0.382683;;
   32;
   3;0,0,0;,3;0,0,0;,3;0,0,0;,3;0,0,0;,3;0,0,0;,3;0,0,0;,3;0,0,0;,3;0,0,0;,
   3;1,1,1;,3;1,1,1;,3;1,1,1;,3;1,1,1;,3;1,1,1;,3;1,1,1;,3;1,1,1;,3;1,1,1;,
   3;2,2,2;,3;2,2,2;,3;3,3,3;,3;3,3,3;,3;4,4,4;,3;4,4,4;,3;5,5,5;,3;5,5,5;,
   3;6,6,6;,3;6,6,6;,3;7,7,7;,3;7,7,7;,3;8,8,8;,3;8,8,8;,3;9,9,9;,3;9,9,9;;
  }
  MeshMaterialList {
   1;32;
   0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0;;
   { MIR_Wood_Material }
  }
  MeshTextureCoords MIR_RoundPegV2_UV {
   18;
   0.5;0.5;,
   1.0;0.5;,0.8536;0.8536;,0.5;1.0;,0.1464;0.8536;,0.0;0.5;,0.1464;0.1464;,0.5;0.0;,0.8536;0.1464;,
   0.5;0.5;,
   1.0;0.5;,0.8536;0.8536;,0.5;1.0;,0.1464;0.8536;,0.0;0.5;,0.1464;0.1464;,0.5;0.0;,0.8536;0.1464;;
  }
 }
}
