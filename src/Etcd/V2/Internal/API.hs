-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE TypeOperators         #-}

{-# OPTIONS_GHC -fno-warn-missing-signatures -fno-warn-orphans #-}

-- | Definition of the etcd API in terms of @servant@ types.
--
-- This module is marked internal as the use of @servant@ is considered an
-- implementation detail, which may change without prior notice.
--
module Etcd.V2.Internal.API
    ( Versioned
    , PutCreated
    , Head
    , EtcdAPI, etcdAPI

      -- * Keyspace API (aka Client API)
    , KeyspaceResponseHeaders
    , KeyspaceResponse
    , KeyspaceAPI, keyspaceAPI
    , Endpoint
    , getKey
    , putKey
    , postKey
    , deleteKey
    , keyExists
    , watchKey

      -- * Members API
    , MembersAPI, membersAPI
    , listMembers
    , addMembers
    , deleteMember
    , updateMember

      -- * Admin API
    , AdminAPI, adminAPI
    , getVersion
    , getHealth

      -- * Stats API
    , StatsAPI, statsAPI
    , leaderStats
    , selfStats
    , storeStats
    )
where

import Data.Bool
import Data.Proxy
import Data.Text                (Text)
import Data.Word
import Etcd.V2.Types
import Network.HTTP.Client      (Manager)
import Servant.API
import Servant.API.ContentTypes
import Servant.Client


--------------------------------------------------------------------------------
-- Misc
--------------------------------------------------------------------------------

type Versioned = "v2"

type PutCreated = Verb 'PUT  201
type Head       = Verb 'HEAD 200


--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

type EtcdAPI = KeyspaceAPI :<|> MembersAPI :<|> AdminAPI :<|> StatsAPI

etcdAPI :: Proxy EtcdAPI
etcdAPI = Proxy

--------------------------------------------------------------------------------
-- Keyspace API
--------------------------------------------------------------------------------

type KeyspaceResponseHeaders
    = '[ Header "X-Etcd-Cluster-ID" Text
       , Header "X-Etcd-Index"      Word64
       , Header "X-Raft-Index"      Word64
       , Header "X-Raft-Term"       Word64
       ]

type KeyspaceResponse = Headers KeyspaceResponseHeaders Response

type KeyspaceAPI = Versioned :> "keys" :>
    (     Capture    "key"       Text
       :> QueryParam "value"     Value
       :> QueryParam "ttl"       SetTTL
       :> QueryParam "prevValue" Value
       :> QueryParam "prevIndex" Word64
       :> QueryParam "prevExist" Bool
       :> QueryParam "refresh"   Bool
       :> QueryParam "dir"       Bool
       :> PutCreated '[JSON] KeyspaceResponse
  :<|>    Capture    "key"       Text
       :> QueryParam "value"     Value
       :> QueryParam "ttl"       TTL
       :> PostCreated '[JSON] KeyspaceResponse
  :<|>    Capture    "key"       Text
       :> QueryParam "recursive" Bool
       :> QueryParam "sorted"    Bool
       :> QueryParam "quorum"    Bool
       :> QueryParam "wait"      Bool
       :> QueryParam "waitIndex" Word64
       :> Get '[JSON] KeyspaceResponse
  :<|>    Capture    "key"       Text
       :> QueryParam "recursive" Bool
       :> QueryParam "prevValue" Value
       :> QueryParam "prevIndex" Word64
       :> QueryParam "dir"       Bool
       :> Delete '[JSON] KeyspaceResponse
  :<|>    Capture    "key"       Text
       :> Head '[JSON] (Headers KeyspaceResponseHeaders NoContent)
    )

keyspaceAPI :: Proxy KeyspaceAPI
keyspaceAPI = Proxy

put :<|> post :<|> get :<|> delete :<|> head' = client keyspaceAPI

type Endpoint a = Manager -> BaseUrl -> ClientM a

getKey :: Key -> GetOptions -> Endpoint KeyspaceResponse
getKey k GetOptions { _getRecursive = recursive
                    , _getSorted    = sorted
                    , _getQuorum    = quorum
                    }
    = get k (may recursive) (may sorted) (may quorum) Nothing Nothing

putKey :: Key -> PutOptions -> Endpoint KeyspaceResponse
putKey k PutOptions { _putValue     = value
                    , _putTTL       = ttl
                    , _putPrevValue = prevValue
                    , _putPrevIndex = prevIndex
                    , _putPrevExist = prevExist
                    , _putRefresh   = refresh
                    , _putDir       = dir
                    }
    = put k value ttl prevValue prevIndex prevExist (may refresh) (may dir)

postKey :: Key -> PostOptions -> Endpoint KeyspaceResponse
postKey k PostOptions { _postValue = value, _postTTL = ttl }
    = post k value ttl

deleteKey :: Key -> DeleteOptions -> Endpoint KeyspaceResponse
deleteKey k DeleteOptions { _delRecursive = recursive
                          , _delPrevValue = prevValue
                          , _delPrevIndex = prevIndex
                          , _delDir       = dir
                          }
    = delete k (may recursive) prevValue prevIndex (may dir)

keyExists :: Key -> Endpoint (Headers KeyspaceResponseHeaders NoContent)
keyExists = head'

watchKey :: Key -> WatchOptions -> Endpoint KeyspaceResponse
watchKey k opts
    = get k
          (may (_watchRecursive opts))
          (Just False)
          (Just False)
          (Just True)
          (_watchWaitIndex opts)


--------------------------------------------------------------------------------
-- Members API
--------------------------------------------------------------------------------

type MembersAPI = Versioned :> "members" :>
    (  Get '[JSON] Members
  :<|> ReqBody '[JSON] PeerURLs :> PostCreated '[JSON] Member
  :<|> Capture "id" Text :> DeleteNoContent '[JSON] NoContent
  :<|> Capture "id" Text :> ReqBody '[JSON] PeerURLs :> PutNoContent '[JSON] NoContent
    )

membersAPI :: Proxy MembersAPI
membersAPI = Proxy

listMembers :<|> addMembers :<|> deleteMember :<|> updateMember = client membersAPI


--------------------------------------------------------------------------------
-- Admin API
--------------------------------------------------------------------------------

type AdminAPI
     = "version" :> Get '[JSON]      Version
  :<|> "health"  :> Get '[PlainText] Health

instance MimeUnrender PlainText Health where
    mimeUnrender _ = eitherDecodeLenient

adminAPI :: Proxy AdminAPI
adminAPI = Proxy

getVersion :<|> getHealth = client adminAPI


--------------------------------------------------------------------------------
-- Stats API
--------------------------------------------------------------------------------

type StatsAPI = Versioned :> "stats" :>
    (  "leader" :> Get '[JSON] LeaderStats
  :<|> "self"   :> Get '[JSON] SelfStats
  :<|> "store"  :> Get '[JSON] StoreStats
    )

statsAPI :: Proxy StatsAPI
statsAPI = Proxy

leaderStats :<|> selfStats :<|> storeStats = client statsAPI


--------------------------------------------------------------------------------
-- Internal
--------------------------------------------------------------------------------

may :: Bool -> Maybe Bool
may = bool Nothing (Just True)
