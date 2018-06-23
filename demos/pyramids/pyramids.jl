#! /usr/bin/env julia
const profile = false

using DataStructures
import GLFW
using ModernGL
using Quaternions
if profile using ProfileView end

#WARNING: Order of includes matters.
const libDir = joinpath("..", "lib")
include(joinpath(libDir, "Renderer.jl"))
include(joinpath(libDir, "Game.jl"))
import Renderer
import Game

# Quantum of simulation fixed time step in seconds.
const chronon = 0.01

const targetFps = 60
const targetSecsPerFrame = 1 / targetFps
const vsync = true

oldCursorPos = [0, 0]
cameraRot = [0, 0]
camera = nothing

timeOfLastSimUpdate = Dates.now()

pastSecsPerUpdate = CircularBuffer{Real}(120)

updateCounter = 0

# Exit app control.
exitApp = false

global nextUpdateQuantaMultiple = 0

include("pawns.jl")

function handleKey(key, scancode, action)
    name = GLFW.GetKeyName(key, scancode)
    # if name == nothing
    #     println("scancode $scancode ", action)
    # else
    #     println("key $name ", action)
    # end
    # if key != nothing

    const speed = 0.1

    if key == GLFW.KEY_SPACE
        global exitApp = true
    elseif key in [GLFW.KEY_W, GLFW.KEY_UP]
        translate(camera, -speed * GLfloat[0, 0, 1])
    elseif key in [GLFW.KEY_S, GLFW.KEY_DOWN]
        translate(camera, speed * GLfloat[0, 0, 1])
    elseif key in [GLFW.KEY_A, GLFW.KEY_LEFT]
        translate(camera, speed * GLfloat[1, 0, 0])
    elseif key in [GLFW.KEY_D, GLFW.KEY_RIGHT]
        translate(camera, -speed * GLfloat[1, 0, 0])
    end
end

# Camera coordinates are its pitch, roll, and yaw vectors.
function translate(camera::Renderer.Camera, translationInCamCoords)
    rotation = rotationmatrix(camera.orientation)
    translationInWorldCoords = rotation * translationInCamCoords
    camera.position += translationInWorldCoords
    Renderer.updateGpuBuffers(camera)
end

function handleCursorPos(cursorPos)
    xdel, ydel = cursorPos - oldCursorPos
    global oldCursorPos = cursorPos

    global cameraRot += 0.005 * [xdel, ydel]

    yaw = qrotation([0, 1, 0], cameraRot[1])
    pitchVec = rotationmatrix(yaw) * [1, 0, 0]
    pitch = qrotation(pitchVec, cameraRot[2])
    camera.orientation = pitch * yaw

    # frameYaw = qrotation([0, 1, 0], 0.01 * xdel)
    # framePitch = qrotation([1, 0, 0], 0.01 * ydel)
    # camera.orientation = framePitch * camera.orientation * frameYaw

    Renderer.updateGpuBuffers(camera)
end

function modernGLDemo()
    window = Renderer.createWindow("ModernGL Example")
    Renderer.init()

    GLFW.SetInputMode(window, GLFW.CURSOR, GLFW.CURSOR_DISABLED)

    GLFW.SetKeyCallback(
        window,
        (_, key, scancode, action, mods) -> handleKey(key, scancode, action)
    )

    cursorPos = GLFW.GetCursorPos(window)
    global oldCursorPos = [cursorPos[1], cursorPos[2]]
    GLFW.SetCursorPosCallback(
        window,
        (_, xpos, ypos) -> handleCursorPos([xpos, ypos])
    )

    const shadersDir = joinpath("..", "shaders")
    shader = Renderer.Shader(
        joinpath(shadersDir, "vert.glsl"),
        joinpath(shadersDir, "frag.glsl")
    )

    global camera = Renderer.Camera(GLFW.GetWindowSize(window))
    Renderer.bind(camera, shader)

    pyramid = Pyramid(shader)
    actors = [pyramid]

    scene = [actor.pawn.item for actor in actors]

    # Loop until user closes the window.
    secsSinceLastFrame = 0
    timeOfLastFrame = Dates.now()
    while !exitApp
        secsSinceLastFrame = (Dates.now() - timeOfLastFrame).value / 1000
        if !vsync || secsSinceLastFrame >= targetSecsPerFrame
            tic()

            Renderer.render(scene, window)

            secsPerFrame = toq()

            timeOfLastFrame = Dates.now()

            Renderer.printFps(secsSinceLastFrame)
        end

        tic()
        simulate(actors)
        secsSpentSimulating = toq()

        GLFW.PollEvents()
    end

    GLFW.Terminate()

    resetDemo()
    return
end

# Reset demo, allowing it to be run again in the same session.
function resetDemo()
    global exitApp = false
end

function simulate(actors)
    secsSinceUpdate = (Dates.now() - timeOfLastSimUpdate).value / 1000
    while secsSinceUpdate >= chronon
        # push!(pastSecsPerUpdate, )
        global updateCounter += 1
        if updateCounter == 5 / chronon
            println("Secs per update: ", secsSinceUpdate)
            global updateCounter = 0
        end

        # Threads.@threads for actor in actors
        for actor in actors
            #TODO: generic update
            simulate(actor, chronon)
        end

        # Update OpenGL in thread that created context.
        for actor in actors
            Game.updateGpuBuffers(actor.pawn)
        end

        secsSinceUpdate -= chronon

        global timeOfLastSimUpdate = Dates.now()
    end
end

if profile
    Profile.init(delay=0.01)
    Profile.clear()
    @profile modernGLDemo()
    ProfileView.view()
    sleep(20)
else
    modernGLDemo()
end
