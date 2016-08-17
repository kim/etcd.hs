-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}

module Etcd.V2.Client
    ( EtcdM

    , newEtcdEnv
    , runEtcdM

      -- * Keyspace API
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

      -- * Re-exports
    , module Etcd.V2.Types
    , HasEnv (..)
    )
where

import           Control.Exception
import           Control.Lens               (view)
import           Control.Monad.Reader
import           Control.Monad.Trans.Except
import           Data.Aeson                 (eitherDecode)
import qualified Data.ByteString.Lazy       as BS
import           Data.Text                  (Text)
import qualified Etcd.V2.Internal.API       as API
import           Etcd.V2.Lens               (HasEnv (..))
import           Etcd.V2.Types
import           Network.HTTP.Client
import           Network.HTTP.Types.Status  (Status (..))
import           Servant.API
import           Servant.Client


type EtcdM e = ReaderT e (ExceptT EtcdError IO)

-- | Construct a new environment from a URL string.
--
-- The 'Env' can be modified using the lenses provided in 'Etcd.V2.Lens', eg. to
-- supply your own 'Network.HTTP.Client.Manager'.
--
newEtcdEnv :: String -> IO Env
newEtcdEnv url = Env <$> newManager defaultManagerSettings <*> parseBaseUrl url

runEtcdM :: HasEnv e => e -> EtcdM e a -> IO (Either EtcdError a)
runEtcdM e f = runExceptT $ runReaderT f e


--------------------------------------------------------------------------------
-- Keyspace API
--------------------------------------------------------------------------------

getKey :: HasEnv e => Key -> GetOptions -> EtcdM e ResponseAndMetadata
getKey k = keyspace . API.getKey k

putKey :: HasEnv e => Key -> PutOptions -> EtcdM e ResponseAndMetadata
putKey k = keyspace . API.putKey k

postKey :: HasEnv e => Key -> PostOptions -> EtcdM e ResponseAndMetadata
postKey k = keyspace . API.postKey k

deleteKey :: HasEnv e => Key -> DeleteOptions -> EtcdM e ResponseAndMetadata
deleteKey k = keyspace . API.deleteKey k

keyExists :: HasEnv e => Key -> EtcdM e Bool
keyExists k = call $ \mgr url ->
    (const True <$> API.keyExists k mgr url) `catchE` notFound
  where
    notFound (FailureResponse (Status 404 _) _ _) = pure False
    notFound e                                    = throwE e

watchKey :: HasEnv e => Key -> WatchOptions -> EtcdM e ResponseAndMetadata
watchKey k = keyspace . API.watchKey k


--------------------------------------------------------------------------------
-- Members API
--------------------------------------------------------------------------------

listMembers :: HasEnv e => EtcdM e Members
listMembers = call API.listMembers

addMembers :: HasEnv e => PeerURLs -> EtcdM e Member
addMembers = call . API.addMembers

deleteMember :: HasEnv e => Text -> EtcdM e NoContent
deleteMember = call . API.deleteMember

updateMember :: HasEnv e => Text -> PeerURLs -> EtcdM e NoContent
updateMember mid = call . API.updateMember mid


--------------------------------------------------------------------------------
-- Admin API
--------------------------------------------------------------------------------

getVersion :: HasEnv e => EtcdM e Version
getVersion = call API.getVersion

getHealth :: HasEnv e => EtcdM e Health
getHealth = call API.getHealth


--------------------------------------------------------------------------------
-- Stats API
--------------------------------------------------------------------------------

leaderStats :: HasEnv e => EtcdM e LeaderStats
leaderStats = call API.leaderStats

selfStats :: HasEnv e => EtcdM e SelfStats
selfStats = call API.selfStats

storeStats :: HasEnv e => EtcdM e StoreStats
storeStats = call API.storeStats

--------------------------------------------------------------------------------
-- Internal
--------------------------------------------------------------------------------

keyspace
    :: HasEnv e
    => (Manager -> BaseUrl -> ClientM API.KeyspaceResponse)
    -> EtcdM e ResponseAndMetadata
keyspace f = call $ \mgr url -> do
    rs <- f mgr url
    return $ responseAndMetadata rs

responseAndMetadata :: API.KeyspaceResponse -> ResponseAndMetadata
responseAndMetadata rs = ResponseAndMetadata
    { _rsResponse = getResponse rs
    , _rsMetadata = meta (getHeadersHList rs)
    }

meta :: HList API.KeyspaceResponseHeaders -> Maybe ResponseHeaders
meta (HCons (Header clusterID)
            (HCons (Header etcdIndex)
                   (HCons (Header raftIndex)
                          (HCons (Header raftTerm) HNil))))
  = Just ResponseHeaders
      { _rsEtcdClusterID = clusterID
      , _rsEtcdIndex     = etcdIndex
      , _rsRaftIndex     = raftIndex
      , _rsRaftTerm      = raftTerm
      }
meta _ = Nothing

call :: HasEnv e => (Manager -> BaseUrl -> ClientM a) -> EtcdM e a
call f = do
    mgr <- view envManager
    url <- view envBaseUrl
    lift . withExceptT mapErrors $
        f mgr url
  where
    mapErrors (FailureResponse status _ body)
      | BS.null body = HttpError status body
      | otherwise    = either (`DecodeError` body) EtcdError $ eitherDecode body

    mapErrors (DecodeFailure err _ body) = DecodeError err body
    mapErrors (ConnectionError ex)       = TransportError ex
    mapErrors unexpected                 = UnexpectedError (SomeException unexpected)
