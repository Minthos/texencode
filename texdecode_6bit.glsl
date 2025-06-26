#version 460

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

uniform writeonly image2D outputTexture;

layout(std430, binding = 0) readonly buffer InputBuffer {
    uint data[];
};

const int BLOCK_SIZE = 16;
const int PALETTE_SIZE = 16;

void main() {
    ivec2 pixelCoord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 blockIdx = pixelCoord / BLOCK_SIZE;
    ivec2 localCoord = pixelCoord % BLOCK_SIZE;
    uint numBlocksX = imageSize(outputTexture).x / BLOCK_SIZE;
    uint byteOffset = (blockIdx.y * numBlocksX + blockIdx.x) * 48;
    uint pixelIdx = localCoord.x % 4 + (localCoord.x / 4) * 16 +
                    (localCoord.y % 4) * 4 + (localCoord.y / 4) * 64;
    uint indexSlot = pixelIdx / 8;
    uint indexShift = (pixelIdx % 8) * 4;
    uint paletteIndex = (data[byteOffset + 16 + indexSlot] >> indexShift) & 0xF;
    imageStore(outputTexture, pixelCoord, unpackUnorm4x8(data[byteOffset + paletteIndex]));
}

