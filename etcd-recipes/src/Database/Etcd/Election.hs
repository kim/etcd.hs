-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE Rank2Types            #-}

module Database.Etcd.Election
    ( ElectionError (..)
    , Nomination
    , Promotion
    , Promoted

    , nominate
    , awaitPromotion

    , asLeader
    , onLeader
    )
where

import Control.Concurrent.Async
import Control.Monad.Catch
import Control.Monad.Free.Class
import Control.Monad.IO.Class
import Control.Monad.Trans.Free
import Data.Etcd.Free
import Data.Monoid
import Data.Text                (Text)
import Data.Void
import Database.Etcd.Util


data ElectionError
    = ElectionError ErrorResponse
    | Impossible    Text
    deriving (Eq, Show)

instance Exception ElectionError

data Nomination m = Nomination Key (EphemeralNode m)
data Promoted     = Promoted
data Promotion  m = Promotion (EphemeralNode m) (m Promoted)


asLeader
    :: (forall b. EtcdF (IO b) -> IO b)
    -> Key -> Maybe Text -> TTL -> IO a
    -> IO a
asLeader evalEtcd k v t f =
    iterT evalEtcd (nominate k v t >>= awaitPromotion) >>= onLeader evalEtcd f

onLeader
    :: (forall b. EtcdF (IO b) -> IO b)
    -> IO a
    -> Promotion (FreeT EtcdF IO)
    -> IO a
onLeader evalEtcd f (Promotion eph w)
    = race (runEtcd (ephHeartbeat eph)) (runEtcd w *> f)
  >>= return . either absurd id
  where
    runEtcd = iterT evalEtcd

nominate
    :: ( MonadIO         m
       , MonadThrow      m
       , MonadFree EtcdF m
       )
    => Key
    -> Maybe Text
    -> TTL
    -> m (Nomination m)
nominate k v t = do
    eph <- newUniqueEphemeralNode k v t
    case eph of
        Left  e -> throwM $ ElectionError e
        Right n -> return $ Nomination k n

awaitPromotion
    :: ( MonadIO         m
       , MonadThrow      m
       , MonadFree EtcdF m
       )
    => Nomination m
    -> m (Promotion m)
awaitPromotion (Nomination d eph) = return $ Promotion eph loop
  where
    myKey = key . ephNode $ eph

    loop = do
        rs <- getKey d getOptions { _gSorted = True, _gQuorum = True }
        ls <- nodes . node <$> successOrThrow ElectionError rs
        case span ((< myKey) . key) ls of
            ([],[]) -> throwM $ Impossible (d <> " does not contain any keys")

            ([],(x:_))
              | key x == myKey -> return Promoted
              | otherwise      -> throwM $ Impossible (key x <> " /= " <> myKey)

            (xs,_) -> watchPred (key (last xs)) (modifiedIndex . ephNode $ eph)

    watchPred p idx = do
        rs <- watchKey p watchOptions { _wRecursive = False, _wWaitIndex = Just idx }
          >>= successOrThrow ElectionError
        case action rs of
            ActionExpire -> loop
            ActionDelete -> loop
            _            -> watchPred p (modifiedIndex . node $ rs)
