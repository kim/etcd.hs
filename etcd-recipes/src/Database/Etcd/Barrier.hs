-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Database.Etcd.Barrier where

import Control.Monad.Catch
import Control.Monad.Trans.Free
import Data.Etcd.Free


newtype BarrierError = BarrierError ErrorResponse
    deriving (Eq, Show)

instance Exception BarrierError


newtype Barrier = Barrier Node

create :: (MonadThrow m, MonadFree EtcdF m) => Key -> m Barrier
create k = do
    rs <- putKey k putOptions
    case responseBody rs of
        Error   e -> throwM $ BarrierError e
        Success s -> return $ Barrier (node s)

release :: (MonadThrow m, MonadFree EtcdF m) => Barrier -> m ()
release (Barrier n) = do
    rs <- deleteKey (key n) deleteOptions
    case responseBody rs of
        Error e | errorCode e /= 100 -> throwM $ BarrierError e
        _ -> return ()

waitOn :: (MonadThrow m, MonadFree EtcdF m) => Key -> m ()
waitOn k = get k >>= maybe (pure ()) wait

get :: (MonadThrow m, MonadFree EtcdF m) => Key -> m (Maybe Barrier)
get k = do
    rs <- getKey k getOptions { _gQuorum = True }
    case responseBody rs of
        Error e | errorCode e == 100 -> return Nothing
                | otherwise          -> throwM $ BarrierError e
        Success s -> return $ Just (Barrier (node s))

wait :: (MonadThrow m, MonadFree EtcdF m) => Barrier -> m ()
wait (Barrier bn) = watch bn
  where
    watch n = do
        rs' <- watchKey (key n) watchOptions { _wWaitIndex = Just (modifiedIndex n) }
        case responseBody rs' of
            Error   e -> throwM $ BarrierError e
            Success s -> case action s of
                ActionDelete -> return ()
                ActionExpire -> return ()
                _            -> watch (node s)
