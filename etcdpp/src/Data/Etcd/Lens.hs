-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE Rank2Types #-}

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
    , gRecursive
    , gSorted
    , gQuorum

      -- * 'PutOptions'
    , pValue
    , pTTL
    , pPrevValue
    , pPrevIndex
    , pPrevExist
    , pRefresh
    , pDir

      -- * 'PostOptions'
    , cValue
    , cTTL

      -- * 'DeleteOptions'
    , dRecursive
    , dPrevValue
    , dPrevIndex
    , dDir

      -- * 'WatchOptions'
    , wRecursive
    , wWaitIndex

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
    )
where

import Control.Exception
import Control.Lens
import Data.Etcd.Types
import Data.Text         (Text)
import Data.Time         (UTCTime)
import Data.Word         (Word16, Word64)


rsMeta :: Lens' (Rs a) ResponseMeta
rsMeta = lens _rsMeta (\s a -> s { _rsMeta = a })

rsBody :: Lens' (Rs a) a
rsBody = lens _rsBody (\s a -> s { _rsBody = a })

rsAction :: Lens' SuccessResponse Action
rsAction = lens _rsAction (\s a -> s { _rsAction = a })

rsNode :: Lens' SuccessResponse Node
rsNode = lens _rsNode (\s a -> s { _rsNode = a })

rsPrevNode :: Lens' SuccessResponse (Maybe Node)
rsPrevNode = lens _rsPrevNode (\s a -> s { _rsPrevNode = a })

rsErrorCode :: Lens' ErrorResponse Word16
rsErrorCode = lens _rsErrorCode (\s a -> s { _rsErrorCode = a })

rsMessage :: Lens' ErrorResponse Text
rsMessage = lens _rsMessage (\s a -> s { _rsMessage = a })

rsCause :: Lens' ErrorResponse Text
rsCause = lens _rsCause (\s a -> s { _rsCause = a })

rsIndex :: Lens' ErrorResponse Word64
rsIndex = lens _rsIndex (\s a -> s { _rsIndex = a })

etcdClusterId :: Lens' ResponseMeta Text
etcdClusterId = lens _etcdClusterId (\s a -> s { _etcdClusterId = a })

etcdIndex :: Lens' ResponseMeta Word64
etcdIndex = lens _etcdIndex (\s a -> s { _etcdIndex = a })

raftIndex :: Lens' ResponseMeta (Maybe Word64)
raftIndex = lens _raftIndex (\s a -> s { _raftIndex = a })

raftTerm :: Lens' ResponseMeta (Maybe Word64)
raftTerm = lens _raftTerm (\s a -> s { _raftTerm = a })


nodeKey :: Lens' Node Text
nodeKey = lens _nodeKey (\s a -> s { _nodeKey = a })

nodeDir :: Lens' Node Bool
nodeDir = lens _nodeDir (\s a -> s { _nodeDir = a })

nodeValue :: Lens' Node (Maybe Text)
nodeValue = lens _nodeValue (\s a -> s { _nodeValue = a })

nodeNodes :: Lens' Node [Node]
nodeNodes = lens _nodeNodes (\s a -> s { _nodeNodes = a })

nodeCreatedIndex :: Lens' Node Word64
nodeCreatedIndex = lens _nodeCreatedIndex (\s a -> s { _nodeCreatedIndex = a })

nodeModifiedIndex :: Lens' Node Word64
nodeModifiedIndex = lens _nodeModifiedIndex (\s a -> s { _nodeModifiedIndex = a })

nodeExpiration :: Lens' Node (Maybe UTCTime)
nodeExpiration = lens _nodeExpiration (\s a -> s { _nodeExpiration = a })

nodeTTL :: Lens' Node (Maybe TTL)
nodeTTL = lens _nodeTTL (\s a -> s { _nodeTTL = a })


gRecursive :: Lens' GetOptions Bool
gRecursive = lens _gRecursive (\s a -> s { _gRecursive = a })

gSorted :: Lens' GetOptions Bool
gSorted = lens _gSorted (\s a -> s { _gSorted = a })

gQuorum :: Lens' GetOptions Bool
gQuorum = lens _gQuorum (\s a -> s { _gQuorum = a })


pValue :: Lens' PutOptions (Maybe Value)
pValue = lens _pValue (\s a -> s { _pValue = a })

pTTL :: Lens' PutOptions (Maybe SetTTL)
pTTL = lens _pTTL (\s a -> s { _pTTL = a })

pPrevValue :: Lens' PutOptions (Maybe Value)
pPrevValue = lens _pPrevValue (\s a -> s { _pPrevValue = a })

pPrevIndex :: Lens' PutOptions (Maybe Word64)
pPrevIndex = lens _pPrevIndex (\s a -> s { _pPrevIndex = a })

pPrevExist :: Lens' PutOptions (Maybe Bool)
pPrevExist = lens _pPrevExist (\s a -> s { _pPrevExist = a })

pRefresh :: Lens' PutOptions Bool
pRefresh = lens _pRefresh (\s a -> s { _pRefresh = a })

pDir :: Lens' PutOptions Bool
pDir = lens _pDir (\s a -> s { _pDir = a })


cValue :: Lens' PostOptions (Maybe Text)
cValue = lens _cValue (\s a -> s { _cValue = a })

cTTL :: Lens' PostOptions (Maybe Word64)
cTTL = lens _cTTL (\s a -> s { _cTTL = a })


dRecursive :: Lens' DeleteOptions Bool
dRecursive = lens _dRecursive (\s a -> s { _dRecursive = a })

dPrevValue :: Lens' DeleteOptions (Maybe Value)
dPrevValue = lens _dPrevValue (\s a -> s { _dPrevValue = a })

dPrevIndex :: Lens' DeleteOptions (Maybe Word64)
dPrevIndex = lens _dPrevIndex (\s a -> s { _dPrevIndex = a })

dDir :: Lens' DeleteOptions Bool
dDir = lens _dDir (\s a -> s { _dDir = a })


wRecursive :: Lens' WatchOptions Bool
wRecursive = lens _wRecursive (\s a -> s { _wRecursive = a })

wWaitIndex :: Lens' WatchOptions (Maybe Word64)
wWaitIndex = lens _wWaitIndex (\s a -> s { _wWaitIndex = a })


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
