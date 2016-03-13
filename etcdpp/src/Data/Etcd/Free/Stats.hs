-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveFunctor         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Data.Etcd.Free.Stats where

import Control.Monad.Free.Class
import Data.Etcd.Types


data StatsF a
    = GetLeaderStats (LeaderStats -> a)
    | GetSelfStats   (SelfStats   -> a)
    | GetStoreStats  (StoreStats  -> a)
    deriving Functor


getLeaderStats :: MonadFree StatsF m => m LeaderStats
getLeaderStats = liftF $ GetLeaderStats id

getSelfStats :: MonadFree StatsF m => m SelfStats
getSelfStats = liftF $ GetSelfStats id

getStoreStats :: MonadFree StatsF m => m StoreStats
getStoreStats = liftF $ GetStoreStats id
