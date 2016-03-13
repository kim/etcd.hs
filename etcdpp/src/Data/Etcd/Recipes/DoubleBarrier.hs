-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE Rank2Types            #-}

module Data.Etcd.Recipes.DoubleBarrier
    ( Entered
    , MayLeave

    , enter
    , leave

    , withDoubleBarrier
    , onEntered
    )
where

import Control.Concurrent.Async.Lifted
import Control.Monad                   (void)
import Control.Monad.Catch
import Control.Monad.Etcd              (MonadEtcd (..))
import Control.Monad.IO.Class
import Control.Monad.Trans.Control
import Control.Monad.Trans.Etcd
import Control.Monad.Trans.Free
import Data.Bifunctor
import Data.Etcd.Free
import Data.Etcd.Recipes.Ephemeral
import Data.Etcd.Recipes.Internal
import Data.Function                   (on)
import Data.Monoid
import Data.Text                       (Text)
import Data.Void                       (absurd)
import Data.Word                       (Word16)


data Entered  m = Entered  (EphemeralNode m) (m MayLeave)
data MayLeave   = MayLeave Key Key


withDoubleBarrier
    :: ( MonadIO             m
       , MonadThrow          m
       , MonadEtcd           m
       , MonadBaseControl IO m
       )
    => Key
    -> Maybe Text
    -> Word16
    -> TTL
    -> m a
    -> m a
withDoubleBarrier k v c t f
    = liftEtcd (enter k v c t)
  >>= onEntered f
  >>= (\(ml,a) -> liftEtcd (leave ml) *> return a)

onEntered
    :: ( MonadEtcd           m
       , MonadBaseControl IO m
       )
    => m a
    -> Entered (EtcdT m)
    -> m (MayLeave, a)
onEntered f (Entered eph waitReady)
    = race (liftEtcd (_ephHeartbeat eph))
           (liftEtcd waitReady >>= \ml -> (,) ml <$> f)
  >>= return . either absurd id

enter
    :: ( MonadIO         m
       , MonadThrow      m
       , MonadFree EtcdF m
       )
    => Key
    -> Maybe Text
    -> Word16
    -> TTL
    -> m (Entered m)
enter k v cnt t
    = fmap (\eph -> Entered eph (waitReady eph))
           (newUniqueEphemeralNode (k <> "/waiters") v t)
  where
    waitReady eph = do
        ls <- getKey (k <> "/waiters") getOptions { _getQuorum = True }
          >>= fmap (_nodeNodes . _rsNode . _rsBody) . hoistError

        if fromIntegral (length ls) >= cnt then
            putKey (k <> "/ready") putOptions >>= void . hoistError
        else
            watchReady (_nodeModifiedIndex . _ephNode $ eph)

        return $ MayLeave k (_nodeKey . _ephNode $ eph)

    watchReady idx = do
        rs <- watchKey (k <> "/ready") watchOptions { _watchWaitIndex = Just idx }
          >>= fmap _rsBody . hoistError
        case _rsAction rs of
            ActionSet -> return ()
            _         -> watchReady (_nodeModifiedIndex . _rsNode $ rs)


leave :: (MonadThrow m, MonadFree EtcdF m) => MayLeave -> m ()
leave (MayLeave k me) = do
    ls <- getKey (k <> "/waiters") getOptions { _getQuorum = True }
      >>= fmap (_nodeNodes . _rsNode . _rsBody) . hoistError

    case ls of
        []  -> return ()
        [x] | _nodeKey x == me -> deleteKey (_nodeKey x) deleteOptions >> return ()
            | otherwise        -> throwM $ ClientError (_nodeKey x <> " /= " <> me)
        xs  -> do
            let (Just lowest, Just highest) = minmax xs
            if _nodeKey lowest == me then
                watchDisappear highest >> leave (MayLeave k me)
            else do
                deleteKey me deleteOptions >>= void . hoistError
                watchDisappear lowest
                leave (MayLeave k me)
  where
    minmax = bimap (fmap unLM . getMin) (fmap unLM . getMax)
           . foldMap (\n -> let lm = Just (LM n) in (Min lm, Max lm))

    watchDisappear n = do
        rs <- watchKey (_nodeKey n)
                       watchOptions { _watchWaitIndex = Just (_nodeModifiedIndex n + 1) } -- why n+1 here?
          >>= fmap _rsBody . hoistError
        case _rsAction rs of
            ActionDelete -> return ()
            ActionExpire -> return ()
            _            -> watchDisappear (_rsNode rs)


newtype LastModified = LM { unLM :: Node }
    deriving Eq

instance Ord LastModified where
    compare = compare `on` _nodeModifiedIndex . unLM
