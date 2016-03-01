-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Database.Etcd.Util
    ( EphemeralNode (ephNode, ephHeartbeat)
    , Heartbeat

    , newDirectory
    , newUniqueEphemeralNode

    , successOrThrow
    , successOrThrow_

    , Min (..)
    , Max (..)
    )
where

import Control.Concurrent       (threadDelay)
import Control.Monad.Catch
import Control.Monad.IO.Class
import Control.Monad.Trans.Free
import Data.Etcd.Free
import Data.Maybe               (fromMaybe)
import Data.Text                (Text)
import Data.Void


type Heartbeat     m = m Void
data EphemeralNode m = EphemeralNode
    { ephNode      :: Node
    , ephHeartbeat :: Heartbeat m
    }

data EphemeralNodeError = EphemeralNodeError ErrorResponse
    deriving (Eq, Show)

instance Exception EphemeralNodeError


newDirectory :: MonadFree EtcdF m => Key -> m (Either ErrorResponse ())
newDirectory k = do
    d <- putKey k (putOptions { _pDir = True })
    case responseBody d of
        Error e | errorCode e /= 102 -> return $ Left e
        _ -> return $ Right ()

newUniqueEphemeralNode
    :: ( MonadIO         m
       , MonadThrow      m
       , MonadFree EtcdF m
       )
    => Key
    -> Maybe Text
    -> TTL
    -> m (Either ErrorResponse (EphemeralNode m))
newUniqueEphemeralNode k v t = do
    parent <- newDirectory k
    case parent of
        Left e -> return $ Left e
        _ -> do
            eph <- postKey k (postOptions { _cValue = v, _cTTL = Just t })
            return $ case responseBody eph of
                Error   e -> Left e
                Success s -> Right (EphemeralNode (node s) (heartbeat (node s)))

heartbeat
    :: ( MonadIO          m
       , MonadThrow       m
       , MonadFree  EtcdF m
       )
    => Node
    -> Heartbeat m
heartbeat = loop
  where
    loop n = do
        rs <- putKey (key n)
                     putOptions { _pTTL       = Just (SomeTTL (ttlOf n + 1))
                                , _pRefresh   = True
                                , _pPrevIndex = Just (modifiedIndex n)
                                }
          >>= successOrThrow EphemeralNodeError
        liftIO $ threadDelay (fromIntegral (ttlOf n) * 1000000)
        loop (node rs)


    ttlOf = fromMaybe 1 . ttl


successOrThrow
    :: ( Exception  e
       , MonadThrow m
       )
    => (ErrorResponse -> e)
    -> Response
    -> m SuccessResponse
successOrThrow f r = case responseBody r of
    Error   e -> throwM $ f e
    Success s -> pure s

successOrThrow_
    :: ( Exception  e
       , MonadThrow m
       )
    => (ErrorResponse -> e)
    -> Response
    -> m ()
successOrThrow_ f r = case responseBody r of
    Error e -> throwM $ f e
    _       -> pure ()


newtype Max a = Max { getMax :: Maybe a }
newtype Min a = Min { getMin :: Maybe a }

instance Ord a => Monoid (Max a) where
    mempty = Max Nothing

    {-# INLINE mappend #-}
    m `mappend` Max Nothing = m
    Max Nothing `mappend` n = n
    (Max m@(Just x)) `mappend` (Max n@(Just y))
      | x >= y    = Max m
      | otherwise = Max n

instance Ord a => Monoid (Min a) where
  mempty = Min Nothing

  {-# INLINE mappend #-}
  m `mappend` Min Nothing = m
  Min Nothing `mappend` n = n
  (Min m@(Just x)) `mappend` (Min n@(Just y))
    | x <= y    = Min m
    | otherwise = Min n