-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE Rank2Types #-}

module Data.Etcd
    ( EtcdAPI     (..)
    , EvalEtcdAPI (evalEtcd)
    , module Data.Etcd.Keys
    , module Data.Etcd.Members
    , module Data.Etcd.Stats
    , module Data.Etcd.Misc
    )
where

import Data.Etcd.Keys
import Data.Etcd.Members
import Data.Etcd.Stats
import Data.Etcd.Misc


data EtcdAPI m a = EtcdAPI
    { evalKeysAPI    :: KeysAPI    m a -> m a
    , evalMembersAPI :: MembersAPI m a -> m a
    , evalStatsAPI   :: StatsAPI   m a -> m a
    , evalMiscAPI    :: MiscAPI    m a -> m a
    }

class EvalEtcdAPI f where
    evalEtcd :: EtcdAPI m a -> f m a -> m a

instance EvalEtcdAPI KeysAPI    where evalEtcd = evalKeysAPI
instance EvalEtcdAPI MembersAPI where evalEtcd = evalMembersAPI
instance EvalEtcdAPI StatsAPI   where evalEtcd = evalStatsAPI
instance EvalEtcdAPI MiscAPI    where evalEtcd = evalMiscAPI
