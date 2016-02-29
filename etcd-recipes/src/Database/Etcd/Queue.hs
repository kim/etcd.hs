-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Database.Etcd.Queue where

import Control.Monad.Trans.Free
import Data.Etcd.Free
import Data.Text                (Text)
import Database.Etcd.Util


enqueue :: MonadFree EtcdF m => Key -> Maybe Text -> m (Either ErrorResponse Node)
enqueue k v = do
    parent <- newDirectory k
    case parent of
        Left e -> return $ Left e
        _ -> do
            n <- postKey k postOptions { _cValue = v }
            return $ case responseBody n of
                Error   e -> Left  e
                Success s -> Right (node s)


dequeue :: MonadFree EtcdF m => Key -> m (Either ErrorResponse Node)
dequeue k = do
    ls <- getKey k getOptions { _gSorted = True }
    case responseBody ls of
        Error   e -> return $ Left e
        Success s -> case nodes (node s) of
            [] -> watchEnqueue (modifiedIndex (node s))
            xs -> tryClaim xs
  where
    watchEnqueue idx = do
        rs <- watchKey k watchOptions { _wWaitIndex = Just idx, _wRecursive = True }
        case responseBody rs of
            Error   e -> return $ Left e
            Success s -> case action s of
                ActionCreate -> claim (node s)
                _            -> watchEnqueue (etcdIndex rs)

    tryClaim []     = dequeue k
    tryClaim (x:xs) = claim x >>= either (const (tryClaim xs)) (pure . Right)

    claim n = do
        rs <- deleteKey (key n) deleteOptions { _dPrevIndex = Just (modifiedIndex n) }
        return $ case responseBody rs of
            Error   e -> Left  e
            Success s -> Right (node s)
