-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE LambdaCase      #-}
{-# LANGUAGE Rank2Types      #-}
{-# LANGUAGE TemplateHaskell #-}

module Etcd.V2.Lens
    ( -- * Environment
      HasEnv (..)

      -- * Responses
      -- ** Success Response
    , rsAction
    , rsNode
    , rsPrevNode

      -- ** Error Response
    , rsErrorCode
    , rsMessage
    , rsCause
    , rsIndex

      -- ** Response Metadata / Headers
    , rsResponse
    , rsMetadata

    , rsEtcdClusterID
    , rsEtcdIndex
    , rsRaftIndex
    , rsRaftTerm

      -- ** Error Prisms
    , _EtcdError
    , _HttpError
    , _DecodeError
    , _TransportError
    , _UnexpectedError

    , _KeyNotFound
    , _TestFailed
    , _NotFile
    , _NotDir
    , _NodeExist
    , _RootOnly
    , _DirNotEmpty
    , _Unauthorized
    , _PrevValueRequired
    , _TTLNaN
    , _IndexNaN
    , _InvalidField
    , _RaftInternal
    , _LeaderElect
    , _WatcherCleared
    , _EventIndexCleared

    , nodeKey
    , nodeDir
    , nodeValue
    , nodeNodes
    , nodeCreatedIndex
    , nodeModifiedIndex
    , nodeExpiration
    , nodeTTL

      -- * 'GetOptions'
    , getRecursive
    , getSorted
    , getQuorum

      -- * 'PutOptions'
    , putValue
    , putTTL
    , putPrevValue
    , putPrevIndex
    , putPrevExist
    , putRefresh
    , putDir

      -- * 'PostOptions'
    , postValue
    , postTTL

      -- * 'DeleteOptions'
    , delRecursive
    , delPrevValue
    , delPrevIndex
    , delDir

      -- * 'WatchOptions'
    , watchRecursive
    , watchWaitIndex

      -- * 'Member'
    , mId
    , mName
    , mPeerURLs
    , mClientURLs

      -- * 'LeaderStats'
    , lsLeader
    , lsFollowers

      -- * 'FollowerStats'
    , fsCounts
    , fsLatency

      -- * 'FollowerCounts'
    , fcFail
    , fcSuccess

      -- * 'FollowerLatency'
    , flAverage
    , flCurrent
    , flMaximum
    , flMinimum
    , flStandardDeviation

      -- * 'SelfStats'
    , ssId
    , ssLeaderInfo
    , ssName
    , ssRecvAppendRequestCnt
    , ssRecvBandwidthRate
    , ssRecvPkgRate
    , ssSendAppendRequestCnt
    , ssStartTime
    , ssState

      -- * 'LeaderInfo'
    , liLeader
    , liStartTime
    , liUptime

      -- * 'StoreStats'
    , stsCompareAndSwapFail
    , stsCompareAndSwapSuccess
    , stsCreateFail
    , stsCreateSuccess
    , stsDeleteFail
    , stsDeleteSuccess
    , stsExpireCount
    , stsGetsFail
    , stsGetsSuccess
    , stsSetsFail
    , stsSetsSuccess
    , stsUpdateFail
    , stsUpdateSuccess
    , stsWatchers
    )
where

import Control.Lens
import Data.Word
import Etcd.V2.Types
import Network.HTTP.Client (Manager)
import Servant.Client      (BaseUrl)


class HasEnv a where
    envManager :: Getting Manager a Manager
    envBaseUrl :: Getting BaseUrl a BaseUrl

instance HasEnv Env where
    envManager = to _envManager
    envBaseUrl = to _envBaseUrl

makePrisms ''EtcdError
makeLenses ''Node
makeLenses ''Response
makeLenses ''ErrorResponse
makeLenses ''ResponseHeaders
makeLenses ''ResponseAndMetadata
makeLenses ''GetOptions
makeLenses ''PutOptions
makeLenses ''PostOptions
makeLenses ''DeleteOptions
makeLenses ''WatchOptions
makeLenses ''Member
makeLenses ''LeaderStats
makeLenses ''FollowerStats
makeLenses ''FollowerCounts
makeLenses ''FollowerLatency
makeLenses ''SelfStats
makeLenses ''LeaderInfo
makeLenses ''StoreStats


_KeyNotFound :: Prism' EtcdError ErrorResponse
_KeyNotFound = _EtcdError . hasCode 100

_TestFailed :: Prism' EtcdError ErrorResponse
_TestFailed = _EtcdError . hasCode 101

_NotFile :: Prism' EtcdError ErrorResponse
_NotFile = _EtcdError . hasCode 102

_NotDir :: Prism' EtcdError ErrorResponse
_NotDir = _EtcdError . hasCode 104

_NodeExist :: Prism' EtcdError ErrorResponse
_NodeExist = _EtcdError . hasCode 105

_RootOnly :: Prism' EtcdError ErrorResponse
_RootOnly = _EtcdError . hasCode 107

_DirNotEmpty :: Prism' EtcdError ErrorResponse
_DirNotEmpty = _EtcdError . hasCode 108

_Unauthorized :: Prism' EtcdError ErrorResponse
_Unauthorized = _EtcdError . hasCode 110

_PrevValueRequired :: Prism' EtcdError ErrorResponse
_PrevValueRequired = _EtcdError . hasCode 201

_TTLNaN :: Prism' EtcdError ErrorResponse
_TTLNaN = _EtcdError . hasCode 202

_IndexNaN :: Prism' EtcdError ErrorResponse
_IndexNaN = _EtcdError . hasCode 203

_InvalidField :: Prism' EtcdError ErrorResponse
_InvalidField = _EtcdError . hasCode 209

_RaftInternal :: Prism' EtcdError ErrorResponse
_RaftInternal = _EtcdError . hasCode 300

_LeaderElect :: Prism' EtcdError ErrorResponse
_LeaderElect = _EtcdError . hasCode 301

_WatcherCleared :: Prism' EtcdError ErrorResponse
_WatcherCleared = _EtcdError . hasCode 400

_EventIndexCleared :: Prism' EtcdError ErrorResponse
_EventIndexCleared = _EtcdError . hasCode 401

hasCode
    :: ( Choice      p
       , Applicative f
       )
    => Word16
    -> Optic' p f ErrorResponse ErrorResponse
hasCode n = filtered ((n ==) . _rsErrorCode)
