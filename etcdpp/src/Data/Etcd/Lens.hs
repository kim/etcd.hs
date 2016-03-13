-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE LambdaCase      #-}
{-# LANGUAGE Rank2Types      #-}
{-# LANGUAGE TemplateHaskell #-}

module Data.Etcd.Lens
    ( -- * Responses
      rsMeta
    , rsBody
    , rsAction
    , rsNode
    , rsPrevNode
    , rsErrorCode
    , rsMessage
    , rsCause
    , rsIndex

    , etcdClusterId
    , etcdIndex
    , raftIndex
    , raftTerm

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

      -- * Response Prisms
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

import Control.Exception
import Control.Lens
import Data.Etcd.Types
import Data.Word


makeLenses ''Rs
makeLenses ''Node
makeLenses ''ResponseMeta
makeLenses ''SuccessResponse
makeLenses ''ErrorResponse
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

_EtcdError :: Prism' SomeException EtcdError
_EtcdError = prism' toException fromException

_KeyNotFound :: Prism' Response (Rs ErrorResponse)
_KeyNotFound = _Left . hasCode 100

_TestFailed :: Prism' Response (Rs ErrorResponse)
_TestFailed = _Left . hasCode 101

_NotFile :: Prism' Response (Rs ErrorResponse)
_NotFile = _Left . hasCode 102

_NotDir :: Prism' Response (Rs ErrorResponse)
_NotDir = _Left . hasCode 104

_NodeExist :: Prism' Response (Rs ErrorResponse)
_NodeExist = _Left . hasCode 105

_RootOnly :: Prism' Response (Rs ErrorResponse)
_RootOnly = _Left . hasCode 107

_DirNotEmpty :: Prism' Response (Rs ErrorResponse)
_DirNotEmpty = _Left . hasCode 108

_Unauthorized :: Prism' Response (Rs ErrorResponse)
_Unauthorized = _Left . hasCode 110

_PrevValueRequired :: Prism' Response (Rs ErrorResponse)
_PrevValueRequired = _Left . hasCode 201

_TTLNaN :: Prism' Response (Rs ErrorResponse)
_TTLNaN = _Left . hasCode 202

_IndexNaN :: Prism' Response (Rs ErrorResponse)
_IndexNaN = _Left . hasCode 203

_InvalidField :: Prism' Response (Rs ErrorResponse)
_InvalidField = _Left . hasCode 209

_RaftInternal :: Prism' Response (Rs ErrorResponse)
_RaftInternal = _Left . hasCode 300

_LeaderElect :: Prism' Response (Rs ErrorResponse)
_LeaderElect = _Left . hasCode 301

_WatcherCleared :: Prism' Response (Rs ErrorResponse)
_WatcherCleared = _Left . hasCode 400

_EventIndexCleared :: Prism' Response (Rs ErrorResponse)
_EventIndexCleared = _Left . hasCode 401

hasCode
    :: ( Choice      p
       , Applicative f
       )
    => Word16
    -> Optic' p f (Rs ErrorResponse) (Rs ErrorResponse)
hasCode n = filtered ((n ==) . _rsErrorCode . _rsBody)
