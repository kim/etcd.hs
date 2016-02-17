-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs         #-}

module Data.Etcd.Misc
    ( MiscAPI
    , MiscF   (..)
    , Version (..)
    , Health  (..)

    , getVersion
    , getHealth
    )
where

import Control.Monad.Operational
import Data.Aeson                (FromJSON (..))
import Data.Text                 (Text)
import GHC.Generics


type MiscAPI = ProgramT MiscF

data MiscF a where
    GetVersion :: MiscF Version
    GetHealth  :: MiscF Health

data Version = Version
    { etcdcluster :: !Text
    , etcdversion :: !Text
    } deriving (Show, Generic)

instance FromJSON Version

newtype Health = Health { health :: Bool }
    deriving (Show, Generic)

instance FromJSON Health


getVersion :: Monad m => MiscAPI m Version
getVersion = singleton GetVersion

getHealth :: Monad m => MiscAPI m Health
getHealth = singleton GetHealth
