//
//  NBShaderUtils.h
//  NBGLViewDemo
//
//  Created by liu enbao on 27/10/2018.
//  Copyright © 2018 liu enbao. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <OpenGLES/ES2/gl.h>

@interface NBShaderUtils : NSObject

// Create a shader object, load the shader source string, and compile the shader.
//
+(GLuint)loadShader:(GLenum)type withString:(NSString *)shaderString;

+(GLuint)loadShader:(GLenum)type withFilepath:(NSString *)shaderFilepath;

//
///
/// Load a vertex and fragment shader, create a program object, link program.
/// Errors output to log.
/// vertexShaderFilepath Vertex shader source file path.
/// fragmentShaderFilepath Fragment shader source file path
/// return A new program object linked with the vertex/fragment shader pair, 0 on failure
//
+(GLuint)loadProgram:(NSString *)vertexShaderFilepath withFragmentShaderFilepath:(NSString *)fragmentShaderFilepath;

@end
