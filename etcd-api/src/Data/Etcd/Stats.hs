-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GADTs         #-}

module Data.Etcd.Stats
    ( StatsAPI
    , StatsF          (..)
    , LeaderStats     (..)
    , FollowerStats   (..)
    , FollowerCounts  (..)
    , FollowerLatency (..)
    , SelfStats       (..)
    , LeaderInfo      (..)
    , StoreStats      (..)

    , getLeaderStats
    , getSelfStats
    , getStoreStats
    )
where

import Control.Monad.Operational
import Data.Aeson
import Data.Etcd.Internal
import Data.HashMap.Strict       (HashMap)
import Data.Text                 (Text)
import Data.Time
import Data.Word
import GHC.Generics


type StatsAPI = ProgramT StatsF

data StatsF a where
    GetLeaderStats :: StatsF LeaderStats
    GetSelfStats   :: StatsF SelfStats
    GetStoreStats  :: StatsF StoreStats

getLeaderStats :: Monad m => StatsAPI m LeaderStats
getLeaderStats = singleton GetLeaderStats

getSelfStats :: Monad m => StatsAPI m SelfStats
getSelfStats = singleton GetSelfStats

getStoreStats :: Monad m => StatsAPI m StoreStats
getStoreStats = singleton GetStoreStats


data LeaderStats = LeaderStats
    { lsLeader    :: !Text
    , lsFollowers :: !(HashMap Text FollowerStats)
    } deriving (Show, Generic)

instance FromJSON LeaderStats where parseJSON = gParsePrefixed


data FollowerStats = FollowerStats
    { fsCounts  :: !FollowerCounts
    , fsLatency :: !FollowerLatency
    } deriving (Show, Generic)

instance FromJSON FollowerStats where parseJSON = gParsePrefixed


data FollowerCounts = FollowerCounts
    { fcFail    :: !Word64
    , fcSuccess :: !Word64
    } deriving (Show, Generic)

instance FromJSON FollowerCounts where parseJSON = gParsePrefixed


data FollowerLatency = FollowerLatency
    { flAverage           :: !Double
    , flCurrent           :: !Double
    , flMaximum           :: !Double
    , flMinimum           :: !Double
    , flStandardDeviation :: !Double
    } deriving (Show, Generic)

instance FromJSON FollowerLatency where parseJSON = gParsePrefixed


data SelfStats = SelfStats
    { ssId                   :: !Text
    , ssLeaderInfo           :: !LeaderInfo
    , ssName                 :: !Text
    , ssRecvAppendRequestCnt :: !Word64
    , ssRecvBandwidthRate    :: !Double
    , ssRecvPkgRate          :: !Double
    , ssSendAppendRequestCnt :: !Word64
    , ssStartTime            :: !UTCTime
    , ssState                :: !Text -- todo
    } deriving (Show, Generic)

instance FromJSON SelfStats where parseJSON = gParsePrefixed


data LeaderInfo = LeaderInfo
    { liLeader    :: !Text
    , liStartTime :: !UTCTime
    , liUptime    :: !Text -- todo
    } deriving (Show, Generic)

instance FromJSON LeaderInfo where parseJSON = gParsePrefixed


data StoreStats = StoreStats
    { stsCompareAndSwapFail    :: !Word64
    , stsCompareAndSwapSuccess :: !Word64
    , stsCreateFail            :: !Word64
    , stsCreateSuccess         :: !Word64
    , stsDeleteFail            :: !Word64
    , stsDeleteSuccess         :: !Word64
    , stsExpireCount           :: !Word64
    , stsGetsFail              :: !Word64
    , stsGetsSuccess           :: !Word64
    , stsSetsFail              :: !Word64
    , stsSetsSuccess           :: !Word64
    , stsUpdateFail            :: !Word64
    , stsUpdateSuccess         :: !Word64
    , stsWatchers              :: !Word64
    } deriving (Show, Generic)

instance FromJSON StoreStats where parseJSON = gParsePrefixed
