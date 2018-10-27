//
//  NBGLView.m
//  NBGLViewDemo
//
//  Created by liu enbao on 25/10/2018.
//  Copyright © 2018 liu enbao. All rights reserved.
//

#import "NBGLView.h"

#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/ES2/gl.h>

/** Global variable to hold GL errors
 * @script{ignore} */
static GLenum g_gl_error_code = GL_NO_ERROR;

// Assert macros.
#ifdef _DEBUG
#define GP_ASSERT(expression) assert(expression)
#else
#define GP_ASSERT(expression)
#endif

/**
 * GL assertion that can be used for any OpenGL function call.
 *
 * This macro will assert if an error is detected when executing
 * the specified GL code. This macro will do nothing in release
 * mode and is therefore safe to use for realtime/per-frame GL
 * function calls.
 */
/**
 * GL assertion that can be used for any OpenGL function call.
 *
 * This macro will assert if an error is detected when executing
 * the specified GL code. This macro will do nothing in release
 * mode and is therefore safe to use for realtime/per-frame GL
 * function calls.
 */
#if defined(NDEBUG) || (defined(__APPLE__) && !defined(DEBUG))
#define GL_ASSERT( gl_code ) gl_code
#else
#define GL_ASSERT( gl_code ) do \
            { \
                gl_code; \
                g_gl_error_code = glGetError(); \
                GP_ASSERT(g_gl_error_code == GL_NO_ERROR); \
            } while(0)
#endif

static NSCondition* sGLThreadManager = [[NSCondition alloc] init];

#pragma NSGLThread declare begin

@interface NBGLThread : NSThread {
    BOOL mExited;
    
    BOOL mShouldExit;
    BOOL mPaused;
    BOOL mRequestPaused;
    
    BOOL mRequestRender;
    BOOL mSizeChanged;
    BOOL mRenderComplete;
    
    BOOL mHaveEaglContext;
    
    BOOL mHasSurface;
    BOOL mFinishedCreatingEglSurface;
    BOOL mWaitingForSurface;
    BOOL mHaveEglContext;
    BOOL mHaveEglSurface;
    BOOL mShouldReleaseEglContext;
    BOOL mWantRenderNotification;
    
    int mWidth;
    int mHeight;
    int mRenderMode;
    
    BOOL mSurfaceIsBad;
    
    NBEventRunnable mFinishDrawingRunnable;
    
    // The GLContext Thared with GLView
    EAGLContext* backgroundContext;
    
    //The thread lock object
    NSMutableArray* eventQueue;
    
    // The weak ref to glView
    __weak NBGLView* mWeakGLView;
}

- (instancetype)initWithNBGLView:(NBGLView*)glView;

- (void)onWindowResize:(int)w height:(int)h;
- (void)surfaceCreated;
- (void)surfaceDestroy;
- (void)onPause;
- (void)onResume;
- (void)requestExitAndWait;

- (void)requestRender;
- (void)requestRenderAndNotify:(NBEventRunnable)finishDrawing;

- (void)queueEvent:(NBEventRunnable)runnable;

- (int)getRenderMode;
- (void)setRenderMode:(int)renderMode;

@end

#pragma NSGLThread declare end

@interface NBGLView() {
    EAGLContext* context;
    GLuint defaultFramebuffer;
    GLuint colorRenderbuffer;
    GLuint depthRenderbuffer;
    GLint framebufferWidth;
    GLint framebufferHeight;
    GLuint multisampleFramebuffer;
    GLuint multisampleRenderbuffer;
    GLuint multisampleDepthbuffer;
    BOOL oglDiscardSupported;
    
    NBGLThread* mGLThread;
    BOOL mDetached;
    
    int mSamplesCount;
}

- (BOOL)createFramebuffer;
- (void)deleteFramebuffer;

// Handle the renderer
@property (nonatomic, strong) id<NBGLRenderer> renderer;

@end

@implementation NBGLView

@synthesize context;

+ (Class) layerClass
{
    return [CAEAGLLayer class];
}

- (id) initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame]))
    {
        // A system version of 3.1 or greater is required to use CADisplayLink.
        NSString *reqSysVer = @"3.1";
        NSString *currSysVer = [[UIDevice currentDevice] systemVersion];
        if ([currSysVer compare:reqSysVer options:NSNumericSearch] != NSOrderedAscending)
        {
            // Log the system version
            NSLog(@"System Version: %@", currSysVer);
        }
        else
        {
            NSLog(@"Invalid OS Version: %s\n", (currSysVer == NULL?"NULL":[currSysVer cStringUsingEncoding:NSASCIIStringEncoding]));
            return nil;
        }
        
        // Check for OS 4.0+ features
        if ([currSysVer compare:@"4.0" options:NSNumericSearch] != NSOrderedAscending)
        {
            oglDiscardSupported = YES;
        }
        else
        {
            oglDiscardSupported = NO;
        }
        
        // Configure the CAEAGLLayer and setup out the rendering context
        CGFloat scale = [[UIScreen mainScreen] scale];
        CAEAGLLayer* layer = (CAEAGLLayer *)self.layer;
        layer.opaque = TRUE;
        layer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking,
                                    kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
        self.contentScaleFactor = scale;
        layer.contentsScale = scale;
        
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        if (!context || ![EAGLContext setCurrentContext:context])
        {
            NSLog(@"Failed to make context current.");
            return nil;
        }
        
        // Initialize Internal Defaults
        defaultFramebuffer = 0;
        colorRenderbuffer = 0;
        depthRenderbuffer = 0;
        framebufferWidth = 0;
        framebufferHeight = 0;
        multisampleFramebuffer = 0;
        multisampleRenderbuffer = 0;
        multisampleDepthbuffer = 0;
        
        mDetached = NO;
    }
    return self;
}

- (void) dealloc
{
    [mGLThread requestExitAndWait];
    
    if ([self.renderer respondsToSelector:@selector(glRenderDestroy:)]) {
        [self.renderer glRenderDestroy:self];
    }
    
    [self deleteFramebuffer];
    
    if ([EAGLContext currentContext] == context)
    {
        [EAGLContext setCurrentContext:nil];
    }
}


- (void)willMoveToSuperview:(nullable UIView *)newSuperview{
    NSLog(@"willMoveToSuperview enter");
    
    [super willMoveToSuperview:newSuperview];
    
    // Create the main framebuffer
    [self createFramebuffer];
    
    if (mDetached && (_renderer != nil)) {
        int renderMode = RENDERMODE_CONTINUOUSLY;
        if (mGLThread != nil) {
            renderMode = [mGLThread getRenderMode];
        }
        mGLThread = [[NBGLThread alloc] initWithNBGLView:self];
        if (renderMode != RENDERMODE_CONTINUOUSLY) {
            [mGLThread setRenderMode:renderMode];
        }
        [mGLThread start];
    }
    mDetached = NO;
    
    [mGLThread surfaceCreated];
    
    NSLog(@"willMoveToSuperview exit");
}

- (void)removeFromSuperview {
    NSLog(@"removeFromSuperview enter");
    
    [mGLThread surfaceDestroy];
    
    if (mGLThread != nil) {
        [mGLThread requestExitAndWait];
    }
    mDetached = YES;
    
    // remove the framebuffer
    [self deleteFramebuffer];
    
    NSLog(@"removeFromSuperview exit");
    
    [super removeFromSuperview];
}

- (void) layoutSubviews
{
    NSLog(@"layoutSubviews enter");
    
    [super layoutSubviews];
    // Called on 'resize'.
    // Mark that framebuffer needs to be updated.
    // NOTE: Current disabled since we need to have a way to reset the default frame buffer handle
    // in FrameBuffer.cpp (for FrameBuffer:bindDefault). This means that changing orientation at
    // runtime is currently not supported until we fix this.
    //updateFramebuffer = YES;
    
    [mGLThread onWindowResize:self.bounds.size.width height:self.bounds.size.height];
    
    NSLog(@"layoutSubviews exit");
}

- (BOOL)createFramebuffer
{
    // iOS Requires all content go to a rendering buffer then it is swapped into the windows rendering surface
    assert(defaultFramebuffer == 0);
    
    // Create the default frame buffer
    GL_ASSERT( glGenFramebuffers(1, &defaultFramebuffer) );
    GL_ASSERT( glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer) );
    
    // Create a color buffer to attach to the frame buffer
    GL_ASSERT( glGenRenderbuffers(1, &colorRenderbuffer) );
    GL_ASSERT( glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer) );
    
    // Associate render buffer storage with CAEAGLLauyer so that the rendered content is display on our UI layer.
    [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
    
    // Attach the color buffer to our frame buffer
    GL_ASSERT( glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer) );
    
    // Retrieve framebuffer size
    GL_ASSERT( glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &framebufferWidth) );
    GL_ASSERT( glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &framebufferHeight) );
    
    NSLog(@"width: %d, height: %d", framebufferWidth, framebufferHeight);
    
//    // If multisampling is enabled in config, create and setup a multisample buffer
    int samples = mSamplesCount;
    if (samples < 0)
        samples = 0;
    if (samples)
    {
        // Create multisample framebuffer
        GL_ASSERT( glGenFramebuffers(1, &multisampleFramebuffer) );
        GL_ASSERT( glBindFramebuffer(GL_FRAMEBUFFER, multisampleFramebuffer) );

        // Create multisample render and depth buffers
        GL_ASSERT( glGenRenderbuffers(1, &multisampleRenderbuffer) );
        GL_ASSERT( glGenRenderbuffers(1, &multisampleDepthbuffer) );

        // Try to find a supported multisample configuration starting with the defined sample count
        while (samples)
        {
            GL_ASSERT( glBindRenderbuffer(GL_RENDERBUFFER, multisampleRenderbuffer) );
            GL_ASSERT( glRenderbufferStorageMultisampleAPPLE(GL_RENDERBUFFER, samples, GL_RGBA8_OES, framebufferWidth, framebufferHeight) );
            GL_ASSERT( glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, multisampleRenderbuffer) );

            GL_ASSERT( glBindRenderbuffer(GL_RENDERBUFFER, multisampleDepthbuffer) );
            GL_ASSERT( glRenderbufferStorageMultisampleAPPLE(GL_RENDERBUFFER, samples, GL_DEPTH_COMPONENT24_OES, framebufferWidth, framebufferHeight) );
            GL_ASSERT( glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, multisampleDepthbuffer) );

            if (glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE)
                break; // success!

            NSLog(@"Creation of multisample buffer with samples=%d failed. Attempting to use configuration with samples=%d instead: %x", samples, samples / 2, glCheckFramebufferStatus(GL_FRAMEBUFFER));
            samples /= 2;
        }

        //todo: __multiSampling = samples > 0;

        // Re-bind the default framebuffer
        GL_ASSERT( glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer) );

        if (samples == 0)
        {
            // Unable to find a valid/supported multisample configuratoin - fallback to no multisampling
            GL_ASSERT( glDeleteRenderbuffers(1, &multisampleRenderbuffer) );
            GL_ASSERT( glDeleteRenderbuffers(1, &multisampleDepthbuffer) );
            GL_ASSERT( glDeleteFramebuffers(1, &multisampleFramebuffer) );
            multisampleFramebuffer = multisampleRenderbuffer = multisampleDepthbuffer = 0;
        }
    }
    
    // Create default depth buffer and attach to the frame buffer.
    // Note: If we are using multisample buffers, we can skip depth buffer creation here since we only
    // need the color buffer to resolve to.
    if (multisampleFramebuffer == 0)
    {
        GL_ASSERT( glGenRenderbuffers(1, &depthRenderbuffer) );
        GL_ASSERT( glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer) );
        GL_ASSERT( glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24_OES, framebufferWidth, framebufferHeight) );
        GL_ASSERT( glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer) );
    }
    
    // Sanity check, ensure that the framebuffer is valid
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        NSLog(@"ERROR: Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
        [self deleteFramebuffer];
        return NO;
    }
    
    // If multisampling is enabled, set the currently bound framebuffer to the multisample buffer
    // since that is the buffer code should be drawing into (and FrameBuffr::initialize will detect
    // and set this bound buffer as the default one during initialization.
    if (multisampleFramebuffer)
        GL_ASSERT( glBindFramebuffer(GL_FRAMEBUFFER, multisampleFramebuffer) );
    
    return YES;
}

- (void)deleteFramebuffer
{
    if (context)
    {
        [EAGLContext setCurrentContext:context];
        if (defaultFramebuffer)
        {
            GL_ASSERT( glDeleteFramebuffers(1, &defaultFramebuffer) );
            defaultFramebuffer = 0;
        }
        if (colorRenderbuffer)
        {
            GL_ASSERT( glDeleteRenderbuffers(1, &colorRenderbuffer) );
            colorRenderbuffer = 0;
        }
        if (depthRenderbuffer)
        {
            GL_ASSERT( glDeleteRenderbuffers(1, &depthRenderbuffer) );
            depthRenderbuffer = 0;
        }
        if (multisampleFramebuffer)
        {
            GL_ASSERT( glDeleteFramebuffers(1, &multisampleFramebuffer) );
            multisampleFramebuffer = 0;
        }
        if (multisampleRenderbuffer)
        {
            GL_ASSERT( glDeleteRenderbuffers(1, &multisampleRenderbuffer) );
            multisampleRenderbuffer = 0;
        }
        if (multisampleDepthbuffer)
        {
            GL_ASSERT( glDeleteRenderbuffers(1, &multisampleDepthbuffer) );
            multisampleDepthbuffer = 0;
        }
    }
}

- (void)prepareBindBuffers {
    // Bind our framebuffer for rendering.
    // If multisampling is enabled, bind the multisample buffer - otherwise bind the default buffer
    GL_ASSERT( glBindFramebuffer(GL_FRAMEBUFFER, multisampleFramebuffer ? multisampleFramebuffer : defaultFramebuffer) );
    GL_ASSERT( glViewport(0, 0, framebufferWidth, framebufferHeight) );
}

- (void)postBindBuffers {
    if (multisampleFramebuffer)
    {
        // Multisampling is enabled: resolve the multisample buffer into the default framebuffer
        GL_ASSERT( glBindFramebuffer(GL_DRAW_FRAMEBUFFER_APPLE, defaultFramebuffer) );
        GL_ASSERT( glBindFramebuffer(GL_READ_FRAMEBUFFER_APPLE, multisampleFramebuffer) );
        GL_ASSERT( glResolveMultisampleFramebufferAPPLE() );
        
        if (oglDiscardSupported)
        {
            // Performance hint that the GL driver can discard the contents of the multisample buffers
            // since they have now been resolved into the default framebuffer
            const GLenum discards[]  = { GL_COLOR_ATTACHMENT0, GL_DEPTH_ATTACHMENT };
            GL_ASSERT( glDiscardFramebufferEXT(GL_READ_FRAMEBUFFER_APPLE, 2, discards) );
        }
    }
    else
    {
        if (oglDiscardSupported)
        {
            // Performance hint to the GL driver that the depth buffer is no longer required.
            const GLenum discards[]  = { GL_DEPTH_ATTACHMENT };
            GL_ASSERT( glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer) );
            GL_ASSERT( glDiscardFramebufferEXT(GL_FRAMEBUFFER, 1, discards) );
        }
    }
    
    // Present the color buffer
    GL_ASSERT( glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer) );
}

#pragma public interface begin

- (void)setMultiSampelsCount:(int)samplesCount {
    mSamplesCount = samplesCount;
}

- (void)pause {
    [mGLThread onPause];
}

- (void)resume {
    [mGLThread onResume];
}

- (void)queueEvent:(nonnull NBEventRunnable)runnable {
    [mGLThread queueEvent:runnable];
}

- (void)setRenderMode:(int)renderMode {
    [mGLThread setRenderMode:renderMode];
}

- (int)getRenderMode {
    return [mGLThread getRenderMode];
}

- (void)requestRender {
    [mGLThread requestRender];
}

- (void)requestRenderAndNotify:(NBEventRunnable)finishDrawing {
    [mGLThread requestRenderAndNotify:finishDrawing];
}

#pragma public interface end

- (void)setRenderer:(id<NBGLRenderer>)renderer {
    _renderer = renderer;

    mGLThread = [[NBGLThread alloc] initWithNBGLView:self];
    [mGLThread start];
}

@end

#pragma NBGLThread begin

@implementation NBGLThread

- (instancetype)initWithNBGLView:(NBGLView*)glView {
    if (self = [super init]) {
        mExited = NO;
        
        mShouldExit = NO;
        mPaused = NO;
        mSizeChanged = NO;
        mRequestPaused = NO;
        
        mHaveEaglContext = NO;
        mWaitingForSurface = NO;
        mHaveEglContext = NO;
        mHaveEglSurface = NO;
        mWantRenderNotification = NO;
        mShouldReleaseEglContext = NO;
        
        mSurfaceIsBad = NO;
        
        mRenderMode = RENDERMODE_CONTINUOUSLY;
        
        mWidth = 0;
        mHeight = 0;
        
        mWeakGLView = glView;
        
        mFinishDrawingRunnable = nil;
        
        // alloc event array
        eventQueue = [NSMutableArray new];
    }
    return self;
}

- (void)onWindowResize:(int)w height:(int)h {
    [sGLThreadManager lock];
    mWidth = w;
    mHeight = h;
    mSizeChanged = true;
    mRequestRender = true;
    mRenderComplete = false;
    
    // If we are already on the GL thread, this means a client callback
    // has caused reentrancy, for example via updating the SurfaceView parameters.
    // We need to process the size change eventually though and update our EGLSurface.
    // So we set the parameters and return so they can be processed on our
    // next iteration.
//        if (Thread.currentThread() == this) {
//            return;
//        }
    
    [sGLThreadManager broadcast];
    
    // Wait for thread to react to resize and render a frame
    while (! mExited && !mPaused && !mRenderComplete
           && [self ableToDraw]) {
        [sGLThreadManager wait];
    }
    [sGLThreadManager unlock];
}

- (void)surfaceCreated {
    [sGLThreadManager lock];
    mHasSurface = true;
    mFinishedCreatingEglSurface = false;
    [sGLThreadManager broadcast];
    while (mWaitingForSurface
           && !mFinishedCreatingEglSurface
           && !mExited) {
        [sGLThreadManager wait];
    }
    [sGLThreadManager unlock];
}

- (void)surfaceDestroy {
    [sGLThreadManager lock];
    mHasSurface = false;
    [sGLThreadManager broadcast];
    while((!mWaitingForSurface) && (!mExited)) {
        [sGLThreadManager wait];
    }
    [sGLThreadManager unlock];
}

- (void)onPause {
    [sGLThreadManager lock];
    mRequestPaused = YES;
    
    [sGLThreadManager broadcast];
    while ((! mExited) && (! mPaused)) {
        [sGLThreadManager wait];
    }
    [sGLThreadManager unlock];
}

- (void)onResume {
    [sGLThreadManager lock];
    mRequestPaused = NO;
    mRequestRender = YES;
    mRenderComplete = NO;
    [sGLThreadManager broadcast];
    while ((! mExited) && mPaused && (!mRenderComplete)) {
        [sGLThreadManager wait];
    }
    [sGLThreadManager unlock];
}

- (void)requestExitAndWait {
    // don't call this from GLThread thread or it is a guaranteed
    // deadlock!
    [sGLThreadManager lock];
    mShouldExit = YES;
    [sGLThreadManager broadcast];
    while (! mExited) {
        [sGLThreadManager wait];
    }
    [sGLThreadManager unlock];
}

- (void)requestRender {
    [sGLThreadManager lock];
    mRequestRender = YES;
    [sGLThreadManager broadcast];
    [sGLThreadManager unlock];
}

- (void)requestRenderAndNotify:(NBEventRunnable)finishDrawing {
    [sGLThreadManager lock];
    // If we are already on the GL thread, this means a client callback
    // has caused reentrancy, for example via updating the SurfaceView parameters.
    // We will return to the client rendering code, so here we don't need to
    // do anything.
//        if (Thread.currentThread() == this) {
//            return;
//        }
    
    mWantRenderNotification = true;
    mRequestRender = true;
    mRenderComplete = false;
    mFinishDrawingRunnable = finishDrawing;
    
    [sGLThreadManager broadcast];
    
    [sGLThreadManager unlock];
}

- (int)getRenderMode {
    int rc = 0;
    [sGLThreadManager lock];
    rc = mRenderMode;
    [sGLThreadManager unlock];
    return rc;
}

- (void)setRenderMode:(int)renderMode {
    [sGLThreadManager lock];
    mRenderMode = renderMode;
    [sGLThreadManager broadcast];
    [sGLThreadManager unlock];
}

- (BOOL)ableToDraw {
    return mHaveEaglContext && [self readyToDraw];
}

- (BOOL)readyToDraw {
    return (!mPaused) && mHasSurface && (!mSurfaceIsBad)
    && (mWidth > 0) && (mHeight > 0)
    && (mRequestRender || (mRenderMode == RENDERMODE_CONTINUOUSLY));
}

- (void)createGLContext {
    backgroundContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2 sharegroup:[mWeakGLView.context sharegroup]];
    [EAGLContext setCurrentContext:backgroundContext];
}

- (void)prepareBuffers {
    if (backgroundContext) {
        [mWeakGLView prepareBindBuffers];
    }
}

- (void)swapBuffers
{
    if (backgroundContext)
    {
        [mWeakGLView postBindBuffers];
        [backgroundContext presentRenderbuffer:GL_RENDERBUFFER];
    }
}

- (void)queueEvent:(nonnull NBEventRunnable)runnable {
    [sGLThreadManager lock];
    [eventQueue addObject:runnable];
    [sGLThreadManager broadcast];
    [sGLThreadManager unlock];
}

- (void)main {
    [self setName:@"glThreadRun"];
    
    // perform the actually render
    [self guardedRun];
}

- (void)guardedRun {
    mHaveEglContext = NO;
    mHaveEglSurface = NO;
    mWantRenderNotification = NO;
    
    BOOL createEglContext = NO;
    BOOL createEglSurface = NO;
    BOOL createGlInterface = NO;
    BOOL lostEglContext = NO;
    BOOL sizeChanged = NO;
    BOOL wantRenderNotification = NO;
    BOOL doRenderNotification = NO;
    BOOL askedToReleaseEglContext = NO;
    int w = 0;
    int h = 0;
    
    NBEventRunnable event = nil;
    NBEventRunnable finishDrawingRunnable = nil;
    
    while (true) {
        [sGLThreadManager lock];
        while (true) {
            if (mShouldExit) {
                // request exit all loop
                break;
            }
            
            if ([eventQueue count] > 0) {
                event = [eventQueue objectAtIndex:0];
                [eventQueue removeObjectAtIndex:0];
                break;
            }
            
            // Update the pause state.
            BOOL pausing = false;
            if (mPaused != mRequestPaused) {
                pausing = mRequestPaused;
                mPaused = mRequestPaused;
                [sGLThreadManager broadcast];
            }
            
            // Do we need to give up the EGL context?
            if (mShouldReleaseEglContext) {
//                stopEglSurfaceLocked();
//                stopEglContextLocked();
                mShouldReleaseEglContext = NO;
                askedToReleaseEglContext = YES;
            }
            
            // Have we lost the EGL context?
            if (lostEglContext) {
//                stopEglSurfaceLocked();
//                stopEglContextLocked();
                lostEglContext = NO;
            }
            
            // When pausing, release the EGL surface:
            if (pausing && mHaveEglSurface) {
//                if (LOG_SURFACE) {
//                    Log.i("GLThread", "releasing EGL surface because paused tid=" + getId());
//                }
//                stopEglSurfaceLocked();
            }
            
            // When pausing, optionally release the EGL Context:
            if (pausing && mHaveEglContext) {
//                GLSurfaceView view = mGLSurfaceViewWeakRef.get();
//                boolean preserveEglContextOnPause = view == null ?
//                false : view.mPreserveEGLContextOnPause;
//                if (!preserveEglContextOnPause) {
//                    stopEglContextLocked();
//                    if (LOG_SURFACE) {
//                        Log.i("GLThread", "releasing EGL context because paused tid=" + getId());
//                    }
//                }
            }
            
            // Have we lost the SurfaceView surface?
            if ((! mHasSurface) && (! mWaitingForSurface)) {
//                if (LOG_SURFACE) {
//                    Log.i("GLThread", "noticed surfaceView surface lost tid=" + getId());
//                }
//                if (mHaveEglSurface) {
//                    stopEglSurfaceLocked();
//                }
//                mWaitingForSurface = true;
//                mSurfaceIsBad = false;
//                sGLThreadManager.notifyAll();
            }
            
            // Have we acquired the surface view surface?
            if (mHasSurface && mWaitingForSurface) {
//                if (LOG_SURFACE) {
//                    Log.i("GLThread", "noticed surfaceView surface acquired tid=" + getId());
//                }
                mWaitingForSurface = NO;
                [sGLThreadManager broadcast];
            }
            
            if (doRenderNotification) {
//                if (LOG_SURFACE) {
//                    Log.i("GLThread", "sending render notification tid=" + getId());
//                }
                mWantRenderNotification = NO;
                doRenderNotification = NO;
                mRenderComplete = YES;
                [sGLThreadManager broadcast];
            }
            
            if (mFinishDrawingRunnable != nil) {
                finishDrawingRunnable = mFinishDrawingRunnable;
                mFinishDrawingRunnable = nil;
            }
            
            // Ready to draw?
            if ([self readyToDraw]) {
                // If we don't have an EGL context, try to acquire one.
                if (! mHaveEglContext) {
                    if (askedToReleaseEglContext) {
                        askedToReleaseEglContext = NO;
                    } else {
//                        try {
//                            mEglHelper.start();
//                        } catch (RuntimeException t) {
//                            sGLThreadManager.releaseEglContextLocked(this);
//                            throw t;
//                        }
                        mHaveEglContext = YES;
                        createEglContext = YES;
                        
                        [sGLThreadManager broadcast];
                    }
                }
                
                if (mHaveEglContext && !mHaveEglSurface) {
                    mHaveEglSurface = YES;
                    createEglSurface = YES;
                    createGlInterface = YES;
                    sizeChanged = YES;
                }
                
                if (mHaveEglSurface) {
                    if (mSizeChanged) {
                        sizeChanged = YES;
                        w = mWidth;
                        h = mHeight;
                        mWantRenderNotification = YES;
                        
//                        if (LOG_SURFACE) {
//                            Log.i("GLThread",
//                                  "noticing that we want render notification tid="
//                                  + getId());
//                        }
                        
                        // Destroy and recreate the EGL surface.
                        createEglSurface = YES;
                        
                        mSizeChanged = NO;
                    }
                    mRequestRender = NO;
                    [sGLThreadManager broadcast];
                    if (mWantRenderNotification) {
                        wantRenderNotification = YES;
                    }
                    break;
                }
                
                if (wantRenderNotification) {
                    doRenderNotification = true;
                    wantRenderNotification = false;
                }
                
            } else {
                if (finishDrawingRunnable != nil) {
                    NSLog(@"Warning, !readyToDraw() but waiting for draw finished! Early reporting draw finished.");
                    finishDrawingRunnable();
                    finishDrawingRunnable = nil;
                }
            }
            
            // wait out side event
            [sGLThreadManager wait];
        }
        [sGLThreadManager unlock];
        
        // check it second time
        if (mShouldExit) {
            break;
        }
        
        // run the event
        if (event != nil) {
            event();
            event = nil;
            continue;
        }
        
        if (createEglSurface) {
//            if (mEglHelper.createSurface()) {
//                synchronized(sGLThreadManager) {
//                    mFinishedCreatingEglSurface = true;
//                    sGLThreadManager.notifyAll();
//                }
//            } else {
//                synchronized(sGLThreadManager) {
//                    mFinishedCreatingEglSurface = true;
//                    mSurfaceIsBad = true;
//                    sGLThreadManager.notifyAll();
//                }
//                continue;
//            }
            createEglSurface = false;
        }
        
        if (createGlInterface) {
            [self createGLContext];
            createGlInterface = false;
        }
        
        if (createEglContext) {
            if ([mWeakGLView.renderer respondsToSelector:@selector(glRenderCreated:)]) {
                [mWeakGLView.renderer glRenderCreated:mWeakGLView];
            }
            createEglContext = false;
        }
        
        if (sizeChanged) {
//            if (LOG_RENDERER) {
//                Log.w("GLThread", "onSurfaceChanged(" + w + ", " + h + ")");
//            }
            if ([mWeakGLView.renderer respondsToSelector:@selector(glRenderSizeChanged:width:height:)]) {
                [mWeakGLView.renderer glRenderSizeChanged:mWeakGLView width:w height:h];
            }
            sizeChanged = false;
        }
        
        // do prepare draw buffer
        [self prepareBuffers];
        
        // do real draw callback
        {
            if ([mWeakGLView.renderer respondsToSelector:@selector(glRenderDrawFrame:)]) {
                [mWeakGLView.renderer glRenderDrawFrame:mWeakGLView];
            }
        }
        
        // swap the glcontext
        [self swapBuffers];
    }
    
    // do call back this context is invalid
    if ([EAGLContext currentContext] == backgroundContext) {
        [EAGLContext setCurrentContext:nil];
    }
    
    if ([mWeakGLView.renderer respondsToSelector:@selector(glRenderDestroy:)]) {
        [mWeakGLView.renderer glRenderDestroy:mWeakGLView];
    }
}

@end

#pragma NBGLThread end
