-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Data.Etcd.Recipes.PriorityQueue where

import Control.Monad.Catch
import Control.Monad.Trans.Free
import Data.Etcd.Free
import Data.Monoid                ((<>))
import Data.Text                  (Text)
import Data.Text.Lazy             (toStrict)
import Data.Text.Lazy.Builder     (fromText, singleton, toLazyText)
import Data.Text.Lazy.Builder.Int (decimal)
import Data.Word                  (Word16)


enqueue
    :: ( MonadThrow      m
       , MonadFree EtcdF m
       )
    => Key
    -> Maybe Text
    -> Word16
    -> m Node
enqueue k v p
    = postKey kp postOptions { _postValue = v }
  >>= fmap (_rsNode . _rsBody) . hoistError
  where
    kp = toStrict . toLazyText $ fromText k <> singleton '/' <> decimal p

dequeue :: (MonadThrow m, MonadFree EtcdF m) => Key -> m Node
dequeue k = do
    rs <- getKey k getOptions { _getRecursive = True, _getSorted = True }
      >>= fmap (_rsNode . _rsBody) . hoistError
    case concatMap _nodeNodes (_nodeNodes rs) of
        [] -> watchEnqueue (_nodeModifiedIndex rs)
        xs -> tryClaim xs
  where
    watchEnqueue idx = do
        rs <- watchKey k watchOptions { _watchRecursive = True
                                      , _watchWaitIndex = Just idx }
          >>= hoistError
        case _rsAction . _rsBody $ rs of
            ActionCreate -> claim (_rsNode . _rsBody $ rs)
                        >>= fmap (_rsNode . _rsBody) . hoistError
            _            -> watchEnqueue (_etcdIndex . _rsMeta $ rs)

    tryClaim []     = dequeue k
    tryClaim (x:xs) = claim x
                  >>= either (const (tryClaim xs)) (pure . _rsNode . _rsBody)

    claim n = deleteKey (_nodeKey n)
                        deleteOptions { _delPrevIndex = Just (_nodeModifiedIndex n) }
