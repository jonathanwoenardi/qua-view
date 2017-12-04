{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE RecursiveDo #-}

module Widgets.Tabs.Geometry
    ( panelGeometry
    ) where

import Reflex.Dom
import Control.Lens ((%~), (^.))
import Control.Monad.Trans.Class (lift)
import qualified GHCJS.DOM.JSFFI.Generated.HTMLInputElement as JSFFI (setValue)
import qualified GHCJS.DOM.JSFFI.Generated.File as JSFFI
import qualified GHCJS.DOM.JSFFI.Generated.FileReader as JSFFI
import qualified GHCJS.DOM.EventM as JSFFI

import Commons
import Program.UserAction
import Widgets.Commons
import Widgets.Generation
import Widgets.Modal.BrowseScenarios
import Widgets.Modal.SaveScenario




panelGeometry :: Reflex t => QuaWidget t x ()
panelGeometry = do

    el "div" $ text "Read GeoJSON from file"
    (clearGeometryClickedE, geometryLoadedE) <-
      el "div" $ do
        -- clear geometry button
        cgClicked <- buttonRed @"ClearGeometry" "Clear" def
        -- File upload button and its dynamic label
        rezE <- fileUpload cgClicked

        return ( () <$ cgClicked, rezE)

    (asksSaveScenarioE, asksSelectScenarioE) <- lift luciScenarioPane

    -- register all outgoing events
    registerEvent (UserAction AskClearGeometry) clearGeometryClickedE
    registerEvent (UserAction AskSaveScenario) asksSaveScenarioE
    registerEvent (UserAction AskSelectScenario) asksSelectScenarioE
    registerEvent GeometryLoaded geometryLoadedE










-- | Widget gets an event of clearing geometry to erase current file name label.
--   Returns two events: file loading errors and content events.
fileUpload :: Reflex t
           => Event t (ElementClick "ClearGeometry")
           -> QuaWidget t x (Event t LoadedTextContent)
fileUpload clearGeomEv = mdo
    _ <- elAttr "label" ("for" =: finputId) $ buttonRed "Files" def
    elAttr "div" ("style" =: "display:inline; font-size: 0.9em;"
               <> "class" =: smallMarginClass)
                 $ dynText fileNameD
    fInput <- fileInput $ def & fileInputConfig_attributes
                              %~ (fmap . mappend $ "style" =: hideWorkaroundStile
                                                <> "id" =: finputId)
    let fileD = headMaybe <$> (fInput ^. fileInput_value)
    fileNameE <- performEvent $ maybe (pure "") JSFFI.getName <$> updated fileD
    fileNameD <- holdDyn "" $ leftmost [fileNameE, "" <$ clearGeomEv]
    -- create JavaSript file reader
    freader <- JSFFI.newFileReader
    -- create a reflex event trigger to put file load events there
    (onLoadEndE, loadEndCallback) <- newTriggerEvent
    (onErrorE  , errorCallback)   <- newTriggerEvent
    -- register reflex callback on file reader loading event
    void . liftIO $ JSFFI.on freader JSFFI.loadEnd $ ReaderT loadEndCallback
    void . liftIO $ JSFFI.on freader JSFFI.error $ ReaderT errorCallback
    void . liftIO $ JSFFI.on freader JSFFI.abortEvent $ ReaderT errorCallback
    performEvent_ $ flip (JSFFI.readAsText freader) (Nothing :: Maybe JSString) <$> updated fileD
    -- get events of completion or errors
    (errE, rezE) <-
       fmap (fanEither . fmap maybeNotRead) . performEvent $
               -- erase content of file input after we got the file
               (JSFFI.setValue (_fileInput_element fInput) ("" :: JSString)
                -- get file content
            >> JSFFI.getResult freader)
            <$ onLoadEndE
    logErrorEvents "fileUpload" $ leftmost
                             [ getJSError <$> errE
                             , "Error happened when executing FileReader.readAsText." <$ onErrorE
                             ]
    return rezE
  where
    finputId = $(newVar >>= returnVars . (:[]))
    headMaybe (x:_) = Just x
    headMaybe [] = Nothing
    hideWorkaroundStile = "position:fixed;top:-10000px;left:-10000px;"
     -- "visibility:hidden;width:0;height:0;padding:0;margin:0;border:0;min-height:0;"
    maybeNotRead Nothing = Left "Could not read file (FileReader.readAsText returned Nothing)."
    maybeNotRead (Just r) = case castToJSString r of
        Nothing -> Left "Scenario file must be a text file, but got binary file."
        Just s  -> Right $ LoadedTextContent s



-- | User indicates that they want to save scanerio with a specified name (via pop-up)
buttonSaveScenario :: Reflex t => Widget x (Event t Text)
buttonSaveScenario = buttonRed "Save" def >>= popupSaveScenario

-- | User selects
buttonBrowseScenarios :: Reflex t => Widget x (Event t ScId)
buttonBrowseScenarios = buttonRed "Scenarios" def >>= popupBrowseScenarios


luciScenarioPane :: Reflex t
                 => Widget x ( Event t Text
                             , Event t ScId )
luciScenarioPane = do
  el "div" $ text "Remote (Luci scenarios)"
  el "div" $ do
    userSelectedScenarioE    <- buttonBrowseScenarios
    userWantsToSaveScenarioE <- buttonSaveScenario
    performEvent_ $ (liftIO . print) <$> userWantsToSaveScenarioE
    -- TODO: fileNameIndicator $ constDyn "placeholder" -- current scenario name
    return (userWantsToSaveScenarioE, userSelectedScenarioE)



