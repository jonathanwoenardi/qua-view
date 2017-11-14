{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE GADTs #-}

{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE Rank2Types #-}
-- | Keep all global events to be registered in qua-view
module Commons.Events
    ( -- * Global event map
      QuaViewEvents (..), noEvents
      -- * Tagging events
    , QEventType (..), QEventTag
      -- * Event types
    , UserRequest (..), ScId
    , WorkerMessage
    , SmallGLInput
      -- * TH helpers
    , deriveEvent
    ) where


import Data.Dependent.Map (unionWithKey, empty)
import Data.GADT.Compare
import Data.GADT.Compare.TH
import Language.Haskell.TH.Syntax ( Type (ConT), Name, Q, Dec, reifyInstances )
import Reflex.Class (leftmost)

import Commons.Import
import Commons.Local

-- | A map of qua-view events with suitable monoid instances.
--   When two maps merge and have same event name (key), the events are merged using
--   `lefmost`.
--   Since there is not symantic way to represent which event occurrence is preferred when
--   an event you declare coincide with another one, you must be very careful to avoid such situations.
newtype QuaViewEvents t = QuaViewEvents
  { unQuaViewEvents :: DMap QEventType (Event t)}

noEvents :: QuaViewEvents t
noEvents = QuaViewEvents empty

instance Reflex t => Semigroup (QuaViewEvents t) where
  a <> b = QuaViewEvents
         $ unionWithKey (\_ x y -> leftmost [x,y])
                        (unQuaViewEvents a)
                        (unQuaViewEvents b)

instance Reflex t => Monoid (QuaViewEvents t) where
  mempty = noEvents
  mappend = (<>)


-- | All possible global events in qua-view
--    (those, which are passed between components only).
data QEventType evArg where
    UserRequest    :: UserRequest evArg -> QEventType evArg
    -- ^ Some type of user action - interaction with UI
    GeometryLoaded :: QEventType LoadedTextContent
    -- ^ When we got geometetry from file
    WorkerMessage  :: (GEq (QEventTag WorkerMessage), GCompare (QEventTag WorkerMessage))
                   => QEventTag WorkerMessage evArg -> QEventType evArg
    -- ^ Various messages coming from web-workers.
    SmallGLInput   :: (GEq (QEventTag SmallGLInput), GCompare (QEventTag SmallGLInput))
                   => QEventTag SmallGLInput evArg -> QEventType evArg
    -- ^ Changes caused by SmallGL inputs


-- | By using this data family we can postpone instantiation of event tags to other module,
--   and thus avoid mutual module dependencies and still have events defined not in a single file.
--   Here we only define abstract uninhabited tag types and use them to index this data family.
data family QEventTag tag :: (* -> *)



----------------------------------------------------------------------------------------------------
-- * Event subtypes
--   Some event subtypes are defined right here, some of them are defined in other places.
--   In latter case, we provide type stubs;
----------------------------------------------------------------------------------------------------

-- | Tag events coming from workers.
--   An actual event content type is defined via @QEventTag WorkerMessage@ later.
data WorkerMessage

-- | Tag events of SmallGL inputs
data SmallGLInput

-- | TODO this datatype should be in luci module;
--   represents a scenario id
newtype ScId = ScId Int
  deriving (Eq, Show, Ord)

-- | Event types fired by user actions
data UserRequest evArg where
    AskSaveScenario   :: UserRequest Text
    -- ^ User wants to save scenario with this name
    AskSelectScenario :: UserRequest ScId
    -- ^ User selects a scenario in the scenario list.
    AskClearGeometry  :: UserRequest ()
    -- ^ User wants to clear all geometry
    AskResetCamera    :: UserRequest ()
    -- ^ User wants to reset camera to its default position
    AskSubmitProposal :: UserRequest Text
    -- ^ User wants to submit exercise. TODO: Need to add image and geometry?

----------------------------------------------------------------------------------------------------
-- * Template Haskell
----------------------------------------------------------------------------------------------------


deriveGEq ''UserRequest
deriveGCompare ''UserRequest
deriveGEq ''QEventType
deriveGCompare ''QEventType

-- | Use this function to derive instance of GEq and GCompare to your GADT.
--   Beware, this function plus GADT definition would require to enable several language extensions:
--
--     {-# LANGUAGE TemplateHaskell #-}
--     {-# LANGUAGE FlexibleInstances #-}
--     {-# LANGUAGE TypeFamilies #-}
--     {-# LANGUAGE GADTs #-}
--     {-# OPTIONS_GHC -fno-warn-orphans #-}
--
--   Argument of a function is a type name of the data family parameter.
--   Example:
--
--   >
--   > data instance QEventTag WorkerMsg evArg where
--   >   ...
--   >
--   > deriveEvent ''WorkerMsg
--   >
--
deriveEvent :: Name -> Q [Dec]
deriveEvent tagname = do
    x <- reifyInstances ''QEventTag [ConT tagname]
    eqdecs <- deriveGEq x
    cmpdecs <- deriveGCompare x
    return $ eqdecs ++ cmpdecs

