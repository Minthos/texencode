#version 460
layout(local_size_x = 4, local_size_y = 4, local_size_z = 1) in;

uniform sampler2D inputTexture;
layout(std430, binding = 0) buffer OutputBuffer { uint data[]; };

const int BLOCK_SIZE = 16;
const int PALETTE_SIZE = 16;

shared vec4 palette[PALETTE_SIZE];
shared vec4 candidateColors[64];
shared float sCounts[16];

float colorDistance(vec4 a, vec4 b) {
    vec4 diff = a - b;
    return abs(diff.x) + abs(diff.y) + abs(diff.z) + abs(diff.w);
}

vec4 pixel(uint idx) {
    uint y = idx / 16;
    uint x = idx % 16;
    ivec2 texCoord = ivec2(gl_WorkGroupID.xy) * BLOCK_SIZE + ivec2(x, y);
    return texelFetch(inputTexture, texCoord, 0);
}

void main() {
    uint localIdx = gl_LocalInvocationIndex;
    uvec2 texSize = textureSize(inputTexture, 0);
    uint byteOffset = (gl_WorkGroupID.y * (texSize.x / BLOCK_SIZE) + gl_WorkGroupID.x) * 48;

    // Each thread generates 4 candidate colors
    uint xOffset = 4 * (localIdx & 3); // 4x4 pixel region per thread
    uint yOffset = 16 * 4 * (localIdx >> 2);
    vec4 avg = vec4(0.0);
    vec4 lpixels[16];
    for(uint y = 0; y < 4; y++) {
        for(uint x = 0; x < 4; x++) {
            uint idx = y * 16 + x;
            uint lidx = y * 4 + x;
            vec4 p = pixel(idx + yOffset + xOffset);
            lpixels[lidx] = p;
            avg += p;
        }
    }
    avg *= 0.0625; // Divide by 16
    vec4 c[4];
    c[0] = avg;
    // initialize all the values in case every input pixel is identical to avoid glitching
    c[1] = vec4(1.0, 0.0, 0.0, 1.0);
    c[2] = vec4(0.0, 1.0, 0.0, 1.0);
    c[3] = vec4(0.0, 0.0, 1.0, 1.0);
    float bestDist = 1e36;
    // First candidate is the pixel closest to the average
    for (uint y = 0; y < 4; y++) {
        for (uint x = 0; x < 4; x++) {
            uint idx = y * 16 + x;
            uint lidx = y * 4 + x;
            float d = colorDistance(lpixels[lidx], avg);
            if(d < bestDist) {
                c[0] = lpixels[lidx];
                bestDist = d;
            }
        }
    }
    // Next 3 candidates are the pixels furthest from existing candidates
    for(uint j = 1; j < 4; j++) {
        bestDist = 0.0;
        for (uint y = 0; y < 4; y++) {
            for (uint x = 0; x < 4; x++) {
                uint idx = y * BLOCK_SIZE + x;
                uint lidx = y * 4 + x;
                float closestDist = 1e36;
                for(uint k = 0; k < j; k++) {
                    float d = colorDistance(lpixels[lidx], c[k]);
                    closestDist = min(closestDist, d);
                }
                if(closestDist > bestDist) {
                    c[j] = lpixels[lidx];
                    bestDist = closestDist;
                }
            }
        }
    }
    // one pass of k-means clustering
    float counts[4];
    vec4 averages[4];
    for(uint i = 0; i < 4; i++) {
        counts[i] = 0.0;
        averages[i] = vec4(0);
    }
    for (uint y = 0; y < 4; y++) {
        for (uint x = 0; x < 4; x++) {
            uint idx = y * BLOCK_SIZE + x;
            uint lidx = y * 4 + x;
            float closestDist = 1e36;
            uint closestIdx = 0;
            vec4 closestColor = vec4(0);
            for(uint k = 0; k < 4; k++) {
                float d = colorDistance(lpixels[lidx], c[k]);
                if(d < closestDist){
                    closestDist = d;
                    closestIdx = k;
                    closestColor = lpixels[lidx];
                }
            }
            counts[closestIdx]++;
            averages[closestIdx] += closestColor;
        }
    }
    float highestCount = 0;
    uint highestIdx = 0;
    for(uint i = 0; i < 4; i++) {
        if(counts[i] > highestCount) {
            highestCount = counts[i];
            highestIdx = i;
        }
    }
    c[0] = averages[highestIdx] / max(1.0, counts[highestIdx]);
    sCounts[localIdx] = highestCount;
    for(uint i = 0; i < 4; i++) {
        candidateColors[localIdx * 4 + i] = c[i];
    }

    barrier();

    // keep the biggest cluster from each block of 8x8 pixels
    if(localIdx < 4) {
        uint heaviestIdx = 0;
        float highestCount = 0.0;
        for(uint y = 0; y < 2; y++){
            for(uint x = 0; x < 2; x++){
                uint idx = ((localIdx * 2) % 4) + ((localIdx / 2) * 8) + x + y * 4;
                if(sCounts[idx] > highestCount){
                    highestCount = sCounts[idx];
                    heaviestIdx = idx;
                }
            }
        }
        palette[localIdx] = candidateColors[heaviestIdx * 4];
    }

    barrier();

    for(uint i = 4; i < 16; i++) {
        bestDist = 0.0;
        uint lwinner = 0;
        for(uint j = 0; j < 64; j++) {
            vec4 C = candidateColors[j];
            float closestDist = 1e36;
            for(uint k = 0; k < i; k++) {
                float d = colorDistance(C, palette[k]);
                closestDist = min(closestDist, d);
            }
            if(closestDist > bestDist) {
                lwinner = j;
                bestDist = closestDist;
            }
        }
        palette[i] = candidateColors[lwinner];
    }

    // assign colors to pixels
    uint indices[16];
    for(uint y = 0; y < 4; y++) {
        for(uint x = 0; x < 4; x++) {
            uint lidx = y * 4 + x;
            vec4 C = lpixels[lidx];
            // Find the closest palette color
            uint closestIdx = 0;
            float closestDist = 1e36;
            for (uint i = 0; i < PALETTE_SIZE; i++) {
                float dist = colorDistance(C, palette[i]);
                if(dist < closestDist) {
                    closestDist = dist;
                    closestIdx = i;
                }
            }
            indices[lidx] = closestIdx;
        }
    }
    // Store palette
    byteOffset = (gl_WorkGroupID.y * (texSize.x / BLOCK_SIZE) + gl_WorkGroupID.x) * 48;
    data[byteOffset + localIdx] = packUnorm4x8(palette[localIdx]);
    // Pack indices
    uint index1 =
        ((indices[0] & 0xF) <<  0) | ((indices[1] & 0xF) <<  4) |
        ((indices[2] & 0xF) <<  8) | ((indices[3] & 0xF) << 12) |
        ((indices[4] & 0xF) << 16) | ((indices[5] & 0xF) << 20) |
        ((indices[6] & 0xF) << 24) | ((indices[7] & 0xF) << 28);
    uint index2 =
        ((indices[8] & 0xF) <<  0) | ((indices[9] & 0xF) <<  4) |
        ((indices[10] & 0xF) <<  8) | ((indices[11] & 0xF) << 12) |
        ((indices[12] & 0xF) << 16) | ((indices[13] & 0xF) << 20) |
        ((indices[14] & 0xF) << 24) | ((indices[15] & 0xF) << 28);
    data[byteOffset + 16 + localIdx * 2] = index1;
    data[byteOffset + 17 + localIdx * 2] = index2;
}
