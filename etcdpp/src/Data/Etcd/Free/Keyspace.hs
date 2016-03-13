-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveFunctor         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Data.Etcd.Free.Keyspace where

import Control.Monad.Free.Class
import Data.Etcd.Types


data KeyspaceF a
    = GetKey    Key GetOptions    (Response -> a)
    | PutKey    Key PutOptions    (Response -> a)
    | PostKey   Key PostOptions   (Response -> a)
    | DeleteKey Key DeleteOptions (Response -> a)
    | WatchKey  Key WatchOptions  (Response -> a)
    | KeyExists Key               (Bool     -> a)
    deriving Functor


getKey :: MonadFree KeyspaceF m => Key -> GetOptions -> m Response
getKey k o = liftF $ GetKey k o id

putKey :: MonadFree KeyspaceF m => Key -> PutOptions -> m Response
putKey k o = liftF $ PutKey k o id

postKey :: MonadFree KeyspaceF m => Key -> PostOptions -> m Response
postKey k o = liftF $ PostKey k o id

deleteKey :: MonadFree KeyspaceF m => Key -> DeleteOptions -> m Response
deleteKey k o = liftF $ DeleteKey k o id

watchKey :: MonadFree KeyspaceF m => Key -> WatchOptions -> m Response
watchKey k o = liftF $ WatchKey k o id

keyExists :: MonadFree KeyspaceF m => Key -> m Bool
keyExists k = liftF $ KeyExists k id
