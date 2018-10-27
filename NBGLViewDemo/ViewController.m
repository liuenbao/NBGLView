//
//  ViewController.m
//  NBGLViewDemo
//
//  Created by liu enbao on 27/10/2018.
//  Copyright © 2018 liu enbao. All rights reserved.
//

#import "ViewController.h"
#import "NBGLView.h"
#import "NBShaderUtils.h"
#include "GLESMath.h"

static GLfloat attrArr[] =
{
    -0.5f, 0.5f, 0.0f, 1.0f, 0.0f, 1.0f, //左上
    0.5f, 0.5f, 0.0f, 1.0f, 0.0f, 1.0f, //右上
    -0.5f, -0.5f, 0.0f, 1.0f, 1.0f, 1.0f, //左下
    0.5f, -0.5f, 0.0f, 1.0f, 1.0f, 1.0f, //右下
    0.0f, 0.0f, -1.0f, 0.0f, 1.0f, 0.0f, //顶点
};

static GLuint indices[] =
{
    0, 3, 2,
    0, 1, 3,
    0, 2, 4,
    0, 4, 1,
    2, 3, 4,
    1, 4, 3,
};

@interface ViewController () <NBGLRenderer> {
    NBGLView* nbGLView;
    GLuint nbProgram;
    
    GLuint attrBuffer;
    GLuint position;
    GLuint positionColor;
    
    GLuint projectionMatrixSlot;
    GLuint modelViewMatrixSlot;
    GLuint fSaturation;
    
    float saturation;
    float degree;
    float yDegree;
    
    NSInteger nbWidth;
    NSInteger nbHeight;
}

@end

@implementation ViewController

- (void)loadView {
    self.view = nbGLView = [[NBGLView alloc] init];
    [nbGLView setRenderer:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)glRenderCreated:(NBGLView*)view {
    NSString* vertFile = [[NSBundle mainBundle] pathForResource:@"shaderv" ofType:@"glsl"];
    NSString* fragFile = [[NSBundle mainBundle] pathForResource:@"shaderf" ofType:@"glsl"];
    
    nbProgram = [NBShaderUtils loadProgram:vertFile withFragmentShaderFilepath:fragFile];
    glUseProgram(nbProgram);
    
    glGenBuffers(1, &attrBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, attrBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(attrArr), attrArr, GL_DYNAMIC_DRAW);
    
    position = glGetAttribLocation(nbProgram, "position");
    glVertexAttribPointer(position, 3, GL_FLOAT, GL_FALSE, sizeof(GLfloat) * 6, NULL);
    glEnableVertexAttribArray(position);
    
    positionColor = glGetAttribLocation(nbProgram, "positionColor");
    glVertexAttribPointer(positionColor, 3, GL_FLOAT, GL_FALSE, sizeof(GLfloat) * 6, (float *)NULL + 3);
    glEnableVertexAttribArray(positionColor);
    
    saturation = 0.5f;
    degree = 0.0f;
    yDegree = 0.0f;
    
    fSaturation = glGetUniformLocation(nbProgram, "saturation");
    glUniform1f(fSaturation, saturation);
    
    projectionMatrixSlot = glGetUniformLocation(nbProgram, "projectionMatrix");
    modelViewMatrixSlot = glGetUniformLocation(nbProgram, "modelViewMatrix");
    
    glEnable(GL_DEPTH_TEST);
    
    glClearColor(0, 0.0, 0, 1.0);
}

- (void)glRenderSizeChanged:(NBGLView*)view width:(NSInteger)width height:(NSInteger)height {
    nbWidth = width;
    nbHeight = height;
}

- (void)glRenderDrawFrame:(NBGLView*)view {
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    KSMatrix4 _projectionMatrix;
    ksMatrixLoadIdentity(&_projectionMatrix);
    float aspect = nbWidth / nbHeight;
    
    ksPerspective(&_projectionMatrix, 30.0, aspect, -5.0f, 20.0f); //透视变换
    
    // Load projection matrix
    glUniformMatrix4fv(projectionMatrixSlot, 1, GL_FALSE, (GLfloat*)&_projectionMatrix.m[0][0]);
    
    glEnable(GL_DEPTH_TEST);
    
    KSMatrix4 _modelViewMatrix;
    ksMatrixLoadIdentity(&_modelViewMatrix);
    
    ksTranslate(&_modelViewMatrix, 0.0, 0.0, 0.0);
    
    KSMatrix4 _rotationMatrix;
    ksMatrixLoadIdentity(&_rotationMatrix);
    
    ksRotate(&_modelViewMatrix, degree, 1.0, 0.0, 0.0);
    ksRotate(&_modelViewMatrix, yDegree, 0.0, 1.0, 0.0);
    
    
    ksMatrixMultiply(&_modelViewMatrix, &_rotationMatrix, &_modelViewMatrix);
    
    // Load the model-view matrix
    glUniformMatrix4fv(modelViewMatrixSlot, 1, GL_FALSE, (GLfloat*)&_modelViewMatrix.m[0][0]);
    
    glDrawElements(GL_TRIANGLES, sizeof(indices) / sizeof(indices[0]), GL_UNSIGNED_INT, indices);
}

- (void)glRenderDestroy:(NBGLView*)view {
    glDeleteBuffers(1, &attrBuffer);
    
    glDeleteProgram(nbProgram);
}

@end
