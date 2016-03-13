-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE Rank2Types            #-}

module Data.Etcd.Recipes.Election
    ( Nomination
    , Promotion
    , Promoted

    , nominate
    , awaitPromotion

    , asLeader
    , onLeader
    )
where

import Control.Concurrent.Async.Lifted
import Control.Monad.Catch
import Control.Monad.Etcd              (MonadEtcd (..))
import Control.Monad.Free.Class
import Control.Monad.IO.Class
import Control.Monad.Trans.Control
import Control.Monad.Trans.Etcd
import Data.Etcd.Free
import Data.Etcd.Recipes.Ephemeral
import Data.Monoid
import Data.Text                       (Text)
import Data.Void


data Nomination m = Nomination Key (EphemeralNode m)
data Promoted     = Promoted
data Promotion  m = Promotion (EphemeralNode m) (m Promoted)


asLeader
    :: ( MonadIO             m
       , MonadThrow          m
       , MonadEtcd           m
       , MonadBaseControl IO m
       )
    => Key
    -> Maybe Text
    -> TTL
    -> m a
    -> m a
asLeader k v t f =
    liftEtcd (nominate k v t >>= awaitPromotion) >>= onLeader f

onLeader
    :: ( MonadEtcd           m
       , MonadBaseControl IO m
       )
    => m a
    -> Promotion (EtcdT m)
    -> m a
onLeader f (Promotion eph w)
    = race (liftEtcd (_ephHeartbeat eph)) (liftEtcd w *> f)
  >>= return . either absurd id

nominate
    :: ( MonadIO         m
       , MonadThrow      m
       , MonadFree EtcdF m
       )
    => Key
    -> Maybe Text
    -> TTL
    -> m (Nomination m)
nominate k v t = Nomination k <$> newUniqueEphemeralNode k v t

awaitPromotion
    :: ( MonadIO         m
       , MonadThrow      m
       , MonadFree EtcdF m
       )
    => Nomination m
    -> m (Promotion m)
awaitPromotion (Nomination d eph) = return $ Promotion eph loop
  where
    myKey = _nodeKey . _ephNode $ eph

    loop = do
        ls <- getKey d getOptions { _getSorted = True, _getQuorum = True }
          >>= fmap (_nodeNodes . _rsNode . _rsBody) . hoistError

        case span ((< myKey) . _nodeKey) ls of
            ([],[]) -> throwM $ ClientError (d <> " does not contain any keys")

            ([],(x:_))
              | _nodeKey x == myKey -> return Promoted
              | otherwise           -> throwM $ ClientError (_nodeKey x <> " /= " <> myKey)

            (xs,_) -> watchPred (_nodeKey (last xs)) (_nodeModifiedIndex . _ephNode $ eph)

    watchPred p idx = do
        rs <- watchKey p watchOptions { _watchRecursive = False
                                      , _watchWaitIndex = Just idx }
          >>= fmap _rsBody . hoistError
        case _rsAction rs of
            ActionExpire -> loop
            ActionDelete -> loop
            _            -> watchPred p (_nodeModifiedIndex . _rsNode $ rs)
