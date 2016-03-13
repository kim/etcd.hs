-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveFunctor         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Data.Etcd.Free.Cluster where

import Control.Monad.Free.Class
import Data.Etcd.Types


data ClusterF a
    = ListMembers                    (Members -> a)
    | AddMember    PeerURLs          (Member  -> a)
    | DeleteMember MemberId          a
    | UpdateMember MemberId PeerURLs a
    deriving Functor


listMembers :: MonadFree ClusterF m => m Members
listMembers = liftF $ ListMembers id

addMember :: MonadFree ClusterF m => PeerURLs -> m Member
addMember urls = liftF $ AddMember urls id

deleteMember :: MonadFree ClusterF m => MemberId -> m ()
deleteMember m = liftF $ DeleteMember m ()

updateMember :: MonadFree ClusterF m => MemberId -> PeerURLs -> m ()
updateMember m urls = liftF $ UpdateMember m urls ()
