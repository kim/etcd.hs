-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DeriveFunctor         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Data.Etcd.Free.Misc where

import Control.Monad.Free.Class
import Data.Etcd.Types


data MiscF a
    = GetVersion (Version -> a)
    | GetHealth  (Health  -> a)
    deriving Functor


getVersion :: MonadFree MiscF m => m Version
getVersion = liftF $ GetVersion id

getHealth :: MonadFree MiscF m => m Health
getHealth = liftF $ GetHealth id
