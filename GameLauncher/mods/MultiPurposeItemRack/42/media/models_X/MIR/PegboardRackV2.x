xof 0303txt 0032
template ColorRGBA {
 <35ff44e0-6c7c-11cf-8f52-0040333594a3>
 FLOAT red; FLOAT green; FLOAT blue; FLOAT alpha;
}
template ColorRGB {
 <d3e16e81-7835-11cf-8f52-0040333594a3>
 FLOAT red; FLOAT green; FLOAT blue;
}
template Material {
 <3d82ab4d-62da-11cf-ab39-0020af71e433>
 ColorRGBA faceColor; FLOAT power; ColorRGB specularColor; ColorRGB emissiveColor; [...]
}
template TextureFilename {
 <a42790e1-7810-11cf-8f52-0040333594a3>
 STRING filename;
}
template Frame {
 <3d82ab46-62da-11cf-ab39-0020af71e433>
 [...]
}
template Matrix4x4 {
 <f6f23f45-7686-11cf-8f52-0040333594a3>
 array FLOAT matrix[16];
}
template FrameTransformMatrix {
 <f6f23f41-7686-11cf-8f52-0040333594a3>
 Matrix4x4 frameMatrix;
}
template Vector {
 <3d82ab5e-62da-11cf-ab39-0020af71e433>
 FLOAT x; FLOAT y; FLOAT z;
}
template MeshFace {
 <3d82ab5f-62da-11cf-ab39-0020af71e433>
 DWORD nFaceVertexIndices; array DWORD faceVertexIndices[nFaceVertexIndices];
}
template Mesh {
 <3d82ab44-62da-11cf-ab39-0020af71e433>
 DWORD nVertices; array Vector vertices[nVertices]; DWORD nFaces; array MeshFace faces[nFaces]; [...]
}
template MeshNormals {
 <f6f23f43-7686-11cf-8f52-0040333594a3>
 DWORD nNormals; array Vector normals[nNormals]; DWORD nFaceNormals; array MeshFace faceNormals[nFaceNormals];
}
template MeshMaterialList {
 <f6f23f42-7686-11cf-8f52-0040333594a3>
 DWORD nMaterials; DWORD nFaceIndexes; array DWORD faceIndexes[nFaceIndexes]; [Material <3d82ab4d-62da-11cf-ab39-0020af71e433>]
}
template Coords2d {
 <f6f23f44-7686-11cf-8f52-0040333594a3>
 FLOAT u; FLOAT v;
}
template MeshTextureCoords {
 <f6f23f40-7686-11cf-8f52-0040333594a3>
 DWORD nTextureCoords; array Coords2d textureCoords[nTextureCoords];
}

Material MIR_PegboardRackV2_Material {
 1.0;1.0;1.0;1.0;;
 4.0;
 0.04;0.04;0.04;;
 0.0;0.0;0.0;;
 TextureFilename { "Pegboard.png"; }
}

Frame MIR_PegboardRackV2 {
 FrameTransformMatrix {
  1.0,0.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,0.0,1.0;;
 }
 Mesh MIR_PegboardRackV2 {
  8;
  -0.460000;-0.035000;0.080000;,
   0.460000;-0.035000;0.080000;,
   0.460000; 0.035000;0.080000;,
  -0.460000; 0.035000;0.080000;,
  -0.460000;-0.035000;0.840000;,
   0.460000;-0.035000;0.840000;,
   0.460000; 0.035000;0.840000;,
  -0.460000; 0.035000;0.840000;;
  12;
  3;0,2,1;,3;0,3,2;,
  3;4,5,6;,3;4,6,7;,
  3;0,1,5;,3;0,5,4;,
  3;1,2,6;,3;1,6,5;,
  3;2,3,7;,3;2,7,6;,
  3;3,0,4;,3;3,4,7;;
  MeshNormals {
   6;
   0.0;0.0;-1.0;,0.0;0.0;1.0;,0.0;-1.0;0.0;,
   1.0;0.0;0.0;,0.0;1.0;0.0;,-1.0;0.0;0.0;;
   12;
   3;0,0,0;,3;0,0,0;,3;1,1,1;,3;1,1,1;,
   3;2,2,2;,3;2,2,2;,3;3,3,3;,3;3,3,3;,
   3;4,4,4;,3;4,4,4;,3;5,5,5;,3;5,5,5;;
  }
  MeshMaterialList {
   1;12;
   0,0,0,0,0,0,0,0,0,0,0,0;;
   { MIR_PegboardRackV2_Material }
  }
  MeshTextureCoords MIR_PegboardRackV2_UV {
   8;
   0.0;1.0;,1.0;1.0;,1.0;0.0;,0.0;0.0;,
   0.0;1.0;,1.0;1.0;,1.0;0.0;,0.0;0.0;;
  }
 }
}
