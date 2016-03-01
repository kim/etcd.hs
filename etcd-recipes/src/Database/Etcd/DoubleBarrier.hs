-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE Rank2Types            #-}

module Database.Etcd.DoubleBarrier
    ( Entered
    , MayLeave

    , enter
    , leave

    , withDoubleBarrier
    , onEntered
    )
where

import Control.Concurrent.Async
import Control.Monad.Catch
import Control.Monad.IO.Class
import Control.Monad.Trans.Free
import Data.Bifunctor
import Data.Etcd.Free
import Data.Function            (on)
import Data.Monoid
import Data.Text                (Text)
import Data.Void                (absurd)
import Data.Word                (Word16)
import Database.Etcd.Util


data Entered  m = Entered  (EphemeralNode m) (m MayLeave)
data MayLeave   = MayLeave Key Key


withDoubleBarrier
    :: (forall b. EtcdF (IO b) -> IO b)
    -> Key
    -> Maybe Text
    -> Word16
    -> TTL
    -> FreeT EtcdF IO a
    -> IO a
withDoubleBarrier evalEtcd k v c t f
    = runEtcd (enter k v c t)
  >>= onEntered evalEtcd f
  >>= (\(ml,a) -> runEtcd (leave ml) *> return a)
  where
    runEtcd = iterT evalEtcd

onEntered
    :: (forall b. EtcdF (IO b) -> IO b)
    -> FreeT EtcdF IO a
    -> Entered (FreeT EtcdF IO)
    -> IO (MayLeave, a)
onEntered evalEtcd f (Entered eph waitReady)
    = race (runEtcd (ephHeartbeat eph))
           (runEtcd $ waitReady >>= \ml -> (,) ml <$> f)
  >>= return . either absurd id
  where
    runEtcd = iterT evalEtcd

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
enter k v cnt t = do
    eph <- newUniqueEphemeralNode (k <> "/waiters") v t
    case eph of
        Left  e -> throwM $ EtcdError e
        Right n -> return $ Entered n (waitReady n)
  where
    waitReady eph = do
        ls <- getKey (k <> "/waiters") getOptions { _gQuorum = True }
          >>= fmap (nodes . node) . successOrThrow

        if fromIntegral (length ls) >= cnt then
            putKey (k <> "/ready") putOptions >>= successOrThrow_
        else
            watchReady (modifiedIndex . ephNode $ eph)

        return $ MayLeave k (key . ephNode $ eph)

    watchReady idx = do
        rs <- watchKey (k <> "/ready") watchOptions { _wWaitIndex = Just idx }
          >>= successOrThrow
        case action rs of
            ActionSet -> return ()
            _         -> watchReady (modifiedIndex . node $ rs)


leave :: (MonadThrow m, MonadFree EtcdF m) => MayLeave -> m ()
leave (MayLeave k me) = do
    ls <- getKey (k <> "/waiters") getOptions { _gQuorum = True }
      >>= fmap (nodes . node) . successOrThrow

    case ls of
        []  -> return ()
        [x] | key x == me -> deleteKey (key x) deleteOptions
                          >> return ()
            | otherwise   -> error "impossible"
        xs  -> do
            let (Just lowest, Just highest) = minmax xs
            if key lowest == me then
                watchDisappear highest >> leave (MayLeave k me)
            else do
                deleteKey me deleteOptions >>= successOrThrow_
                watchDisappear lowest
                leave (MayLeave k me)
  where
    minmax = bimap (fmap unLM . getMin) (fmap unLM . getMax)
           . foldMap (\n -> let lm = Just (LM n) in (Min lm, Max lm))

    watchDisappear n = do
        rs <- watchKey (key n) watchOptions { _wWaitIndex = Just (modifiedIndex n + 1) } -- why n+1 here?
          >>= successOrThrow
        case action rs of
            ActionDelete -> return ()
            ActionExpire -> return ()
            _            -> watchDisappear (node rs)


newtype LastModified = LM { unLM :: Node }
    deriving Eq

instance Ord LastModified where
    compare = compare `on` modifiedIndex . unLM
