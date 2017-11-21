{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
module Main ( main ) where

import Reflex.Dom
import Reflex.Dom.Widget.Animation (resizeEvents, viewPortSizeI)
import qualified Reflex.Dom.Widget.Animation as Animation
import Numeric.DataFrame

import Commons


import qualified Model.Camera               as Model
import qualified Model.Scenario             as Scenario
import qualified Model.Scenario.Statistics  as Scenario
import qualified Model.Scenario.Object      as Object

import           Widgets.Generation
import qualified Widgets.LoadingSplash  as Widgets
import qualified Widgets.Canvas         as Widgets
import qualified Widgets.ControlPanel   as Widgets

import qualified SmallGL
import qualified Workers.LoadGeometry as Workers

import           Program.Scenario

import qualified QuaTypes
import Control.Concurrent (forkIO, threadDelay)

main :: IO ()
main = mainWidgetInElementById "qua-view-widgets" $ runQuaWidget $ mdo
    -- Change the state of the program
    (isProgramBusy, setIsProgramBusy) <- newTriggerEvent

    -- register loading splash so that we can change its visibility
    Widgets.loadingSplashD isProgramBusy

    -- register canvas element
    canvas <- Widgets.getWebGLCanvas

    -- add the control panel to the page
    _panelStateD <- Widgets.controlPanel

    -- get an event of loaded geometry text, combine it with current state of scenario,
    -- and make a new event to be consumed by the LoadGeometryWorker
    do
      geomLoadedE <- askEvent GeometryLoaded
      registerEvent (WorkerMessage Workers.LGWRequest)
        $ Workers.LGWLoadTextContent . Scenario.withoutObjects <$> scenarioB <@> geomLoadedE

    -- initialize web workers
    Workers.runLoadGeometryWorker
    loadedGeometryE <- askEvent $ WorkerMessage Workers.LGWMessage


    renderingApi <- SmallGL.createRenderingEngine canvas
    -- initialize animation handler (and all pointer events).
    aHandler <- Widgets.registerAnimationHandler canvas (SmallGL.render renderingApi)
    -- selected object id events
    selectorClicks <-
       performEvent $ (\((x,y):_) ->
           liftIO $ SmallGL.getHoveredSelId renderingApi (round x, round y) )
                 <$> Animation.downPointersB aHandler
                 <@ select (Animation.pointerEvents aHandler) PClickEvent
    selectedObjIdD <- holdDyn Nothing . ffor selectorClicks $
        \oid -> if oid == 0xFFFFFFFF then Nothing else Just (Object.ObjectId oid)

    logDebugEvents' @JSString "qua-view.hs" $ (,) "selectedObjId" . Just <$> updated selectedObjIdD

    -- supply animation events to camera
    let icamera = Model.initCamera (realToFrac . fst $ viewPortSizeI aHandler)
                                   (realToFrac . snd $ viewPortSizeI aHandler)
                                   Model.CState { Model.viewPoint  = vec3 (-2) 3 0
                                                , Model.viewAngles = (2.745, 0.995)
                                                , Model.viewDist = 468 }
    plsResetCameraE <- askEvent (UserRequest AskResetCamera)
    cameraD <- Model.dynamicCamera icamera aHandler plsResetCameraE $ current scenarioCenterD
--    performEvent_ $ liftIO . print <$> updated cameraD
    -- initialize WebGL rendering context
    registerEvent (SmallGLInput SmallGL.ViewPortResize)
        $ resizeEvents aHandler
    registerEvent (SmallGLInput SmallGL.ProjTransformChange)
        $ SmallGL.ProjM . Model.projMatrix <$> updated cameraD
    registerEvent (SmallGLInput SmallGL.ViewTransformChange)
        $ SmallGL.ViewM . Model.viewMatrix <$> updated cameraD

    scenarioB <- inQuaWidget $ createScenario renderingApi

    let scenarioCenterE = fmapMaybe
                          (\m -> case m of
                             Workers.LGWSCStat st -> Just $ Scenario.centerPoint st
                             _ -> Nothing
                          ) loadedGeometryE
    scenarioCenterD <- holdDyn (vec2 0 0) scenarioCenterE


    -- Notify everyone that the program h finished starting up now
    mainBuilt <- getPostBuild
    performEvent_ . flip fmap mainBuilt . const $ do
        liftIO (setIsProgramBusy Idle)
        Widgets.play aHandler

    -- other init things
    -- load geometry from url if it is supplied
    quaSettings >>= sample . fmap QuaTypes.getSubmissionGeometryUrl . current
                >>= \ms -> case ms of
      Nothing -> return ()
      Just url -> do
        (ev, trigger) <- newTriggerEvent
        registerEvent (WorkerMessage Workers.LGWRequest)
          $ Workers.LGWLoadUrl . Scenario.withoutObjects <$> scenarioB <@> ev
        liftIO . void . forkIO $ threadDelay 2000000 >> trigger url



-- | Create a global css splice.
--   Do not abuse this!
$(do
  qcss
    [cassius|
      body
        position: fixed
        left: 0
        top: 0
        padding: 0
        margin: 0
        width: 100%
        height: 100%
        overflow: hidden
        background-color: #FFFFFF
        touch-action: none
        color: #BF360C

      #qua-view-widgets
        position: fixed
        left: 0
        top: 0
        padding: 0
        margin: 0
        z-index: 1
        overflow: visible
        width: 0
        height: 0
    |]
  return []
 )
