-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ViewPatterns          #-}

module Data.Etcd.Recipes.Barrier where

import Control.Lens
import Control.Monad (void)
import Control.Monad.Catch
import Control.Monad.Trans.Free
import Data.Etcd.Free
import Data.Etcd.Lens


newtype Barrier = Barrier Node

create :: (MonadThrow m, MonadFree EtcdF m) => Key -> m Barrier
create k
    = putKey k putOptions
  >>= fmap (Barrier . view (rsBody . rsNode)) . hoistError

release :: (MonadThrow m, MonadFree EtcdF m) => Barrier -> m ()
release (Barrier (view nodeKey -> n))
    = deleteKey n deleteOptions
  >>= either (void . hoistError) (const (return ()))
    . matching _KeyNotFound

waitOn :: (MonadThrow m, MonadFree EtcdF m) => Key -> m ()
waitOn k = get k >>= maybe (pure ()) wait

get :: (MonadThrow m, MonadFree EtcdF m) => Key -> m (Maybe Barrier)
get k = getKey k getOptions { _getQuorum = True }
    >>= either (fmap (Just . Barrier . view (rsBody . rsNode)) . hoistError)
               (const (return Nothing))
      . matching _KeyNotFound

wait :: (MonadThrow m, MonadFree EtcdF m) => Barrier -> m ()
wait (Barrier bn) = watch bn
  where
    watch n = do
        rs <- watchKey (_nodeKey n)
                       watchOptions { _watchWaitIndex = Just (_nodeModifiedIndex n) }
            >>= hoistError
        case view (rsBody . rsAction) rs of
            ActionDelete -> return ()
            ActionExpire -> return ()
            _            -> watch (view (rsBody . rsNode) rs)
