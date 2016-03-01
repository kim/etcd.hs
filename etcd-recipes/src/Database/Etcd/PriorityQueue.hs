-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Database.Etcd.PriorityQueue where

import Control.Monad.Trans.Free
import Data.Etcd.Free
import Data.Monoid                ((<>))
import Data.Text                  (Text)
import Data.Text.Lazy             (toStrict)
import Data.Text.Lazy.Builder     (fromText, singleton, toLazyText)
import Data.Text.Lazy.Builder.Int (decimal)
import Data.Word                  (Word16)


enqueue :: MonadFree EtcdF m => Key -> Maybe Text -> Word16 -> m (Either ErrorResponse Node)
enqueue k v p = do
    n <- postKey kp postOptions { _cValue = v }
    return $ case responseBody n of
        Error   e -> Left  e
        Success s -> Right (node s)
  where
    kp = toStrict . toLazyText $ fromText k <> singleton '/' <> decimal p

dequeue :: MonadFree EtcdF m => Key -> m (Either ErrorResponse Node)
dequeue k = do
    ls <- getKey k getOptions { _gRecursive = True, _gSorted = True }
    case responseBody ls of
        Error   e -> return $ Left e
        Success s -> case concatMap nodes (nodes . node $ s) of
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
