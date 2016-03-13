-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Control.Monad.Etcd
    ( MonadEtcd (..)

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

import           Control.Monad.Trans.Etcd
import qualified Data.Etcd.Free           as EF
import           Data.Etcd.Types


class (Functor m, Applicative m, Monad m) => MonadEtcd m where
    liftEtcd :: EtcdT m a -> m a

getKey :: MonadEtcd m => Key -> GetOptions -> m Response
getKey k = liftEtcd . EF.getKey k

putKey :: MonadEtcd m => Key -> PutOptions -> m Response
putKey k = liftEtcd . EF.putKey k

postKey :: MonadEtcd m => Key -> PostOptions -> m Response
postKey k = liftEtcd . EF.postKey k

deleteKey :: MonadEtcd m => Key -> DeleteOptions -> m Response
deleteKey k = liftEtcd . EF.deleteKey k

watchKey :: MonadEtcd m => Key -> WatchOptions -> m Response
watchKey k = liftEtcd . EF.watchKey k

keyExists :: MonadEtcd m => Key -> m Bool
keyExists = liftEtcd . EF.keyExists


listMembers :: MonadEtcd m => m Members
listMembers = liftEtcd EF.listMembers

addMember :: MonadEtcd m => PeerURLs -> m Member
addMember = liftEtcd . EF.addMember

deleteMember :: MonadEtcd m => MemberId -> m ()
deleteMember = liftEtcd . EF.deleteMember

updateMember :: MonadEtcd m => MemberId -> PeerURLs -> m ()
updateMember m = liftEtcd . EF.updateMember m


getLeaderStats :: MonadEtcd m => m LeaderStats
getLeaderStats = liftEtcd EF.getLeaderStats

getSelfStats :: MonadEtcd m => m SelfStats
getSelfStats = liftEtcd EF.getSelfStats

getStoreStats :: MonadEtcd m => m StoreStats
getStoreStats = liftEtcd EF.getStoreStats


getVersion :: MonadEtcd m => m Version
getVersion = liftEtcd EF.getVersion

getHealth :: MonadEtcd m => m Health
getHealth = liftEtcd EF.getHealth
