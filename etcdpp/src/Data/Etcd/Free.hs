-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveFunctor         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Data.Etcd.Free
    ( EtcdF (..)

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
import Data.Etcd.Types


data EtcdF a
    -- keyspace
    = GetKey    Key GetOptions    (Response -> a)
    | PutKey    Key PutOptions    (Response -> a)
    | PostKey   Key PostOptions   (Response -> a)
    | DeleteKey Key DeleteOptions (Response -> a)
    | WatchKey  Key WatchOptions  (Response -> a)
    | KeyExists Key               (Bool     -> a)

    -- members
    | ListMembers                    (Members -> a)
    | AddMember    PeerURLs          (Member  -> a)
    | DeleteMember MemberId          a
    | UpdateMember MemberId PeerURLs a

    -- stats
    | GetLeaderStats (LeaderStats -> a)
    | GetSelfStats   (SelfStats   -> a)
    | GetStoreStats  (StoreStats  -> a)

    -- misc
    | GetVersion (Version -> a)
    | GetHealth  (Health  -> a)
    deriving Functor


getKey :: MonadFree EtcdF m => Key -> GetOptions -> m Response
getKey k o = liftF $ GetKey k o id

putKey :: MonadFree EtcdF m => Key -> PutOptions -> m Response
putKey k o = liftF $ PutKey k o id

postKey :: MonadFree EtcdF m => Key -> PostOptions -> m Response
postKey k o = liftF $ PostKey k o id

deleteKey :: MonadFree EtcdF m => Key -> DeleteOptions -> m Response
deleteKey k o = liftF $ DeleteKey k o id

watchKey :: MonadFree EtcdF m => Key -> WatchOptions -> m Response
watchKey k o = liftF $ WatchKey k o id

keyExists :: MonadFree EtcdF m => Key -> m Bool
keyExists k = liftF $ KeyExists k id


listMembers :: MonadFree EtcdF m => m Members
listMembers = liftF $ ListMembers id

addMember :: MonadFree EtcdF m => PeerURLs -> m Member
addMember urls = liftF $ AddMember urls id

deleteMember :: MonadFree EtcdF m => MemberId -> m ()
deleteMember m = liftF $ DeleteMember m ()

updateMember :: MonadFree EtcdF m => MemberId -> PeerURLs -> m ()
updateMember m urls = liftF $ UpdateMember m urls ()


getLeaderStats :: MonadFree EtcdF m => m LeaderStats
getLeaderStats = liftF $ GetLeaderStats id

getSelfStats :: MonadFree EtcdF m => m SelfStats
getSelfStats = liftF $ GetSelfStats id

getStoreStats :: MonadFree EtcdF m => m StoreStats
getStoreStats = liftF $ GetStoreStats id


getVersion :: MonadFree EtcdF m => m Version
getVersion = liftF $ GetVersion id

getHealth :: MonadFree EtcdF m => m Health
getHealth = liftF $ GetHealth id