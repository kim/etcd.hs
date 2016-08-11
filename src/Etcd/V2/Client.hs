{-# OPTIONS_GHC -fno-warn-missing-signatures #-}

module Etcd.V2.Client
    ( -- * Keyspace API
      GetOptions    (..), getOptions
    , PutOptions    (..), putOptions
    , PostOptions   (..), postOptions
    , DeleteOptions (..), deleteOptions
    , WatchOptions  (..), watchOptions

    , getKey
    , putKey
    , postKey
    , deleteKey
    , keyExists
    , watchKey

      -- * Members API
    , listMembers
    , addMembers
    , deleteMember
    , updateMember

      -- * Admin API
    , getVersion
    , getHealth

      -- * Stats API
    , leaderStats
    , selfStats
    , storeStats
    )
where

import Data.Bool
import Data.Text           (Text)
import Data.Word
import Etcd.V2.API
import Network.HTTP.Client (Manager)
import Servant.API
import Servant.Client


type Endpoint a = Manager -> BaseUrl -> ClientM a

--------------------------------------------------------------------------------
-- Keyspace API (aka Client API)
--------------------------------------------------------------------------------

data GetOptions = GetOptions
    { _getRecursive :: !Bool
    , _getSorted    :: !Bool
    , _getQuorum    :: !Bool
    } deriving Show

getOptions :: GetOptions
getOptions = GetOptions
    { _getRecursive = False
    , _getSorted    = False
    , _getQuorum    = False
    }

data PutOptions = PutOptions
    { _putValue     :: Maybe Text
    , _putTTL       :: Maybe SetTTL
    , _putPrevValue :: Maybe Text
    , _putPrevIndex :: Maybe Word64
    , _putPrevExist :: Maybe Bool -- ^ 'Nothing' = don't care
    , _putRefresh   :: !Bool
    , _putDir       :: !Bool
    } deriving Show

putOptions :: PutOptions
putOptions = PutOptions
    { _putValue     = Nothing
    , _putTTL       = Nothing
    , _putPrevValue = Nothing
    , _putPrevIndex = Nothing
    , _putPrevExist = Nothing
    , _putRefresh   = False
    , _putDir       = False
    }

data PostOptions = PostOptions
    { _postValue :: Maybe Text
    , _postTTL   :: Maybe TTL
    } deriving Show

postOptions :: PostOptions
postOptions = PostOptions
    { _postValue = Nothing
    , _postTTL   = Nothing
    }

data DeleteOptions = DeleteOptions
    { _delRecursive :: !Bool
    , _delPrevValue :: Maybe Text
    , _delPrevIndex :: Maybe Word64
    , _delDir       :: !Bool
    } deriving Show

deleteOptions :: DeleteOptions
deleteOptions = DeleteOptions
    { _delRecursive = False
    , _delPrevValue = Nothing
    , _delPrevIndex = Nothing
    , _delDir       = False
    }

data WatchOptions = WatchOptions
    { _watchRecursive :: !Bool
    , _watchWaitIndex :: Maybe Word64
    } deriving Show

watchOptions :: WatchOptions
watchOptions = WatchOptions
    { _watchRecursive = False
    , _watchWaitIndex = Nothing
    }

put :<|> post :<|> get :<|> delete :<|> head' = client keyspaceAPI

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

keyExists :: Key -> Endpoint (KeyspaceResponseHeaders NoContent)
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

listMembers :<|> addMembers :<|> deleteMember :<|> updateMember = client membersAPI

--------------------------------------------------------------------------------
-- Admin API
--------------------------------------------------------------------------------

getVersion :<|> getHealth = client adminAPI

--------------------------------------------------------------------------------
-- Stats API
--------------------------------------------------------------------------------

leaderStats :<|> selfStats :<|> storeStats = client statsAPI

--------------------------------------------------------------------------------
-- Internal
--------------------------------------------------------------------------------

may :: Bool -> Maybe Bool
may = bool Nothing (Just True)
