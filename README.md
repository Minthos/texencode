# texencode
glsl compute shader for texture block compression

input texture should be RGBA with power of 2 dimensions (must be divisible by 16 in both dimensions, I have only tested it with 512, 1024 and 2048 square textures)

```cpp

void Renderer::compressTexture(GLuint inputTexture, GLuint outputBuffer, int width, int height) {
    glUseProgram(texencodeProgram_);
    glBindTexture(GL_TEXTURE_2D, inputTexture);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, outputBuffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, outputBuffer);
    glDispatchCompute(width / 16, height / 16, 1);
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);
}

void Renderer::decompressTexture(GLuint inputBuffer, GLuint outputTexture, int width, int height) {
    glUseProgram(texdecodeProgram_);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, inputBuffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, inputBuffer);
    glBindImageTexture(0, outputTexture, 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA8);
    glDispatchCompute(width / 16, height / 16, 1);
    glMemoryBarrier(GL_TEXTURE_UPDATE_BARRIER_BIT);
}

struct TextureInfo {
    GLuint id;
    int width;
    int height;
};

TextureInfo loadTexture(const char* filename) {
    int width, height, channels;
    unsigned char* data = stbi_load(filename, &width, &height, &channels, 0);
    if (!data) {
        std::cerr << "Failed to load texture " << filename << std::endl;
        exit(1);
    }
    uint32_t texture;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    std::cout << "loaded texture " << filename << " with " << channels << " channels\n";
    GLint format = GL_RGBA;
    glTexImage2D(GL_TEXTURE_2D, 0, format, width, height, 0, format, GL_UNSIGNED_BYTE, data);
    stbi_image_free(data);
    return {texture, width, height};
}

void mkbuf(GLuint number, GLuint* handle, GLuint size, void* data, GLenum flag) {
    glGenBuffers(1, handle);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, *handle);
    glBufferData(GL_SHADER_STORAGE_BUFFER, size, data, flag);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, number, *handle);
}

mkbuf(15, &compressedTexture_.id, (texture0_.width * texture0_.height * 6) / 8, nullptr, GL_DYNAMIC_DRAW);

```
