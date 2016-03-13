-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ViewPatterns          #-}

module Data.Etcd.Recipes.Ephemeral
    ( EphemeralNode (_ephNode, _ephHeartbeat)
    , Heartbeat

    , newUniqueEphemeralNode
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
    { _ephNode      :: Node
    , _ephHeartbeat :: Heartbeat m
    }

newUniqueEphemeralNode
    :: ( MonadIO         m
       , MonadThrow      m
       , MonadFree EtcdF m
       )
    => Key
    -> Maybe Text
    -> TTL
    -> m (EphemeralNode m)
newUniqueEphemeralNode k v t
    = postKey k (postOptions { _postValue = v, _postTTL = Just t })
  >>= fmap mkEph . hoistError
  where
    mkEph (_rsNode . _rsBody -> n) = EphemeralNode n (heartbeat n)

heartbeat
    :: ( MonadIO         m
       , MonadThrow      m
       , MonadFree EtcdF m
       )
    => Node
    -> Heartbeat m
heartbeat = loop
  where
    loop n = do
        rs <- putKey (_nodeKey n)
                     putOptions { _putTTL       = Just (SomeTTL (ttlOf n + 1))
                                , _putRefresh   = True
                                , _putPrevIndex = Just (_nodeModifiedIndex n)
                                }
          >>= hoistError
        liftIO $ threadDelay (fromIntegral (ttlOf n) * 1000000)
        loop (_rsNode . _rsBody $ rs)


    ttlOf = fromMaybe 1 . _nodeTTL
