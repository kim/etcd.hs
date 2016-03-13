-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveFunctor         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Data.Etcd.Free
    ( EtcdF     (..)
    , KeyspaceF (..)
    , ClusterF  (..)
    , MiscF     (..)
    , StatsF    (..)

    , getKey
    , putKey
    , postKey
    , deleteKey
    , watchKey
    , keyExists

    , listMembers
    , addMember
    , deleteMember
    , updateMember

    , getLeaderStats
    , getSelfStats
    , getStoreStats

    , getVersion
    , getHealth

    , module Data.Etcd.Types
    )
where

import Control.Monad.Free.Class
import Data.Etcd.Free.Keyspace  (KeyspaceF (..))
import Data.Etcd.Free.Cluster   (ClusterF (..))
import Data.Etcd.Free.Misc      (MiscF (..))
import Data.Etcd.Free.Stats     (StatsF (..))
import Data.Etcd.Types


data EtcdF a
    = Keyspace (KeyspaceF a)
    | Cluster  (ClusterF  a)
    | Stats    (StatsF    a)
    | Misc     (MiscF     a)
    deriving Functor

getKey :: MonadFree EtcdF m => Key -> GetOptions -> m Response
getKey k o = liftF . Keyspace $ GetKey k o id

putKey :: MonadFree EtcdF m => Key -> PutOptions -> m Response
putKey k o = liftF . Keyspace $ PutKey k o id

postKey :: MonadFree EtcdF m => Key -> PostOptions -> m Response
postKey k o = liftF . Keyspace $ PostKey k o id

deleteKey :: MonadFree EtcdF m => Key -> DeleteOptions -> m Response
deleteKey k o = liftF . Keyspace $ DeleteKey k o id

watchKey :: MonadFree EtcdF m => Key -> WatchOptions -> m Response
watchKey k o = liftF . Keyspace $ WatchKey k o id

keyExists :: MonadFree EtcdF m => Key -> m Bool
keyExists k = liftF . Keyspace $ KeyExists k id


listMembers :: MonadFree EtcdF m => m Members
listMembers = liftF . Cluster $ ListMembers id

addMember :: MonadFree EtcdF m => PeerURLs -> m Member
addMember urls = liftF . Cluster $ AddMember urls id

deleteMember :: MonadFree EtcdF m => MemberId -> m ()
deleteMember m = liftF . Cluster $ DeleteMember m ()

updateMember :: MonadFree EtcdF m => MemberId -> PeerURLs -> m ()
updateMember m urls = liftF . Cluster $ UpdateMember m urls ()


getLeaderStats :: MonadFree EtcdF m => m LeaderStats
getLeaderStats = liftF . Stats $ GetLeaderStats id

getSelfStats :: MonadFree EtcdF m => m SelfStats
getSelfStats = liftF . Stats $ GetSelfStats id

getStoreStats :: MonadFree EtcdF m => m StoreStats
getStoreStats = liftF . Stats $ GetStoreStats id


getVersion :: MonadFree EtcdF m => m Version
getVersion = liftF . Misc $ GetVersion id

getHealth :: MonadFree EtcdF m => m Health
getHealth = liftF . Misc $ GetHealth id
