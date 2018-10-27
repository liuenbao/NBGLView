//
//  NBGLView.h
//  NBGLViewDemo
//
//  Created by liu enbao on 25/10/2018.
//  Copyright © 2018 liu enbao. All rights reserved.
//

#import <UIKit/UIKit.h>

/**
 * The renderer only renders
 * when the surface is created, or when {@link #requestRender} is called.
 *
 * @see #getRenderMode()
 * @see #setRenderMode(int)
 * @see #requestRender()
 */
static int RENDERMODE_WHEN_DIRTY = 0;

/**
 * The renderer is called
 * continuously to re-render the scene.
 *
 * @see #getRenderMode()
 * @see #setRenderMode(int)
 */
static int RENDERMODE_CONTINUOUSLY = 1;

@class NBGLView;

@protocol NBGLRenderer<NSObject>

- (void)glRenderCreated:(NBGLView*)view;

- (void)glRenderSizeChanged:(NBGLView*)view width:(NSInteger)width height:(NSInteger)height;

- (void)glRenderDrawFrame:(NBGLView*)view;

- (void)glRenderDestroy:(NBGLView*)view;

@end

typedef void (^NBEventRunnable)(void);

@interface NBGLView : UIView

@property (readonly, nonatomic, getter=getContext) EAGLContext* context;

- (void)setRenderer:(id<NBGLRenderer>)renderer;

/**
 * For multisample support on Apple platform
 */
- (void)setMultiSampelsCount:(int)sampleCount;

/**
 * Pause the rendering thread, optionally tearing down the EGL context
 * depending upon the value of {@link #setPreserveEGLContextOnPause(boolean)}.
 *
 * This method should be called when it is no longer desirable for the
 * GLSurfaceView to continue rendering, such as in response to
 * {@link android.app.Activity#onStop Activity.onStop}.
 *
 * Must not be called before a renderer has been set.
 */
- (void)pause;

/**
 * Resumes the rendering thread, re-creating the OpenGL context if necessary. It
 * is the counterpart to {@link #onPause()}.
 *
 * This method should typically be called in
 * {@link android.app.Activity#onStart Activity.onStart}.
 *
 * Must not be called before a renderer has been set.
 */
- (void)resume;

/**
 * Queue a runnable to be run on the GL rendering thread. This can be used
 * to communicate with the Renderer on the rendering thread.
 * Must not be called before a renderer has been set.
 * @param r the runnable to be run on the GL rendering thread.
 */
- (void)queueEvent:(nonnull NBEventRunnable)runnable;

/**
 * Set the rendering mode. When renderMode is
 * RENDERMODE_CONTINUOUSLY, the renderer is called
 * repeatedly to re-render the scene. When renderMode
 * is RENDERMODE_WHEN_DIRTY, the renderer only rendered when the surface
 * is created, or when {@link #requestRender} is called. Defaults to RENDERMODE_CONTINUOUSLY.
 * <p>
 * Using RENDERMODE_WHEN_DIRTY can improve battery life and overall system performance
 * by allowing the GPU and CPU to idle when the view does not need to be updated.
 * <p>
 * This method can only be called after {@link #setRenderer(Renderer)}
 *
 * @param renderMode one of the RENDERMODE_X constants
 * @see #RENDERMODE_CONTINUOUSLY
 * @see #RENDERMODE_WHEN_DIRTY
 */
- (void)setRenderMode:(int)renderMode;

/**
 * Get the current rendering mode. May be called
 * from any thread. Must not be called before a renderer has been set.
 * @return the current rendering mode.
 * @see #RENDERMODE_CONTINUOUSLY
 * @see #RENDERMODE_WHEN_DIRTY
 */
- (int)getRenderMode;

/**
 * Request that the renderer render a frame.
 * This method is typically used when the render mode has been set to
 * {@link #RENDERMODE_WHEN_DIRTY}, so that frames are only rendered on demand.
 * May be called
 * from any thread. Must not be called before a renderer has been set.
 */
- (void)requestRender;

@end
